//
//  TranscriptService.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/12/17.
//

import AVFoundation
import Foundation
import NaturalLanguage
import Speech
import os.log

// Change availability to iOS and a more realistic version number (e.g., 17.0)
@available(iOS 17.0, *)
public actor TranscriptService {
  private nonisolated let logger = Logger(
    subsystem: "com.podcast.analyzer", category: "TranscriptService")
  private var censor: Bool = false
  private var needsAudioTimeRange: Bool = true
  private var targetLocale: Locale

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
        // 4. Start a nested Task to monitor progress
        Task {
          while !request.progress.isFinished {
            continuation.yield(request.progress.fractionCompleted)
            try? await Task.sleep(for: .milliseconds(100))
          }
        }

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

    // Convert transcript to SRT format
    return transcriptToSRT(transcript: transcript, maxLength: maxLength)
  }

  /// Transcription progress update
  public struct TranscriptionProgress {
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
      Task {
        do {
          // Ensure transcriber and analyzer are initialized
          guard let transcriber = self.transcriber, let analyzer = self.analyzer else {
            throw NSError(
              domain: "TranscriptService", code: 1,
              userInfo: [
                NSLocalizedDescriptionKey:
                  "Transcriber or analyzer not initialized. Call setupAndInstallAssets() first."
              ])
          }

          guard self.needsAudioTimeRange else {
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

          // Convert transcript to SRT format
          let srtContent = self.transcriptToSRT(transcript: transcript, maxLength: maxLength)

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

  /// Formats a TimeInterval into SRT time format (HH:MM:SS,mmm)
  /// - Parameter timeInterval: The time interval in seconds
  /// - Returns: Formatted time string in SRT format
  private func formatSRTTime(_ timeInterval: TimeInterval) -> String {
    let ms = Int(timeInterval.truncatingRemainder(dividingBy: 1) * 1000)
    let s = Int(timeInterval) % 60
    let m = (Int(timeInterval) / 60) % 60
    let h = Int(timeInterval) / 60 / 60
    return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
  }

  /// Helper to check for sentence endings in various languages
  private func isSentenceEnd(_ text: String) -> Bool {
    // Includes:
    // English/European: . ! ?
    // Chinese/CJK: 。 (IDEOGRAPHIC FULL STOP), ！ (FULLWIDTH EXCLAMATION MARK), ？ (FULLWIDTH QUESTION MARK)
    let terminators: Set<Character> = [".", "!", "?", "。", "！", "？"]

    // Check the last character (trimming whitespace/newlines first just in case)
    guard let lastChar = text.trimmingCharacters(in: .whitespacesAndNewlines).last else {
      return false
    }
    return terminators.contains(lastChar)
  }

  /// Splits an AttributedString transcript into segments using NLTokenizer with maxLength constraint
  /// This creates segments of approximately 5-6 seconds duration, similar to yap CLI tool
  /// - Parameters:
  ///   - transcript: The full transcript as AttributedString with audioTimeRange attributes
  ///   - maxLength: Maximum character length per segment (default: 40)
  /// - Returns: Array of AttributedString segments with proper time ranges
  private func splitTranscriptIntoSegments(
    transcript: AttributedString, maxLength: Int
  ) -> [AttributedString] {
    let tokenizer = NLTokenizer(unit: .sentence)
    let string = String(transcript.characters)
    tokenizer.string = string

    // Get all sentence ranges
    let sentenceRanges = tokenizer.tokens(for: string.startIndex..<string.endIndex).compactMap {
      stringRange -> (Range<String.Index>, Range<AttributedString.Index>)? in
      guard
        let attrLower = AttributedString.Index(stringRange.lowerBound, within: transcript),
        let attrUpper = AttributedString.Index(stringRange.upperBound, within: transcript)
      else { return nil }
      return (stringRange, attrLower..<attrUpper)
    }

    // Process each sentence and split if needed
    let allRanges: [Range<AttributedString.Index>] = sentenceRanges.flatMap {
      sentenceStringRange, sentenceAttrRange -> [Range<AttributedString.Index>] in
      let sentence = transcript[sentenceAttrRange]

      // If sentence is within maxLength, keep it as-is
      guard sentence.characters.count > maxLength else {
        return [sentenceAttrRange]
      }

      // Sentence exceeds maxLength - split by words
      let wordTokenizer = NLTokenizer(unit: .word)
      wordTokenizer.string = string

      var wordRanges: [Range<AttributedString.Index>] = wordTokenizer.tokens(
        for: sentenceStringRange
      ).compactMap { wordStringRange -> Range<AttributedString.Index>? in
        guard
          let attrLower = AttributedString.Index(wordStringRange.lowerBound, within: transcript),
          let attrUpper = AttributedString.Index(wordStringRange.upperBound, within: transcript)
        else { return nil }
        return attrLower..<attrUpper
      }

      guard !wordRanges.isEmpty else { return [sentenceAttrRange] }

      // Extend first word to include leading whitespace/punctuation
      wordRanges[0] = sentenceAttrRange.lowerBound..<wordRanges[0].upperBound
      // Extend last word to include trailing whitespace/punctuation
      wordRanges[wordRanges.count - 1] =
        wordRanges[wordRanges.count - 1].lowerBound..<sentenceAttrRange.upperBound

      // Accumulate words into segments respecting maxLength
      var segmentRanges: [Range<AttributedString.Index>] = []
      for wordRange in wordRanges {
        if let lastRange = segmentRanges.last,
          transcript[lastRange].characters.count + transcript[wordRange].characters.count
            <= maxLength
        {
          // Extend the last segment
          segmentRanges[segmentRanges.count - 1] = lastRange.lowerBound..<wordRange.upperBound
        } else {
          // Start a new segment
          segmentRanges.append(wordRange)
        }
      }

      return segmentRanges
    }

    // Convert ranges to AttributedStrings with proper time ranges
    return allRanges.compactMap { range -> AttributedString? in
      let segment = transcript[range]

      // Collect time ranges from non-empty runs
      let audioTimeRanges = segment.runs.filter {
        !String(transcript[$0.range].characters)
          .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }.compactMap(\.audioTimeRange)

      guard !audioTimeRanges.isEmpty else { return nil }

      // Calculate combined time range (start of first, end of last)
      let start = audioTimeRanges.first!.start
      let end = audioTimeRanges.last!.end

      // Create new AttributedString with the combined time range
      var attributes = AttributeContainer()
      attributes[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self] = CMTimeRange(
        start: start,
        end: end
      )
      return AttributedString(segment.characters, attributes: attributes)
    }
  }

  /// Converts an AttributedString transcript to SRT subtitle format
  /// Uses NLTokenizer for smart sentence detection and splits long sentences by word
  /// - Parameters:
  ///   - transcript: The full transcript as AttributedString
  ///   - maxLength: Maximum character length per segment (default: 40 for ~5 second segments)
  /// - Returns: SRT formatted string
  private func transcriptToSRT(transcript: AttributedString, maxLength: Int?) -> String {
    // Default to 40 characters if not specified (creates ~5 second segments)
    let effectiveMaxLength = maxLength ?? 40

    let segments = splitTranscriptIntoSegments(
      transcript: transcript, maxLength: effectiveMaxLength)

    let srtEntries = segments.enumerated().compactMap { index, segment -> String? in
      guard let timeRange = segment.audioTimeRange else { return nil }

      let text = String(segment.characters).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { return nil }

      let entryNumber = index + 1
      let startTime = formatSRTTime(timeRange.start.seconds)
      let endTime = formatSRTTime(timeRange.end.seconds)

      return "\(entryNumber)\n\(startTime) --> \(endTime)\n\(text)"
    }

    return srtEntries.joined(separator: "\n\n")
  }
}
