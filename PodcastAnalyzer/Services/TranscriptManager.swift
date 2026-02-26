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

/// Manages background transcript generation with parallel processing.
///
/// Explicit `@MainActor` because all state (`activeJobs`, `pendingJobs`, etc.) drives
/// UI observation via `@Observable`.  Heavy work is delegated to `TranscriptService`
/// and `WhisperTranscriptService` (both actors), so `await`-ing their methods
/// automatically suspends the caller and runs on the actor's executor.
@available(iOS 17.0, *)
@MainActor
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
  private let maxConcurrentJobs: Int = {
    let processorCount = ProcessInfo.processInfo.processorCount
    return min(max(processorCount / 2, 2), 4)
  }()

  // Queue for pending jobs
  private var pendingJobs: [TranscriptJob] = []
  private var runningJobIds: Set<String> = []
  private var processingTasks: [String: Task<Void, Never>] = [:]

  private init() {}

  // No deinit needed — TranscriptManager is a singleton (static let shared)
  // that lives for the app's lifetime. Tasks are cancelled via cancelAll().

  // MARK: - Public API

  /// Queues a transcript generation job
  func queueTranscript(
    episodeTitle: String, podcastTitle: String, audioPath: String, language: String
  ) {
    let jobId = makeJobId(podcastTitle: podcastTitle, episodeTitle: episodeTitle)

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
    startProcessingIfNeeded()
  }

  /// Checks if a transcript is being generated for an episode
  func isGenerating(episodeTitle: String, podcastTitle: String) -> Bool {
    let jobId = makeJobId(podcastTitle: podcastTitle, episodeTitle: episodeTitle)

    if pendingJobs.contains(where: { $0.id == jobId }) || runningJobIds.contains(jobId) {
      return true
    }

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

    pendingJobs.removeAll { $0.id == jobId }
    activeJobs.removeValue(forKey: jobId)

    if runningJobIds.contains(jobId) {
      processingTasks[jobId]?.cancel()
      processingTasks.removeValue(forKey: jobId)
      runningJobIds.remove(jobId)
      logger.info("Cancelled running transcript job for: \(episodeTitle)")

      if runningJobIds.isEmpty && pendingJobs.isEmpty {
        isProcessing = false
      }
    }
  }

  // MARK: - Processing

  private func startProcessingIfNeeded() {
    while runningJobIds.count < maxConcurrentJobs && !pendingJobs.isEmpty {
      let job = pendingJobs.removeFirst()
      runningJobIds.insert(job.id)
      isProcessing = true

      let task = Task { [weak self] in
        guard let self else { return }
        await self.processJob(job)
      }
      processingTasks[job.id] = task
    }
  }

  private func processJob(_ job: TranscriptJob) async {
    var updatedJob = job
    updatedJob.status = .downloadingModel(progress: 0)
    activeJobs[job.id] = updatedJob

    let engine = TranscriptEngine(
      rawValue: UserDefaults.standard.string(forKey: "transcriptEngine") ?? ""
    ) ?? .appleSpeech

    do {
      let audioURL = URL(fileURLWithPath: job.audioPath)
      guard FileManager.default.fileExists(atPath: job.audioPath) else {
        throw NSError(
          domain: "TranscriptManager", code: 3,
          userInfo: [NSLocalizedDescriptionKey: "Audio file not found: \(job.audioPath)"]
        )
      }

      switch engine {

      // MARK: Apple Speech path
      case .appleSpeech:
        let transcriptService = TranscriptService(language: job.language)

        let modelReady = await transcriptService.isModelReady()
        if !modelReady {
          for await progress in await transcriptService.setupAndInstallAssets() {
            activeJobs[job.id]?.status = .downloadingModel(progress: progress)
          }
        } else {
          for await _ in await transcriptService.setupAndInstallAssets() {}
        }

        guard await transcriptService.isInitialized() else {
          throw NSError(
            domain: "TranscriptManager", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Failed to initialize Apple Speech service"]
          )
        }

        activeJobs[job.id]?.status = .transcribing(progress: 0)

        var finalSRTContent: String?
        for try await progressUpdate in await transcriptService.audioToSRTChunkedWithProgress(
          inputFile: audioURL)
        {
          activeJobs[job.id]?.status = .transcribing(progress: progressUpdate.progress)
          if progressUpdate.isComplete {
            finalSRTContent = progressUpdate.srtContent
          }
        }

        guard let srtContent = finalSRTContent else {
          throw NSError(
            domain: "TranscriptManager", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Transcription produced no content"]
          )
        }

        _ = try await fileStorage.saveCaptionFile(
          content: srtContent,
          episodeTitle: job.episodeTitle,
          podcastTitle: job.podcastTitle
        )

      // MARK: Whisper path (WhisperKit)
      case .whisper:
        let modelVariant = WhisperModelManager.shared.selectedModel

        if !WhisperModelManager.modelExistsOnDisk(modelVariant) {
          do {
            try await WhisperTranscriptService.downloadModel(
              variant: modelVariant,
              onProgress: { [weak self] progress in
                Task { @MainActor in
                  self?.activeJobs[job.id]?.status = .downloadingModel(progress: progress)
                }
              }
            )
          } catch {
            throw NSError(
              domain: "TranscriptManager", code: 4,
              userInfo: [
                NSLocalizedDescriptionKey:
                  "Whisper model download failed: \(error.localizedDescription)"
              ]
            )
          }
        }

        activeJobs[job.id]?.status = .transcribing(progress: 0)

        let whisperService = WhisperTranscriptService()
        var finalSRTContent: String?

        for try await progressUpdate in await whisperService.audioToSRTWithProgress(
          inputFile: audioURL,
          modelVariant: modelVariant)
        {
          activeJobs[job.id]?.status = .transcribing(progress: progressUpdate.progress)
          if progressUpdate.isComplete {
            finalSRTContent = progressUpdate.srtContent
          }
        }

        guard let srtContent = finalSRTContent else {
          throw NSError(
            domain: "TranscriptManager", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Whisper transcription produced no content"]
          )
        }

        _ = try await fileStorage.saveCaptionFile(
          content: srtContent,
          episodeTitle: job.episodeTitle,
          podcastTitle: job.podcastTitle
        )
      }

      // MARK: Completion (shared)
      activeJobs[job.id]?.status = .completed
      logger.info("Transcript completed for: \(job.episodeTitle)")

      try? await Task.sleep(for: .seconds(3))
      activeJobs.removeValue(forKey: job.id)

    } catch {
      activeJobs[job.id]?.status = .failed(error: error.localizedDescription)
      logger.error("Transcript failed for \(job.episodeTitle): \(error.localizedDescription)")
    }

    runningJobIds.remove(job.id)
    processingTasks.removeValue(forKey: job.id)
    if runningJobIds.isEmpty && pendingJobs.isEmpty {
      isProcessing = false
    }
    startProcessingIfNeeded()
  }
}
