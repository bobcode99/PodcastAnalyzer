//
//  TranscriptGenerationViewModel.swift
//  PodcastAnalyzer
//
//  ViewModel for transcript generation - handles speech-to-text processing
//

import SwiftData
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.podcast.analyzer", category: "TranscriptGeneration")

// MARK: - Transcript State

enum TranscriptState: Equatable {
  case idle
  case downloadingModel(progress: Double)
  case transcribing(progress: Double)
  case completed
  case error(String)
}

// MARK: - ViewModel

@MainActor
@Observable
class TranscriptGenerationViewModel {
  var state: TranscriptState = .idle
  var transcriptText: String = ""
  var showCopySuccess: Bool = false
  var isModelReady: Bool = false

  private let episode: PodcastEpisodeInfo
  private let podcastTitle: String
  private let localAudioPath: String?
  private let fileStorage = FileStorageManager.shared
  private var modelContext: ModelContext?

  var captionFileURL: URL?

  init(episode: PodcastEpisodeInfo, podcastTitle: String, localAudioPath: String?) {
    self.episode = episode
    self.podcastTitle = podcastTitle
    self.localAudioPath = localAudioPath
  }

  func setModelContext(_ context: ModelContext) {
    self.modelContext = context
  }

  /// Gets the podcast language from SwiftData, falling back to "en" if not found
  private func getPodcastLanguage() -> String {
    guard let context = modelContext else { return "en" }

    let descriptor = FetchDescriptor<PodcastInfoModel>(
      predicate: #Predicate { $0.title == podcastTitle }
    )

    do {
      let results = try context.fetch(descriptor)
      if let podcastModel = results.first {
        return podcastModel.podcastInfo.language
      }
    } catch {
      logger.error("Failed to fetch podcast language: \(error.localizedDescription)")
    }

    return "en"
  }

  func checkTranscriptStatus() {
    Task {
      let language = getPodcastLanguage()
      let transcriptService = TranscriptService(language: language)
      isModelReady = await transcriptService.isModelReady()

      let exists = await fileStorage.captionFileExists(
        for: episode.title,
        podcastTitle: podcastTitle
      )

      if exists {
        await loadExistingTranscript()
      }
    }
  }

  func generateTranscript() {
    guard let audioPath = localAudioPath else {
      state = .error("No local audio file available. Please download the episode first.")
      return
    }

    Task {
      do {
        let audioURL = URL(fileURLWithPath: audioPath)
        let language = getPodcastLanguage()
        let transcriptService = TranscriptService(language: language)

        let modelReady = await transcriptService.isModelReady()

        if !modelReady {
          state = .downloadingModel(progress: 0)

          for await progress in await transcriptService.setupAndInstallAssets() {
            state = .downloadingModel(progress: progress)
          }
        } else {
          for await _ in await transcriptService.setupAndInstallAssets() {
            // Silently consume progress
          }
        }

        guard await transcriptService.isInitialized() else {
          throw NSError(
            domain: "TranscriptService", code: 1,
            userInfo: [
              NSLocalizedDescriptionKey: "Failed to initialize transcription service"
            ]
          )
        }

        state = .transcribing(progress: 0)

        // Use audioToSRTWithWordTimings to get both SRT and word-level timing
        let (srtContent, wordTimingsJSON) = try await transcriptService.audioToSRTWithWordTimings(inputFile: audioURL)

        // Save SRT file
        let captionURL = try await fileStorage.saveCaptionFile(
          content: srtContent,
          episodeTitle: episode.title,
          podcastTitle: podcastTitle
        )

        // Save word timings JSON alongside SRT (for accurate word-level highlighting)
        _ = try await fileStorage.saveWordTimingFile(
          content: wordTimingsJSON,
          episodeTitle: episode.title,
          podcastTitle: podcastTitle
        )

        self.captionFileURL = captionURL
        self.transcriptText = srtContent
        self.state = .completed

      } catch {
        state = .error(error.localizedDescription)
      }
    }
  }

  func regenerateTranscript() {
    Task {
      do {
        if await fileStorage.captionFileExists(
          for: episode.title, podcastTitle: podcastTitle)
        {
          try await fileStorage.deleteCaptionFile(
            for: episode.title, podcastTitle: podcastTitle)
        }
      } catch {
        logger.error("Failed to delete existing transcript: \(error.localizedDescription)")
      }

      generateTranscript()
    }
  }

  private func loadExistingTranscript() async {
    do {
      let content = try await fileStorage.loadCaptionFile(
        for: episode.title,
        podcastTitle: podcastTitle
      )

      let captionURL = await fileStorage.captionFilePath(
        for: episode.title,
        podcastTitle: podcastTitle
      )

      self.transcriptText = content
      self.captionFileURL = captionURL
      self.state = .completed
    } catch {
      logger.error("Failed to load transcript: \(error.localizedDescription)")
    }
  }
}
