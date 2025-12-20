//
//  TranscriptManager.swift
//  PodcastAnalyzer
//
//  Manages background transcript generation across the app
//

import Combine
import Foundation
import SwiftData
import os.log

/// Tracks the status of a transcript generation job
enum TranscriptJobStatus: Equatable {
    case queued
    case downloadingModel(progress: Double)
    case transcribing(progress: Double)
    case completed
    case failed(error: String)
}

/// Represents a transcript generation job
struct TranscriptJob: Identifiable {
    let id: String  // podcastTitle|episodeTitle
    let episodeTitle: String
    let podcastTitle: String
    let audioPath: String
    let language: String
    var status: TranscriptJobStatus = .queued
}

/// Manages background transcript generation
@available(iOS 17.0, *)
class TranscriptManager: ObservableObject {
    static let shared = TranscriptManager()

    private let logger = Logger(subsystem: "com.podcast.analyzer", category: "TranscriptManager")
    private let fileStorage = FileStorageManager.shared

    // Published state for UI observation
    @Published var activeJobs: [String: TranscriptJob] = [:]
    @Published var isProcessing: Bool = false

    // Queue for pending jobs
    private var pendingJobs: [TranscriptJob] = []
    private var currentJob: TranscriptJob?
    private var processingTask: Task<Void, Never>?

    private init() {}

    // MARK: - Public API

    /// Queues a transcript generation job
    /// - Parameters:
    ///   - episodeTitle: Title of the episode
    ///   - podcastTitle: Title of the podcast
    ///   - audioPath: Local path to the audio file
    ///   - language: Language code for transcription
    func queueTranscript(episodeTitle: String, podcastTitle: String, audioPath: String, language: String) {
        let jobId = "\(podcastTitle)|\(episodeTitle)"

        // Check if already queued or processing
        if activeJobs[jobId] != nil {
            logger.info("Transcript job already exists for: \(episodeTitle)")
            return
        }

        let job = TranscriptJob(
            id: jobId,
            episodeTitle: episodeTitle,
            podcastTitle: podcastTitle,
            audioPath: audioPath,
            language: language
        )

        pendingJobs.append(job)
        activeJobs[jobId] = job

        logger.info("Queued transcript job for: \(episodeTitle)")

        // Start processing if not already running
        startProcessingIfNeeded()
    }

    /// Checks if a transcript is being generated for an episode
    func isGenerating(episodeTitle: String, podcastTitle: String) -> Bool {
        let jobId = "\(podcastTitle)|\(episodeTitle)"
        if let job = activeJobs[jobId] {
            switch job.status {
            case .queued, .downloadingModel, .transcribing:
                return true
            case .completed, .failed:
                return false
            }
        }
        return false
    }

    /// Gets the current status of a transcript job
    func getJobStatus(episodeTitle: String, podcastTitle: String) -> TranscriptJobStatus? {
        let jobId = "\(podcastTitle)|\(episodeTitle)"
        return activeJobs[jobId]?.status
    }

    /// Cancels a pending or active transcript job
    func cancelJob(episodeTitle: String, podcastTitle: String) {
        let jobId = "\(podcastTitle)|\(episodeTitle)"

        // Remove from pending
        pendingJobs.removeAll { $0.id == jobId }
        activeJobs.removeValue(forKey: jobId)

        // If this is the current job, we can't cancel the transcription itself
        // but we can mark it as cancelled
        if currentJob?.id == jobId {
            logger.info("Cannot cancel active transcription, will complete but discard result")
        }
    }

    // MARK: - Processing

    private func startProcessingIfNeeded() {
        guard !isProcessing, !pendingJobs.isEmpty else { return }

        isProcessing = true
        processingTask = Task { [weak self] in
            await self?.processNextJob()
        }
    }

    private func processNextJob() async {
        guard !pendingJobs.isEmpty else {
            await MainActor.run {
                isProcessing = false
            }
            return
        }

        let job = pendingJobs.removeFirst()
        currentJob = job

        await MainActor.run {
            var updatedJob = job
            updatedJob.status = .downloadingModel(progress: 0)
            activeJobs[job.id] = updatedJob
        }

        do {
            let audioURL = URL(fileURLWithPath: job.audioPath)
            let transcriptService = TranscriptService(language: job.language)

            // Check if model is ready
            let modelReady = await transcriptService.isModelReady()

            if !modelReady {
                for await progress in await transcriptService.setupAndInstallAssets() {
                    await MainActor.run {
                        var updatedJob = job
                        updatedJob.status = .downloadingModel(progress: progress)
                        self.activeJobs[job.id] = updatedJob
                    }
                }
            } else {
                // Still need to call setup to initialize
                for await _ in await transcriptService.setupAndInstallAssets() {
                    // Consume progress
                }
            }

            guard await transcriptService.isInitialized() else {
                throw NSError(
                    domain: "TranscriptManager", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to initialize transcription service"]
                )
            }

            // Start transcription
            await MainActor.run {
                var updatedJob = job
                updatedJob.status = .transcribing(progress: 0)
                self.activeJobs[job.id] = updatedJob
            }

            var finalSRTContent: String?

            for try await progressUpdate in await transcriptService.audioToSRTWithProgress(inputFile: audioURL) {
                await MainActor.run {
                    var updatedJob = job
                    updatedJob.status = .transcribing(progress: progressUpdate.progress)
                    self.activeJobs[job.id] = updatedJob
                }

                if progressUpdate.isComplete {
                    finalSRTContent = progressUpdate.srtContent
                }
            }

            guard let srtContent = finalSRTContent else {
                throw NSError(
                    domain: "TranscriptManager", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Transcription completed but no content was generated"]
                )
            }

            // Save the transcript
            _ = try await fileStorage.saveCaptionFile(
                content: srtContent,
                episodeTitle: job.episodeTitle,
                podcastTitle: job.podcastTitle
            )

            await MainActor.run {
                var updatedJob = job
                updatedJob.status = .completed
                self.activeJobs[job.id] = updatedJob
                self.logger.info("Transcript completed for: \(job.episodeTitle)")
            }

            // Remove from active jobs after a short delay
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run {
                self.activeJobs.removeValue(forKey: job.id)
            }

        } catch {
            await MainActor.run {
                var updatedJob = job
                updatedJob.status = .failed(error: error.localizedDescription)
                self.activeJobs[job.id] = updatedJob
                self.logger.error("Transcript failed for \(job.episodeTitle): \(error.localizedDescription)")
            }
        }

        currentJob = nil

        // Process next job
        await processNextJob()
    }
}
