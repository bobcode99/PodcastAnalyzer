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
  case checkingCloudKit                        // NEW: Checking if transcript exists in CloudKit
  case downloadingFromCloudKit(progress: Double)  // NEW: Downloading from CloudKit
  case downloadingModel(progress: Double)
  case transcribing(progress: Double)
  case uploadingToCloudKit(progress: Double)    // NEW: Uploading to CloudKit
  case completed
  case failed(error: String)
}

/// Represents a transcript generation job
struct TranscriptJob: Identifiable {
  let id: String  // podcastTitle + Unit Separator + episodeTitle (same format as episode keys)
  let episodeTitle: String
  let podcastTitle: String
  let audioPath: String
  let audioURL: String? // Episode audio URL for CloudKit lookup
  let language: String
  var status: TranscriptJobStatus = .queued
  var source: TranscriptCacheMetadata.TranscriptSource = .localGeneration
}

/// Manages background transcript generation with parallel processing
@available(iOS 17.0, *)
class TranscriptManager: ObservableObject {
  static let shared = TranscriptManager()

  // Use Unit Separator (U+001F) as delimiter - same as DownloadManager for consistency
  private static let episodeKeyDelimiter = "\u{1F}"

  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "TranscriptManager")
  private let fileStorage = FileStorageManager.shared

  // CloudKit integration (optional - check availability at runtime)
  private let cloudKitService = CloudKitTranscriptService()

  // Helper to create job ID matching episode key format
  private func makeJobId(podcastTitle: String, episodeTitle: String) -> String {
    return "\(podcastTitle)\(Self.episodeKeyDelimiter)\(episodeTitle)"
  }

  // Published state for UI observation
  @Published var activeJobs: [String: TranscriptJob] = [:]
  @Published var isProcessing: Bool = false
  @Published var cloudKitEnabled: Bool = UserDefaults.standard.bool(forKey: "CloudKitTranscriptSyncEnabled")

  // Maximum concurrent transcript jobs
  private let maxConcurrentJobs = 2

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
  ///   - audioURL: Episode audio URL for CloudKit lookup (optional)
  ///   - language: Language code for transcription
  func queueTranscript(
    episodeTitle: String,
    podcastTitle: String,
    audioPath: String,
    audioURL: String? = nil,
    language: String
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
      audioURL: audioURL,
      language: language
    )

    pendingJobs.append(job)
    activeJobs[jobId] = job

    logger.info("Queued transcript job for: \(episodeTitle)")

    // Start processing if not already running
    startProcessingIfNeeded()
  }

  /// Enable or disable CloudKit sync
  func setCloudKitEnabled(_ enabled: Bool) {
    cloudKitEnabled = enabled
    UserDefaults.standard.set(enabled, forKey: "CloudKitTranscriptSyncEnabled")
    logger.info("CloudKit sync \(enabled ? "enabled" : "disabled")")
  }

  /// Get CloudKit statistics
  func getCloudKitStats() async -> CloudKitTranscriptStats {
    await cloudKitService.getStats()
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
    var updatedJob = job

    do {
      // STEP 1: Check CloudKit first if enabled and audioURL available
      if cloudKitEnabled, let episodeURL = job.audioURL {
        await MainActor.run {
          updatedJob.status = .checkingCloudKit
          activeJobs[job.id] = updatedJob
        }

        logger.info("Checking CloudKit for existing transcript: \(job.episodeTitle)")

        // Check if transcript exists in CloudKit
        if let sharedTranscript = try? await cloudKitService.findTranscript(forEpisodeURL: episodeURL) {
          logger.info("Found transcript in CloudKit! Downloading...")

          // Download from CloudKit
          for try await progress in await cloudKitService.downloadTranscript(sharedTranscript) {
            await MainActor.run {
              updatedJob.status = .downloadingFromCloudKit(progress: progress.progress)
              activeJobs[job.id] = updatedJob
            }

            // Download complete
            if progress.progress >= 1.0, let content = progress.content {
              // Save to local storage
              _ = try await fileStorage.saveCaptionFile(
                content: content,
                episodeTitle: job.episodeTitle,
                podcastTitle: job.podcastTitle
              )

              await MainActor.run {
                updatedJob.status = .completed
                updatedJob.source = .cloudKitDownload
                activeJobs[job.id] = updatedJob
                logger.info("Downloaded transcript from CloudKit: \(job.episodeTitle)")
              }

              // Early return - no need to generate locally!
              await finishJob(updatedJob)
              return
            }
          }
        } else {
          logger.info("No transcript found in CloudKit, generating locally")
        }
      }

      // STEP 2: Generate locally (only if CloudKit didn't provide it)
      await MainActor.run {
        updatedJob.status = .downloadingModel(progress: 0)
        activeJobs[job.id] = updatedJob
      }

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

      // Save the transcript locally
      _ = try await fileStorage.saveCaptionFile(
        content: srtContent,
        episodeTitle: job.episodeTitle,
        podcastTitle: job.podcastTitle
      )

      // STEP 3: Upload to CloudKit if enabled and audioURL available
      if cloudKitEnabled, let episodeURL = job.audioURL {
        logger.info("Uploading transcript to CloudKit: \(job.episodeTitle)")

        await MainActor.run {
          updatedJob.status = .uploadingToCloudKit(progress: 0)
          activeJobs[job.id] = updatedJob
        }

        // Get audio duration for validation (estimate from file if needed)
        let audioDuration: TimeInterval = 0 // TODO: Get from episode metadata if available

        let sharedTranscript = SharedTranscript(
          episodeAudioURL: episodeURL,
          episodeTitle: job.episodeTitle,
          podcastTitle: job.podcastTitle,
          language: job.language,
          transcriptContent: srtContent,
          audioDuration: audioDuration
        )

        // Upload to CloudKit (non-blocking, fire and forget)
        Task {
          do {
            for try await uploadProgress in await cloudKitService.uploadTranscript(sharedTranscript) {
              await MainActor.run {
                updatedJob.status = .uploadingToCloudKit(progress: uploadProgress.progress)
                activeJobs[job.id] = updatedJob
              }

              if uploadProgress.progress >= 1.0 {
                logger.info("Successfully uploaded transcript to CloudKit")
              }
            }
          } catch {
            logger.warning("Failed to upload to CloudKit: \(error.localizedDescription)")
            // Don't fail the job - local transcript is already saved
          }
        }
      }

      await MainActor.run {
        updatedJob.status = .completed
        updatedJob.source = .localGeneration
        self.activeJobs[job.id] = updatedJob
        self.logger.info("Transcript completed for: \(job.episodeTitle)")
      }

      // Finish job cleanup
      await finishJob(updatedJob)

    } catch {
      await MainActor.run {
        updatedJob.status = .failed(error: error.localizedDescription)
        self.activeJobs[job.id] = updatedJob
        self.logger.error(
          "Transcript failed for \(job.episodeTitle): \(error.localizedDescription)")
      }

      await finishJob(updatedJob)
    }
  }

  /// Finish job and clean up
  private func finishJob(_ job: TranscriptJob) async {
    // Remove from active jobs after a short delay
    try? await Task.sleep(for: .seconds(3))

    await MainActor.run {
      self.activeJobs.removeValue(forKey: job.id)
      self.runningJobIds.remove(job.id)
      self.processingTasks.removeValue(forKey: job.id)

      // Update isProcessing flag
      if self.runningJobIds.isEmpty && self.pendingJobs.isEmpty {
        self.isProcessing = false
      }

      // Start next job if there are pending ones
      self.startProcessingIfNeeded()
    }
  }
}
