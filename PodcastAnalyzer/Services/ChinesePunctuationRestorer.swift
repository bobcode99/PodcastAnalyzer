//
//  ChinesePunctuationRestorer.swift
//  PodcastAnalyzer
//
//  Rule-based punctuation insertion for CJK transcripts.
//  Apple's Speech framework does not auto-insert punctuation for Chinese.
//  Uses audio time gaps between runs as the primary signal.
//

import Foundation
import Speech

@available(iOS 17.0, *)
nonisolated struct ChinesePunctuationRestorer {

  /// Minimum gap (seconds) between runs to insert a comma (，)
  var commaThreshold: Double = 0.5

  /// Minimum gap (seconds) between runs to insert a period (。)
  var periodThreshold: Double = 1.0

  /// Question-ending particles that turn a period into a question mark
  private static let questionParticles: [String] = [
    "嗎", "吗", "呢", "吧", "嘛",
    "對不對", "对不对",
    "是不是", "好不好",
    "對吧", "对吧",
  ]

  /// Sentence-ending punctuation already present — skip insertion if found
  private static let existingTerminators: Set<Character> = [
    "。", "？", "！", ".", "?", "!",
    "，", "、", "；", "：",
    ",", ";",
  ]

  /// Restores punctuation in a CJK AttributedString using audio time gaps.
  ///
  /// Strategy:
  /// 1. Walk runs in order, tracking the end-time of the previous run.
  /// 2. When the gap between the previous run's end and the current run's start
  ///    exceeds a threshold, insert punctuation after the previous run.
  /// 3. Post-process: replace trailing 。 with ？ if the text ends with a question particle.
  func restore(transcript: AttributedString) -> AttributedString {
    // Collect runs with their audio time ranges
    struct RunInfo {
      let range: Range<AttributedString.Index>
      let text: String
      let startTime: Double
      let endTime: Double
    }

    var runs: [RunInfo] = []
    for run in transcript.runs {
      let text = String(transcript[run.range].characters)
      guard let timeRange = run.audioTimeRange else {
        // Preserve runs without timing (whitespace, etc.) as-is
        continue
      }
      let start = timeRange.start.seconds
      let end = timeRange.end.seconds
      guard start.isFinite && end.isFinite else { continue }
      runs.append(RunInfo(range: run.range, text: text, startTime: start, endTime: end))
    }

    guard runs.count >= 2 else { return transcript }

    // Determine where to insert punctuation — collect insertion points
    // Key: the AttributedString index *after* which to insert punctuation
    // Value: the punctuation character to insert
    var insertions: [(afterIndex: AttributedString.Index, punctuation: String)] = []

    for i in 0..<(runs.count - 1) {
      let currentRun = runs[i]
      let nextRun = runs[i + 1]

      let gap = nextRun.startTime - currentRun.endTime
      guard gap >= commaThreshold else { continue }

      // Check if current run already ends with punctuation
      let trimmed = currentRun.text.trimmingCharacters(in: .whitespacesAndNewlines)
      if let lastChar = trimmed.last, Self.existingTerminators.contains(lastChar) {
        continue
      }

      let punctuation: String
      if gap >= periodThreshold {
        // Check for question pattern in the accumulated text up to this point
        let accumulatedText = accumulateText(runs: runs, through: i)
        if isQuestionEnding(accumulatedText) {
          punctuation = "？"
        } else {
          punctuation = "。"
        }
      } else {
        punctuation = "，"
      }

      insertions.append((afterIndex: currentRun.range.upperBound, punctuation: punctuation))
    }

    guard !insertions.isEmpty else { return transcript }

    // Build new AttributedString with punctuation inserted
    var result = AttributedString()
    var lastCopiedUpTo = transcript.startIndex

    for insertion in insertions {
      // Copy everything from lastCopiedUpTo to the insertion point
      if lastCopiedUpTo < insertion.afterIndex {
        result += transcript[lastCopiedUpTo..<insertion.afterIndex]
      }

      // Insert the punctuation character (inheriting no special attributes)
      result += AttributedString(insertion.punctuation)

      lastCopiedUpTo = insertion.afterIndex
    }

    // Copy remaining content after last insertion
    if lastCopiedUpTo < transcript.endIndex {
      result += transcript[lastCopiedUpTo..<transcript.endIndex]
    }

    return result
  }

  // MARK: - Private Helpers

  /// Accumulates plain text from runs[0...through]
  private func accumulateText(runs: [some Any], through index: Int) -> String {
    // We only need the last few characters to check question patterns
    // Re-type as we know the actual type from the caller
    guard let typedRuns = runs as? [(range: Range<AttributedString.Index>, text: String, startTime: Double, endTime: Double)] else {
      return ""
    }
    let start = max(0, index - 5)
    return typedRuns[start...index].map(\.text).joined()
  }

  /// Checks if accumulated text ends with a question pattern
  private func isQuestionEnding(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return Self.questionParticles.contains { trimmed.hasSuffix($0) }
  }
}
