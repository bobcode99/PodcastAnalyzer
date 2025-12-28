//
//  SRTParser.swift
//  PodcastAnalyzer
//
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
    /// Used for progress estimation with cloud providers
    /// - Parameters:
    ///   - text: Input text
    ///   - language: Language code (e.g., "en", "zh", "ja")
    /// - Returns: Estimated token count
    nonisolated static func estimateTokenCount(for text: String, language: String = "en") -> Int {
        // English/European: ~4 chars per token
        // Asian languages (CJK): ~1.5 chars per token
        let langPrefix = String(language.lowercased().prefix(2))
        let isAsianLanguage = ["zh", "ja", "ko"].contains(langPrefix)
        let charsPerToken = isAsianLanguage ? 1.5 : 4.0

        return Int(ceil(Double(text.count) / charsPerToken))
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
