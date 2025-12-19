//
//  TranscriptService.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/12/17.
//


import AVFoundation
import Foundation
import Speech
import os.log

// Change availability to iOS and a more realistic version number (e.g., 17.0)
@available(iOS 17.0, *)
public actor TranscriptService {
    private nonisolated let logger = Logger(subsystem: "com.podcast.analyzer", category: "TranscriptService")
    private var censor: Bool = false
    private var needsAudioTimeRange: Bool = true
    private var targetLocale: Locale

    // 1. Store the transcriber instance
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    // Store the locale used for installation

    // Designated initializer
    public init(
        censor: Bool = false, needsAudioTimeRange: Bool = true,
        targetLocale: Locale = Locale(identifier: "en-US")
    ) {
        self.censor = censor
        self.needsAudioTimeRange = needsAudioTimeRange
        self.targetLocale = targetLocale
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
    private func setupAndInstallAssetsInternal(continuation: AsyncStream<Double>.Continuation) async
    {
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

    /// Converts an AttributedString transcript to SRT subtitle format
    /// - Parameter transcript: The transcript as AttributedString with audioTimeRange attributes
    /// - Parameter maxLength: Maximum length for each subtitle entry (optional)
    /// - Returns: SRT formatted subtitle string
    private func transcriptToSRT(transcript: AttributedString, maxLength: Int?) -> String {
        // Get sentences from the transcript by processing runs
        var sentences: [(text: AttributedString, timeRange: CMTimeRange?)] = []

        if let maxLength = maxLength {
            // Split into sentences with max length
            var currentSentence: AttributedString = ""
            var currentTimeRange: CMTimeRange?

            for run in transcript.runs {
                let runSubstring = transcript[run.range]
                let runText = AttributedString(runSubstring)
                let runLength = runText.characters.count

                // Get audioTimeRange from this run
                var runTimeRange: CMTimeRange?
                if let audioTimeRange = run.audioTimeRange {
                    runTimeRange = audioTimeRange
                }

                if currentSentence.characters.count + runLength <= maxLength {
                    currentSentence += runText
                    // Update time range
                    if let runRange = runTimeRange {
                        if let currentRange = currentTimeRange {
                            let start = min(currentRange.start.seconds, runRange.start.seconds)
                            let end = max(currentRange.end.seconds, runRange.end.seconds)
                            currentTimeRange = CMTimeRange(
                                start: CMTime(seconds: start, preferredTimescale: 600),
                                duration: CMTime(seconds: end - start, preferredTimescale: 600)
                            )
                        } else {
                            currentTimeRange = runRange
                        }
                    }
                } else {
                    if currentSentence.characters.count > 0 {
                        sentences.append((currentSentence, currentTimeRange))
                    }
                    currentSentence = runText
                    currentTimeRange = runTimeRange
                }
            }
            if currentSentence.characters.count > 0 {
                sentences.append((currentSentence, currentTimeRange))
            }
        } else {
            // Use natural sentence boundaries - process by runs and group by audioTimeRange
            var currentSentence: AttributedString = ""
            var currentTimeRange: CMTimeRange?

            for run in transcript.runs {
                let runSubstring = transcript[run.range]
                let runText = AttributedString(runSubstring)
                currentSentence += runText

                // Get audioTimeRange from this run
                if let audioTimeRange = run.audioTimeRange {
                    if let existingRange = currentTimeRange {
                        let start = min(existingRange.start.seconds, audioTimeRange.start.seconds)
                        let end = max(existingRange.end.seconds, audioTimeRange.end.seconds)
                        currentTimeRange = CMTimeRange(
                            start: CMTime(seconds: start, preferredTimescale: 600),
                            duration: CMTime(seconds: end - start, preferredTimescale: 600)
                        )
                    } else {
                        currentTimeRange = audioTimeRange
                    }
                }

                // Check if this run ends a sentence
                let text = String(runText.characters)
                if text.hasSuffix(".") || text.hasSuffix("!") || text.hasSuffix("?") {
                    if currentSentence.characters.count > 0 {
                        sentences.append((currentSentence, currentTimeRange))
                    }
                    currentSentence = ""
                    currentTimeRange = nil
                }
            }
            if currentSentence.characters.count > 0 {
                sentences.append((currentSentence, currentTimeRange))
            }
        }

        // Convert sentences to SRT entries
        let srtEntries = sentences.enumerated().compactMap { index, entry -> String? in
            let (sentence, timeRange) = entry

            // Try to get timeRange from sentence level first, then use the computed one
            var finalTimeRange: CMTimeRange?

            // Check if audioTimeRange is set at the sentence level
            for run in sentence.runs {
                if let audioTimeRange = run.audioTimeRange {
                    if finalTimeRange == nil {
                        finalTimeRange = audioTimeRange
                    } else {
                        // Extend the range
                        let start = min(finalTimeRange!.start.seconds, audioTimeRange.start.seconds)
                        let end = max(finalTimeRange!.end.seconds, audioTimeRange.end.seconds)
                        finalTimeRange = CMTimeRange(
                            start: CMTime(seconds: start, preferredTimescale: 600),
                            duration: CMTime(seconds: end - start, preferredTimescale: 600)
                        )
                    }
                }
            }

            // Use computed timeRange if sentence-level one is not available
            let range = finalTimeRange ?? timeRange
            guard let range = range else { return nil }

            let text = String(sentence.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count > 0 else { return nil }

            return """
                \(index + 1)
                \(formatSRTTime(range.start.seconds)) --> \(formatSRTTime(range.end.seconds))
                \(text)

                """
        }

        return srtEntries.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

}
