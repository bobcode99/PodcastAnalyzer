//
//  TranscriptService.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/12/17.
//

import AVFoundation
import Foundation
import Speech
import OSLog

// Change availability to iOS and a more realistic version number (e.g., 17.0)
@available(iOS 17.0, *)
public actor TranscriptService {
  private nonisolated let logger = Logger(
    subsystem: "com.podcast.analyzer", category: "TranscriptService")
  private var censor: Bool = false
  private var needsAudioTimeRange: Bool = true
  private var targetLocale: Locale

  /// Whether the target locale is CJK (Chinese, Japanese, Korean).
  /// CJK characters carry ~1 word of meaning each, so segments need fewer characters.
  var isCJKLocale: Bool {
    let lang = targetLocale.language.languageCode?.identifier ?? ""
    return ["zh", "ja", "ko"].contains(lang)
  }

  /// Default max characters per subtitle segment, adjusted for character density.
  /// CJK: 18 chars (~18 words of content), Latin: 40 chars (~6-8 words)
  var defaultMaxLength: Int {
    isCJKLocale ? 18 : 40
  }

  /// Converts a podcast language code (e.g., "zh-tw") to a Locale identifier (e.g., "zh_TW")
  /// - Parameter languageCode: The language code from podcast RSS feed (e.g., "zh-tw", "en-us", "ja")
  /// - Returns: A Locale instance with the properly formatted identifier
  ///
  /// Examples:
  /// - "zh-tw" → Locale(identifier: "zh_TW")
  /// - "en-us" → Locale(identifier: "en_US")
  /// - "en" → Locale(identifier: "en_US")  // Maps to default region
  /// - "ja" → Locale(identifier: "ja_JP")  // Maps to default region
  public static func locale(fromPodcastLanguage languageCode: String) -> Locale {
    // Default region mappings for language-only codes
    // Speech framework requires full locale identifiers (e.g., "en_US" not just "en")
    let defaultRegions: [String: String] = [
      "en": "US",
      "zh": "TW",
      "ja": "JP",
      "ko": "KR",
      "fr": "FR",
      "de": "DE",
      "es": "ES",
      "it": "IT",
      "pt": "BR",
      "ru": "RU",
      "ar": "SA",
      "hi": "IN",
      "th": "TH",
      "vi": "VN",
      "id": "ID",
      "ms": "MY",
      "nl": "NL",
      "pl": "PL",
      "tr": "TR",
      "uk": "UA",
      "cs": "CZ",
      "el": "GR",
      "he": "IL",
      "ro": "RO",
      "hu": "HU",
      "sv": "SE",
      "da": "DK",
      "fi": "FI",
      "nb": "NO",
      "sk": "SK",
      "ca": "ES",
      "hr": "HR",
    ]

    // Replace hyphens with underscores and uppercase the region code
    let parts = languageCode.lowercased().split(separator: "-")
    if parts.count == 2 {
      // Language and region: "zh-tw" -> "zh_TW"
      let language = String(parts[0])
      let region = String(parts[1]).uppercased()
      return Locale(identifier: "\(language)_\(region)")
    } else if parts.count == 1 {
      // Language only: map to default region if available
      let language = String(parts[0])
      if let defaultRegion = defaultRegions[language] {
        return Locale(identifier: "\(language)_\(defaultRegion)")
      }
      // Fallback: just use the language code
      return Locale(identifier: language)
    } else {
      // Fallback: use the original string as-is
      return Locale(identifier: languageCode)
    }
  }

  // 1. Store the transcriber instance
  private var transcriber: SpeechTranscriber?
  private var analyzer: SpeechAnalyzer?
  // Store the locale used for installation

  /// Convenience initializer that accepts a podcast language string (e.g., "zh-tw", "en-us")
  /// - Parameters:
  ///   - language: The language code from podcast RSS feed (e.g., "zh-tw", "en-us", "ja")
  ///   - censor: Whether to enable content filtering
  ///   - needsAudioTimeRange: Whether to include audio time ranges in transcription
  public init(
    language: String,
    censor: Bool = false,
    needsAudioTimeRange: Bool = true
  ) {
    self.censor = censor
    self.needsAudioTimeRange = needsAudioTimeRange
    self.targetLocale = Self.locale(fromPodcastLanguage: language)
  }

  // 2. The main setup function that returns an AsyncStream of progress
  func setupAndInstallAssets() -> AsyncStream<Double> {
    return AsyncStream { continuation in
      // Create a task that will call the actor method
      // The await ensures we're properly isolated to the actor
      Task {
        await self.setupAndInstallAssetsInternal(continuation: continuation)
      }
    }
  }

  // Internal setup method that runs on the actor (isolated to this actor)
  private func setupAndInstallAssetsInternal(continuation: AsyncStream<Double>.Continuation) async {
    // Ensure we have an active transcriber instance
    let newTranscriber = SpeechTranscriber(
      locale: targetLocale,
      transcriptionOptions: censor ? [.etiquetteReplacements] : [],
      reportingOptions: [],
      attributeOptions: needsAudioTimeRange ? [.audioTimeRange] : []
    )
    self.transcriber = newTranscriber

    // Release and reserve locales
    await releaseAndReserveLocales()

      let modules: [any SpeechModule] = [newTranscriber]
    let installed = await Set(SpeechTranscriber.installedLocales)
    logger.info("Installed locales: \(installed.map { $0.identifier }.joined(separator: ", "))")

    // Check if assets are already installed
    if installed.map({ $0.identifier(.bcp47) }).contains(
      targetLocale.identifier(.bcp47))
    {
      // Create analyzer even if assets are already installed
      self.analyzer = SpeechAnalyzer(modules: modules)

      // Verify analyzer was set (defensive check)
      assert(self.analyzer != nil, "Analyzer should be set before finishing")

      continuation.yield(1.0)  // Already installed, send 100%
      continuation.finish()
      return
    }

    do {
      // 3. Get the installation request
      if let request = try await AssetInventory.assetInstallationRequest(
        supporting: modules)
      {
        // 4. Start a nested Task to monitor progress; tie its lifetime to the stream
        let pollingTask = Task {
          while !request.progress.isFinished && !Task.isCancelled {
            continuation.yield(request.progress.fractionCompleted)
            try? await Task.sleep(for: .milliseconds(100))
          }
        }
        continuation.onTermination = { _ in pollingTask.cancel() }

        // 6. Start the actual download and installation
        try await request.downloadAndInstall()

        // 7. Once finished, send 100% and end the stream
        continuation.yield(1.0)
      }
    } catch {
      logger.error("Asset setup failed: \(error.localizedDescription)")
    }

    // Always create analyzer after setup (even if installation failed, we still need it)
    self.analyzer = SpeechAnalyzer(modules: modules)

    // Verify analyzer was set (defensive check)
    assert(self.analyzer != nil, "Analyzer should be set before finishing")

    continuation.finish()
  }

  /// Checks if the Speech-to-Text model for the target locale is installed and ready to use.
  ///
  /// - Returns: `true` if the model is installed, `false` otherwise.
  public func isModelReady() async -> Bool {
    let installed = await Set(SpeechTranscriber.installedLocales)
    return installed.map({ $0.identifier(.bcp47) }).contains(targetLocale.identifier(.bcp47))
  }

  /// Checks if the service is fully initialized and ready to transcribe audio.
  ///
  /// - Returns: `true` if both transcriber and analyzer are initialized, `false` otherwise.
  public func isInitialized() async -> Bool {
    return transcriber != nil && analyzer != nil
  }

  // Helper function for the locale logic (no longer needs 'locale' parameter)
  private func releaseAndReserveLocales() async {
    // Release existing reserved locales
    for existingLocale in await AssetInventory.reservedLocales {
      await AssetInventory.release(reservedLocale: existingLocale)
    }

    // Reserve the new locale
    do {
      try await AssetInventory.reserve(locale: targetLocale)
    } catch {
      logger.error("Failed to reserve locale: \(error.localizedDescription)")
    }
  }

  public func audioToText(inputFile: URL) async throws -> String {
    // Ensure transcriber and analyzer are initialized
    guard let transcriber = transcriber, let analyzer = analyzer else {
      throw NSError(
        domain: "TranscriptService", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Transcriber or analyzer not initialized. Call setupAndInstallAssets() first."
        ])
    }

    // Download if remote URL, otherwise use local file
    let audioURL = try await resolveAudioURL(inputFile)
    let audioFile = try AVAudioFile(forReading: audioURL)
    let audioFileDuration: TimeInterval =
      Double(audioFile.length) / audioFile.processingFormat.sampleRate

    logger.info("Audio file duration: \(audioFileDuration) seconds")

    // Start the analyzer
    try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)

    // Collect transcript results
    var transcript: AttributedString = ""

    for try await result in transcriber.results {
      transcript += result.text
    }

    // Convert AttributedString to String and return
    return String(transcript.characters)
  }

  /// Resolves audio URL - downloads remote URLs to a temporary file, returns local URLs as-is
  private func resolveAudioURL(_ url: URL) async throws -> URL {
    // If it's a local file, return as-is
    if url.isFileURL {
      return url
    }

    // Download remote URL to temporary file
    let (tempFileURL, _) = try await URLSession.shared.download(from: url)
    return tempFileURL
  }

  /// Converts audio file to SRT subtitle format
  /// - Parameter inputFile: The URL of the audio file to transcribe
  /// - Parameter maxLength: Maximum length for each subtitle entry (optional, defaults to nil)
  /// - Returns: SRT formatted subtitle string
  public func audioToSRT(inputFile: URL, maxLength: Int? = nil) async throws -> String {
    // Ensure transcriber and analyzer are initialized
    guard let transcriber = transcriber, let analyzer = analyzer else {
      throw NSError(
        domain: "TranscriptService", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Transcriber or analyzer not initialized. Call setupAndInstallAssets() first."
        ])
    }

    guard needsAudioTimeRange else {
      throw NSError(
        domain: "TranscriptService", code: 2,
        userInfo: [
          NSLocalizedDescriptionKey:
            "audioTimeRange must be enabled to generate SRT subtitles. Initialize TranscriptService with needsAudioTimeRange: true"
        ])
    }

    // Download if remote URL, otherwise use local file
    let audioURL = try await resolveAudioURL(inputFile)
    let audioFile = try AVAudioFile(forReading: audioURL)
    let audioFileDuration: TimeInterval =
      Double(audioFile.length) / audioFile.processingFormat.sampleRate

    logger.info("Audio file duration for SRT: \(audioFileDuration) seconds")

    // Start the analyzer
    try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)

    // Collect transcript results
    var transcript: AttributedString = ""

    for try await result in transcriber.results {
      transcript += result.text
    }

    // Apply Chinese punctuation restoration for CJK locales
    var processedTranscript = transcript
    if isCJKLocale {
      let restorer = ChinesePunctuationRestorer()
      processedTranscript = restorer.restore(transcript: transcript)
    }

    // Convert transcript to SRT format
    let effectiveMaxLength = maxLength ?? defaultMaxLength
    let segmenter = TranscriptSegmenter(isCJK: isCJKLocale, maxLength: effectiveMaxLength)
    let segments = segmenter.splitTranscriptIntoSegments(transcript: processedTranscript)
    return SRTFormatter.format(segments: segments)
  }

  /// Transcription progress update
  public struct TranscriptionProgress: Sendable {
    public let progress: Double  // 0.0 to 1.0
    public let currentTimeSeconds: TimeInterval
    public let totalDurationSeconds: TimeInterval
    public let isComplete: Bool
    public let srtContent: String?  // Only set when isComplete = true
  }

  /// Converts audio file to SRT subtitle format with progress updates
  /// - Parameter inputFile: The URL of the audio file to transcribe
  /// - Parameter maxLength: Maximum length for each subtitle entry (optional, defaults to nil)
  /// - Returns: AsyncStream of TranscriptionProgress updates
  public func audioToSRTWithProgress(inputFile: URL, maxLength: Int? = nil) -> AsyncThrowingStream<
    TranscriptionProgress, Error
  > {
    return AsyncThrowingStream { continuation in
      // Use Task.detached to ensure CPU-intensive transcription runs on a background thread
      // This prevents blocking the actor and allows better parallelization
      Task.detached(priority: .userInitiated) {
        do {
          // Access actor-isolated properties - need to await actor access
          let (transcriber, analyzer, needsAudioTimeRange) = await (
            self.transcriber,
            self.analyzer,
            self.needsAudioTimeRange
          )
          let isCJK = await self.isCJKLocale
          let defaultMaxLen = await self.defaultMaxLength

          // Ensure transcriber and analyzer are initialized
          guard let transcriber = transcriber, let analyzer = analyzer else {
            throw NSError(
              domain: "TranscriptService", code: 1,
              userInfo: [
                NSLocalizedDescriptionKey:
                  "Transcriber or analyzer not initialized. Call setupAndInstallAssets() first."
              ])
          }

          guard needsAudioTimeRange else {
            throw NSError(
              domain: "TranscriptService", code: 2,
              userInfo: [
                NSLocalizedDescriptionKey:
                  "audioTimeRange must be enabled to generate SRT subtitles."
              ])
          }

          // Download if remote URL, otherwise use local file
          let audioURL = try await self.resolveAudioURL(inputFile)
          let audioFile = try AVAudioFile(forReading: audioURL)
          let audioFileDuration: TimeInterval =
            Double(audioFile.length) / audioFile.processingFormat.sampleRate

          // Logger is nonisolated, no need to await
          self.logger.info(
            "Audio file duration for SRT with progress: \(audioFileDuration) seconds")

          // Send initial progress
          continuation.yield(
            TranscriptionProgress(
              progress: 0.0,
              currentTimeSeconds: 0,
              totalDurationSeconds: audioFileDuration,
              isComplete: false,
              srtContent: nil
            ))

          // Start the analyzer
          try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)

          // Collect transcript results with progress
          var transcript: AttributedString = ""
          var lastReportedTime: TimeInterval = 0

          for try await result in transcriber.results {
            transcript += result.text

            // Extract the latest time from the result to calculate progress
            for run in result.text.runs {
              if let timeRange = run.audioTimeRange {
                let currentTime = timeRange.end.seconds
                if currentTime > lastReportedTime {
                  lastReportedTime = currentTime
                  let progress = min(currentTime / audioFileDuration, 0.99)  // Cap at 99% until complete

                  continuation.yield(
                    TranscriptionProgress(
                      progress: progress,
                      currentTimeSeconds: currentTime,
                      totalDurationSeconds: audioFileDuration,
                      isComplete: false,
                      srtContent: nil
                    ))
                }
              }
            }
          }

          // Check if we actually got any transcript content
          guard !transcript.characters.isEmpty else {
            throw NSError(
              domain: "TranscriptService", code: 3,
              userInfo: [
                NSLocalizedDescriptionKey:
                  "Transcription produced no content. The audio may be silent or in an unsupported format."
              ])
          }

          // Apply Chinese punctuation restoration for CJK locales
          var processedTranscript = transcript
          if isCJK {
            let restorer = ChinesePunctuationRestorer()
            processedTranscript = restorer.restore(transcript: transcript)
          }

          // Convert transcript to SRT format
          let effectiveMaxLength = maxLength ?? defaultMaxLen
          let segmenter = TranscriptSegmenter(isCJK: isCJK, maxLength: effectiveMaxLength)
          let segments = segmenter.splitTranscriptIntoSegments(transcript: processedTranscript)
          let srtContent = SRTFormatter.format(segments: segments)

          // Send final progress with completed content
          continuation.yield(
            TranscriptionProgress(
              progress: 1.0,
              currentTimeSeconds: audioFileDuration,
              totalDurationSeconds: audioFileDuration,
              isComplete: true,
              srtContent: srtContent
            ))

          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }

  /// Converts audio to SRT format with additional JSON file containing word timings
  /// - Parameter inputFile: The URL of the audio file to transcribe
  /// - Parameter maxLength: Maximum length for each subtitle entry (optional, defaults to nil)
  /// - Returns: Tuple of (SRT content, JSON word timings content)
  public func audioToSRTWithWordTimings(inputFile: URL, maxLength: Int? = nil) async throws -> (srt: String, wordTimingsJSON: String) {
    guard let transcriber = transcriber, let analyzer = analyzer else {
      throw NSError(
        domain: "TranscriptService", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Transcriber or analyzer not initialized. Call setupAndInstallAssets() first."
        ])
    }

    guard needsAudioTimeRange else {
      throw NSError(
        domain: "TranscriptService", code: 2,
        userInfo: [
          NSLocalizedDescriptionKey:
            "audioTimeRange must be enabled to generate word timings."
        ])
    }

    let audioURL = try await resolveAudioURL(inputFile)
    let audioFile = try AVAudioFile(forReading: audioURL)

    try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)

    var transcript: AttributedString = ""
    for try await result in transcriber.results {
      transcript += result.text
    }

    // Apply Chinese punctuation restoration for CJK locales
    var processedTranscript = transcript
    if isCJKLocale {
      let restorer = ChinesePunctuationRestorer()
      processedTranscript = restorer.restore(transcript: transcript)
    }

    let effectiveMaxLength = maxLength ?? defaultMaxLength
    let segmenter = TranscriptSegmenter(isCJK: isCJKLocale, maxLength: effectiveMaxLength)
    let segments = segmenter.extractSegmentsWithWordTimings(transcript: processedTranscript)
    let transcriptData = TranscriptData(segments: segments)

    // Generate SRT
    let srtSegments = segmenter.splitTranscriptIntoSegments(transcript: processedTranscript)
    let srtContent = SRTFormatter.format(segments: srtSegments)

    // Generate JSON word timings
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let jsonData = try encoder.encode(transcriptData)
    let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

    return (srtContent, jsonString)
  }

  /// Converts audio file to SRT subtitle format with parallel chunk processing for long audio.
  /// For audio shorter than 10 minutes, falls back to sequential processing.
  /// For longer audio, splits into 5-minute chunks processed in parallel for ~3-4x speedup.
  public func audioToSRTChunkedWithProgress(
    inputFile: URL,
    maxLength: Int? = nil,
    chunkDuration: TimeInterval = 300
  ) -> AsyncThrowingStream<TranscriptionProgress, Error> {
    return AsyncThrowingStream { continuation in
      Task.detached(priority: .userInitiated) { [self] in
        do {
          // Capture actor-isolated state upfront so chunk tasks don't need the actor
          let locale = await self.targetLocale
          let censor = await self.censor
          let isCJK = await self.isCJKLocale
          let defaultMaxLen = await self.defaultMaxLength
          let effectiveMaxLength = maxLength ?? defaultMaxLen

          let audioURL = try await self.resolveAudioURL(inputFile)
          let audioFile = try AVAudioFile(forReading: audioURL)
          let sampleRate = audioFile.processingFormat.sampleRate
          let audioFileDuration: TimeInterval =
            sampleRate > 0 ? Double(audioFile.length) / sampleRate : 0

          guard audioFileDuration.isFinite && audioFileDuration > 0 else {
            throw NSError(
              domain: "TranscriptService", code: 12,
              userInfo: [NSLocalizedDescriptionKey: "Invalid audio file duration"]
            )
          }

          self.logger.info(
            "Audio duration: \(audioFileDuration)s — evaluating chunked vs sequential")

          // Threshold: audio shorter than 10 minutes uses sequential processing
          if audioFileDuration < 600 {
            self.logger.info("Audio < 10 min, using sequential processing")
            for try await progress in await self.audioToSRTWithProgress(
              inputFile: inputFile, maxLength: maxLength
            ) {
              continuation.yield(progress)
            }
            continuation.finish()
            return
          }

          // Send initial progress
          continuation.yield(TranscriptionProgress(
            progress: 0.0,
            currentTimeSeconds: 0,
            totalDurationSeconds: audioFileDuration,
            isComplete: false,
            srtContent: nil
          ))

          // Export audio chunks
          self.logger.info("Exporting audio chunks (chunkDuration: \(chunkDuration)s)")
          let overlap: TimeInterval = 2.0
          let chunks = try await ChunkedTranscriptionService.exportAudioChunks(
            from: audioURL,
            totalDuration: audioFileDuration,
            chunkDuration: chunkDuration,
            overlap: overlap
          )
          self.logger.info("Exported \(chunks.count) chunks")

          defer { ChunkedTranscriptionService.cleanupTempFiles(chunks) }

          // Determine concurrency limit (at least 1)
          let maxConcurrent = max(min(
            chunks.count,
            ProcessInfo.processInfo.processorCount / 2,
            4
          ), 1)
          self.logger.info("Processing with concurrency limit: \(maxConcurrent)")

          let progressTracker = ChunkProgressTracker(totalChunks: chunks.count)

          // Process chunks in parallel
          let allChunkResults: [[ChunkedTranscriptionService.ChunkSegment]] = try await withThrowingTaskGroup(
            of: (Int, [ChunkedTranscriptionService.ChunkSegment]).self
          ) { group in
            var results = [[ChunkedTranscriptionService.ChunkSegment]](repeating: [], count: chunks.count)
            var launched = 0

            // Launch initial batch up to concurrency limit
            for i in 0..<min(maxConcurrent, chunks.count) {
              let chunk = chunks[i]
              group.addTask {
                let segments = try await ChunkedTranscriptionService.transcribeChunkParallel(
                  chunk: chunk,
                  locale: locale,
                  censor: censor,
                  isCJK: isCJK,
                  maxSegmentLength: effectiveMaxLength,
                  onProgress: { chunkProgress in
                    Task {
                      let overall = await progressTracker.updateProgress(
                        chunkIndex: chunk.index, progress: chunkProgress
                      )
                      continuation.yield(TranscriptionProgress(
                        progress: min(overall, 0.99),
                        currentTimeSeconds: overall * audioFileDuration,
                        totalDurationSeconds: audioFileDuration,
                        isComplete: false,
                        srtContent: nil
                      ))
                    }
                  }
                )
                return (chunk.index, segments)
              }
              launched += 1
            }

            // As each task completes, launch the next pending chunk
            for try await (chunkIndex, segments) in group {
              results[chunkIndex] = segments

              // Launch next chunk if available
              if launched < chunks.count {
                let chunk = chunks[launched]
                group.addTask {
                  let segments = try await ChunkedTranscriptionService.transcribeChunkParallel(
                    chunk: chunk,
                    locale: locale,
                    censor: censor,
                    isCJK: isCJK,
                    maxSegmentLength: effectiveMaxLength,
                    onProgress: { chunkProgress in
                      Task {
                        let overall = await progressTracker.updateProgress(
                          chunkIndex: chunk.index, progress: chunkProgress
                        )
                        continuation.yield(TranscriptionProgress(
                          progress: min(overall, 0.99),
                          currentTimeSeconds: overall * audioFileDuration,
                          totalDurationSeconds: audioFileDuration,
                          isComplete: false,
                          srtContent: nil
                        ))
                      }
                    }
                  )
                  return (chunk.index, segments)
                }
                launched += 1
              }
            }

            return results
          }

          // Merge results with overlap de-duplication
          let mergedSegments = ChunkedTranscriptionService.mergeChunkSegments(allChunkResults, overlap: overlap)

          guard !mergedSegments.isEmpty else {
            throw NSError(
              domain: "TranscriptService", code: 3,
              userInfo: [
                NSLocalizedDescriptionKey:
                  "Transcription produced no content. The audio may be silent or in an unsupported format."
              ])
          }

          // Convert to SRT
          let srtContent = SRTFormatter.format(chunkSegments: mergedSegments)

          // Send final progress
          continuation.yield(TranscriptionProgress(
            progress: 1.0,
            currentTimeSeconds: audioFileDuration,
            totalDurationSeconds: audioFileDuration,
            isComplete: true,
            srtContent: srtContent
          ))

          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }
}
