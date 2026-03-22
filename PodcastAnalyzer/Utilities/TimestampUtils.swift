//
//  TimestampUtils.swift
//  PodcastAnalyzer
//
//  Timestamp parsing and formatting utilities for AI analysis views.
//

import Foundation

nonisolated struct TimestampUtils {

  /// Parses a timestamp string like "05:32", "1:23:45", or "[05:32]" into total seconds.
  static func parseToSeconds(_ timestamp: String) -> TimeInterval? {
    // Strip brackets if present
    let cleaned = timestamp
      .trimmingCharacters(in: .whitespaces)
      .replacingOccurrences(of: "[", with: "")
      .replacingOccurrences(of: "]", with: "")

    let parts = cleaned.split(separator: ":").compactMap { Int($0) }
    switch parts.count {
    case 2:
      // MM:SS
      return TimeInterval(parts[0] * 60 + parts[1])
    case 3:
      // H:MM:SS or HH:MM:SS
      return TimeInterval(parts[0] * 3600 + parts[1] * 60 + parts[2])
    default:
      return nil
    }
  }

  /// Finds all timestamps in a text string. Returns deduplicated results.
  static func findTimestamps(in text: String) -> [(text: String, seconds: TimeInterval)] {
    guard let regex = try? NSRegularExpression(
      pattern: #"(?<!\d)(\d{1,2}:\d{2}(?::\d{2})?)(?!\d)"#
    ) else { return [] }

    let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
    let matches = regex.matches(in: text, range: nsRange)

    var seen = Set<String>()
    var results: [(text: String, seconds: TimeInterval)] = []

    for match in matches {
      guard let range = Range(match.range(at: 1), in: text) else { continue }
      let matched = String(text[range])
      guard !seen.contains(matched), let seconds = parseToSeconds(matched) else { continue }
      // Skip 0:00 / 00:00 / 00:00:00
      guard seconds > 0 else { continue }
      seen.insert(matched)
      results.append((text: matched, seconds: seconds))
    }

    return results
  }

  /// Formats seconds into a display string like "05:32" or "1:23:45".
  static func formatSeconds(_ seconds: TimeInterval) -> String {
    let total = Int(seconds)
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 {
      return String(format: "%d:%02d:%02d", h, m, s)
    } else {
      return String(format: "%02d:%02d", m, s)
    }
  }
}
