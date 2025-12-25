//
//  SRTParser.swift
//  PodcastAnalyzer
//
//  Created by Claude Code
//  Utility for parsing SRT (SubRip) transcript files
//

import Foundation

/// Utility for parsing SRT subtitle files and extracting transcript text
struct SRTParser {

    /// Parse SRT content and extract plain text transcript
    /// - Parameter srtContent: Raw SRT file content
    /// - Returns: Plain text transcript with all text concatenated
    static func extractPlainText(from srtContent: String) -> String {
        let lines = srtContent.components(separatedBy: .newlines)
        var transcriptText: [String] = []

        var isTextLine = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            if trimmed.isEmpty {
                isTextLine = false
                continue
            }

            // Skip sequence numbers (1, 2, 3, etc.)
            if trimmed.range(of: "^\\d+$", options: .regularExpression) != nil {
                continue
            }

            // Skip timestamp lines (00:00:00,000 --> 00:00:05,230)
            if trimmed.contains("-->") {
                isTextLine = true
                continue
            }

            // This is actual transcript text
            if isTextLine {
                transcriptText.append(trimmed)
            }
        }

        return transcriptText.joined(separator: " ")
    }

    /// Parse SRT content into structured segments with timestamps
    /// - Parameter srtContent: Raw SRT file content
    /// - Returns: Array of transcript segments with timing information
    static func parseSegments(from srtContent: String) -> [TranscriptSegment] {
        let lines = srtContent.components(separatedBy: .newlines)
        var segments: [TranscriptSegment] = []

        var currentIndex: Int?
        var currentStartTime: TimeInterval?
        var currentEndTime: TimeInterval?
        var currentText: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Empty line indicates end of segment
            if trimmed.isEmpty {
                if let index = currentIndex,
                   let start = currentStartTime,
                   let end = currentEndTime,
                   !currentText.isEmpty {
                    segments.append(TranscriptSegment(
                        id: index,
                        startTime: start,
                        endTime: end,
                        text: currentText.joined(separator: " ")
                    ))
                }
                // Reset for next segment
                currentIndex = nil
                currentStartTime = nil
                currentEndTime = nil
                currentText = []
                continue
            }

            // Parse sequence number
            if let index = Int(trimmed), currentIndex == nil {
                currentIndex = index
                continue
            }

            // Parse timestamp line
            if trimmed.contains("-->") {
                let components = trimmed.components(separatedBy: "-->")
                if components.count == 2 {
                    currentStartTime = parseTimestamp(components[0].trimmingCharacters(in: .whitespaces))
                    currentEndTime = parseTimestamp(components[1].trimmingCharacters(in: .whitespaces))
                }
                continue
            }

            // Collect text lines
            if currentIndex != nil {
                currentText.append(trimmed)
            }
        }

        // Don't forget the last segment if file doesn't end with empty line
        if let index = currentIndex,
           let start = currentStartTime,
           let end = currentEndTime,
           !currentText.isEmpty {
            segments.append(TranscriptSegment(
                id: index,
                startTime: start,
                endTime: end,
                text: currentText.joined(separator: " ")
            ))
        }

        return segments
    }

    /// Parse SRT timestamp to TimeInterval
    /// - Parameter timestamp: Timestamp string in format "00:00:05,230"
    /// - Returns: TimeInterval in seconds
    private static func parseTimestamp(_ timestamp: String) -> TimeInterval {
        // Format: 00:00:05,230 or 00:00:05.230
        let cleaned = timestamp.replacingOccurrences(of: ",", with: ".")
        let components = cleaned.components(separatedBy: ":")

        guard components.count == 3 else { return 0 }

        let hours = Double(components[0]) ?? 0
        let minutes = Double(components[1]) ?? 0
        let seconds = Double(components[2]) ?? 0

        return hours * 3600 + minutes * 60 + seconds
    }

    /// Estimate token count for text (rough approximation)
    /// - Parameters:
    ///   - text: Input text
    ///   - language: Language code (e.g., "en", "zh", "ja")
    /// - Returns: Estimated token count
    static func estimateTokenCount(for text: String, language: String = "en") -> Int {
        // English/European languages: ~3-4 chars per token
        // Asian languages (Chinese/Japanese): ~1 char per token
        let isAsianLanguage = ["zh", "ja", "ko"].contains(language.lowercased().prefix(2))
        let charsPerToken = isAsianLanguage ? 1.0 : 3.5

        return Int(ceil(Double(text.count) / charsPerToken))
    }

    /// Split transcript into chunks that fit within token limit
    /// - Parameters:
    ///   - text: Full transcript text
    ///   - maxTokens: Maximum tokens per chunk (default 3000 to leave room for output)
    ///   - language: Language code for token estimation
    /// - Returns: Array of text chunks
    static func chunkText(_ text: String, maxTokens: Int = 3000, language: String = "en") -> [String] {
        let estimatedTokens = estimateTokenCount(for: text, language: language)

        // If text fits in one chunk, return as-is
        if estimatedTokens <= maxTokens {
            return [text]
        }

        // Split by sentences first
        let sentences = splitIntoSentences(text)
        var chunks: [String] = []
        var currentChunk: [String] = []
        var currentTokenCount = 0

        for sentence in sentences {
            let sentenceTokens = estimateTokenCount(for: sentence, language: language)

            // If adding this sentence exceeds limit, start new chunk
            if currentTokenCount + sentenceTokens > maxTokens && !currentChunk.isEmpty {
                chunks.append(currentChunk.joined(separator: " "))
                currentChunk = [sentence]
                currentTokenCount = sentenceTokens
            } else {
                currentChunk.append(sentence)
                currentTokenCount += sentenceTokens
            }
        }

        // Add final chunk
        if !currentChunk.isEmpty {
            chunks.append(currentChunk.joined(separator: " "))
        }

        return chunks
    }

    /// Split text into sentences using basic punctuation
    /// - Parameter text: Input text
    /// - Returns: Array of sentences
    private static func splitIntoSentences(_ text: String) -> [String] {
        // Split on sentence terminators while preserving them
        let pattern = "([.!?。！？]+\\s+)"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])

        guard let regex = regex else {
            // Fallback: split on common sentence endings
            return text.components(separatedBy: ". ")
        }

        let range = NSRange(text.startIndex..., in: text)
        var sentences: [String] = []
        var lastEnd = text.startIndex

        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match = match else { return }
            let matchRange = Range(match.range, in: text)!

            let sentence = String(text[lastEnd..<matchRange.upperBound])
            sentences.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
            lastEnd = matchRange.upperBound
        }

        // Add remaining text
        if lastEnd < text.endIndex {
            sentences.append(String(text[lastEnd...]).trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return sentences.filter { !$0.isEmpty }
    }
}

// MARK: - TranscriptSegment Extension
extension TranscriptSegment {
    /// Get text content for a range of segments
    /// - Parameters:
    ///   - segments: Array of transcript segments
    ///   - startIndex: Starting segment index
    ///   - endIndex: Ending segment index
    /// - Returns: Combined text from segments in range
    static func getText(from segments: [TranscriptSegment], startIndex: Int, endIndex: Int) -> String {
        let filtered = segments.filter { $0.id >= startIndex && $0.id <= endIndex }
        return filtered.map { $0.text }.joined(separator: " ")
    }
}
