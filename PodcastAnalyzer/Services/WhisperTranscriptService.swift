//
//  WhisperTranscriptService.swift
//  PodcastAnalyzer
//
//  On-device transcription using WhisperKit (OpenAI Whisper models via CoreML).
//  Produces SRT output compatible with the existing caption pipeline.
//

import Foundation
import OSLog
import WhisperKit

// MARK: - WhisperTranscriptService

/// Actor-isolated service that transcribes audio files using WhisperKit.
/// Output format is SRT, matching what TranscriptService (Apple Speech) produces,
/// so the rest of the pipeline (FileStorageManager, EnhancedAudioManager) is unchanged.
actor WhisperTranscriptService {

    private let logger = Logger(subsystem: "com.podcast.analyzer", category: "WhisperTranscriptService")

    // MARK: - Model Download

    /// Downloads a Whisper model variant, reporting fractional progress via the callback.
    /// Throws on failure or cancellation.
    static func downloadModel(
        variant: WhisperModelVariant,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws {
        _ = try await WhisperKit.download(
            variant: variant.rawValue,
            downloadBase: nil,
            useBackgroundSession: false
        ) { progress in
            onProgress(progress.fractionCompleted)
        }
    }

    // MARK: - Transcription

    /// Transcribes an audio file to SRT format, streaming progress updates.
    ///
    /// - Parameters:
    ///   - inputFile: URL to a local audio/video file supported by AVFoundation.
    ///   - modelVariant: Which Whisper model to use (must already be downloaded).
    /// - Returns: An `AsyncThrowingStream` that emits `TranscriptionProgressUpdate` values.
    ///            The last emission has `isComplete == true` and carries the full SRT content.
    func audioToSRTWithProgress(
        inputFile: URL,
        modelVariant: WhisperModelVariant
    ) -> AsyncThrowingStream<TranscriptionProgressUpdate, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    continuation.yield(
                        TranscriptionProgressUpdate(progress: 0, isComplete: false, srtContent: nil)
                    )

                    // Load the model (uses cached CoreML artefacts).
                    let whisper = try await WhisperKit(model: modelVariant.rawValue)

                    continuation.yield(
                        TranscriptionProgressUpdate(progress: 0.05, isComplete: false, srtContent: nil)
                    )

                    guard !Task.isCancelled else {
                        continuation.finish(throwing: CancellationError())
                        return
                    }

                    // Decoding options tuned for podcast audio.
                    let options = DecodingOptions(
                        verbose: false,
                        task: .transcribe,
                        // usePrefillPrompt helps with accuracy on technical content
                        usePrefillPrompt: true,
                        // Suppress hallucinations on silent segments
                        noSpeechThreshold: 0.6,
                        // Compression ratio guard (Whisper default is 2.4)
                        compressionRatioThreshold: 2.4,
                        // Log-probability guard
                        logProbThreshold: -1.0,
                        // Enable word timestamps for accurate segment boundaries
                        wordTimestamps: true
                    )

                    // WhisperKit streams segment-level results via a callback.
                    var allSegments: [TranscriptionSegment] = []

                    // Estimate audio duration for progress reporting.
                    let estimatedDuration = await estimateDuration(of: inputFile)

                    var lastReportedProgress = 0.05

                    let results = try await whisper.transcribe(
                        audioPath: inputFile.path,
                        decodeOptions: options
                    ) { progress in
                        // `progress` is a WhisperKit Progress object carrying partial segments.
                        // Map the last segment end-time to a fraction of total duration.
                        if let lastEnd = progress.timings?.fullPipeline,
                           estimatedDuration > 0 {
                            let fraction = min(Double(lastEnd) / estimatedDuration, 0.95)
                            if fraction > lastReportedProgress + 0.02 {
                                lastReportedProgress = fraction
                                continuation.yield(
                                    TranscriptionProgressUpdate(
                                        progress: fraction,
                                        isComplete: false,
                                        srtContent: nil
                                    )
                                )
                            }
                        }
                    }

                    guard !Task.isCancelled else {
                        continuation.finish(throwing: CancellationError())
                        return
                    }

                    // Collect all segments from all results (WhisperKit may split long audio).
                    for result in results {
                        allSegments.append(contentsOf: result.segments)
                    }

                    let srtContent = Self.segmentsToSRT(allSegments)

                    continuation.yield(
                        TranscriptionProgressUpdate(progress: 1.0, isComplete: true, srtContent: srtContent)
                    )
                    continuation.finish()

                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - SRT Formatting

    /// Converts WhisperKit segments to an SRT string.
    private static func segmentsToSRT(_ segments: [TranscriptionSegment]) -> String {
        var lines: [String] = []
        for (index, segment) in segments.enumerated() {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            let start = formatSRTTime(TimeInterval(segment.start))
            let end = formatSRTTime(TimeInterval(segment.end))

            lines.append("\(index + 1)")
            lines.append("\(start) --> \(end)")
            lines.append(text)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Formats seconds into SRT timestamp: `HH:MM:SS,mmm`
    private static func formatSRTTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && !seconds.isNaN else { return "00:00:00,000" }
        let totalMs = Int(max(0, seconds) * 1000)
        let ms = totalMs % 1000
        let s = (totalMs / 1000) % 60
        let m = (totalMs / 60_000) % 60
        let h = totalMs / 3_600_000
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }

    // MARK: - Duration Estimation

    private func estimateDuration(of url: URL) async -> Double {
        await Task.detached {
            let asset = AVURLAsset(url: url)
            do {
                let duration = try await asset.load(.duration)
                return duration.seconds
            } catch {
                return 0
            }
        }.value
    }
}

// MARK: - AVFoundation import for duration

import AVFoundation
