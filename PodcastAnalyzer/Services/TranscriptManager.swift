//
//  TranscriptManager.swift
//  PodcastAnalyzer
//
//  Manages background transcript generation across the app
//

import Foundation
import SwiftData
import OSLog

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
  let id: String  // podcastTitle + Unit Separator + episodeTitle (same format as episode keys)
  let episodeTitle: String
  let podcastTitle: String
  let audioPath: String
  let language: String
  var status: TranscriptJobStatus = .queued
}

/// Manages background transcript generation with parallel processing
@available(iOS 17.0, *)
@Observable
class TranscriptManager {
  static let shared = TranscriptManager()

  // Use Unit Separator (U+001F) as delimiter - same as DownloadManager for consistency
  private static let episodeKeyDelimiter = "\u{1F}"

  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "TranscriptManager")
  private let fileStorage = FileStorageManager.shared
  
  // Helper to create job ID matching episode key format
  private func makeJobId(podcastTitle: String, episodeTitle: String) -> String {
    return "\(podcastTitle)\(Self.episodeKeyDelimiter)\(episodeTitle)"
  }

  var activeJobs: [String: TranscriptJob] = [:]
  var isProcessing: Bool = false

  // Maximum concurrent transcript jobs
  // Increased for better performance on modern devices
  // Speech framework can handle multiple concurrent transcriptions efficiently
  private let maxConcurrentJobs: Int = {
    // Use more concurrent jobs on devices with more CPU cores
    let processorCount = ProcessInfo.processInfo.processorCount
    // Cap at 4 to avoid overwhelming the system
    return min(max(processorCount / 2, 2), 4)
  }()
  
  // Queue for pending jobs
  private var pendingJobs: [TranscriptJob] = []
  private var runningJobIds: Set<String> = []
  private var processingTasks: [String: Task<Void, Never>] = [:]

  private init() {}

  // MARK: - Public API

  /// Queues a transcript generation job
  /// - Parameters:
  ///   - episodeTitle: Title of the episode
  ///   - podcastTitle: Title of the podcast
  ///   - audioPath: Local path to the audio file
  ///   - language: Language code for transcription
  func queueTranscript(
    episodeTitle: String, podcastTitle: String, audioPath: String, language: String
  ) {
    let jobId = makeJobId(podcastTitle: podcastTitle, episodeTitle: episodeTitle)

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
    let jobId = makeJobId(podcastTitle: podcastTitle, episodeTitle: episodeTitle)

    // Check if in pending queue or actively running
    if pendingJobs.contains(where: { $0.id == jobId }) || runningJobIds.contains(jobId) {
      return true
    }

    // Also check active jobs status
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
    let jobId = makeJobId(podcastTitle: podcastTitle, episodeTitle: episodeTitle)
    return activeJobs[jobId]?.status
  }

  /// Cancels a pending or active transcript job
  func cancelJob(episodeTitle: String, podcastTitle: String) {
    let jobId = makeJobId(podcastTitle: podcastTitle, episodeTitle: episodeTitle)

    // Remove from pending
    pendingJobs.removeAll { $0.id == jobId }
    activeJobs.removeValue(forKey: jobId)

    // If this job is currently running, cancel the task
    if runningJobIds.contains(jobId) {
      processingTasks[jobId]?.cancel()
      processingTasks.removeValue(forKey: jobId)
      runningJobIds.remove(jobId)
      logger.info("Cancelled running transcript job for: \(episodeTitle)")

      // Update isProcessing flag
      if runningJobIds.isEmpty && pendingJobs.isEmpty {
        isProcessing = false
      }
    }
  }

  // MARK: - Processing

  private func startProcessingIfNeeded() {
    // Start as many jobs as we can up to the concurrent limit
    while runningJobIds.count < maxConcurrentJobs && !pendingJobs.isEmpty {
      let job = pendingJobs.removeFirst()
      runningJobIds.insert(job.id)
      isProcessing = true

      let task = Task { [weak self] in
        guard let self = self else { return }
        await self.processJob(job)
      }
      processingTasks[job.id] = task
    }
  }

  private func processJob(_ job: TranscriptJob) async {
    await MainActor.run {
      var updatedJob = job
      updatedJob.status = .downloadingModel(progress: 0)
      activeJobs[job.id] = updatedJob
    }

    // Use Task.detached to ensure CPU-intensive work runs on a background thread
    // This prevents blocking the main actor and allows better parallelization
    await Task.detached(priority: .userInitiated) { [weak self] in
      guard let self = self else { return }
      
      do {
        // Verify audio file exists before starting
        let audioURL = URL(fileURLWithPath: job.audioPath)
        guard FileManager.default.fileExists(atPath: job.audioPath) else {
          throw NSError(
            domain: "TranscriptManager", code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Audio file not found: \(job.audioPath)"]
          )
        }
        
        // Create a fresh TranscriptService for each job to avoid state issues
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

        // CPU-intensive transcription work happens here
        // Task.detached ensures this runs on a background thread
        for try await progressUpdate in await transcriptService.audioToSRTWithProgress(
          inputFile: audioURL)
        {
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
            userInfo: [
              NSLocalizedDescriptionKey: "Transcription completed but no content was generated"
            ]
          )
        }

        // Save the transcript (file I/O can also benefit from background thread)
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
        _ = await MainActor.run {
          self.activeJobs.removeValue(forKey: job.id)
        }

      } catch {
        await MainActor.run {
          var updatedJob = job
          updatedJob.status = .failed(error: error.localizedDescription)
          self.activeJobs[job.id] = updatedJob
          self.logger.error(
            "Transcript failed for \(job.episodeTitle): \(error.localizedDescription)")
        }
      }

      // Job completed - clean up and check for more pending jobs
      await MainActor.run {
        self.runningJobIds.remove(job.id)
        self.processingTasks.removeValue(forKey: job.id)

        // Update isProcessing flag
        if self.runningJobIds.isEmpty && self.pendingJobs.isEmpty {
          self.isProcessing = false
        }

        // Start next job if there are pending ones
        self.startProcessingIfNeeded()
      }
    }.value
  }
}
