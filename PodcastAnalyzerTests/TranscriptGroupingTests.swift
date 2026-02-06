//
//  TranscriptGroupingTests.swift
//  PodcastAnalyzerTests
//
//  Unit tests for TranscriptGrouping utilities and TranscriptSentence methods
//

import Foundation
import Testing
@testable import PodcastAnalyzer

@MainActor
struct TranscriptGroupingTests {

  // MARK: - Helper to create test segments

  private func makeSegment(id: Int, start: TimeInterval, end: TimeInterval, text: String) -> TranscriptSegment {
    TranscriptSegment(id: id, startTime: start, endTime: end, text: text)
  }

  // MARK: - isSentenceEnd Tests

  @Test func isSentenceEnd_withEnglishPeriod_returnsTrue() {
    #expect(TranscriptGrouping.isSentenceEnd("Hello world."))
    #expect(TranscriptGrouping.isSentenceEnd("End. ")) // with trailing space
  }

  @Test func isSentenceEnd_withExclamationMark_returnsTrue() {
    #expect(TranscriptGrouping.isSentenceEnd("Wow!"))
    #expect(TranscriptGrouping.isSentenceEnd("Amazing! "))
  }

  @Test func isSentenceEnd_withQuestionMark_returnsTrue() {
    #expect(TranscriptGrouping.isSentenceEnd("How are you?"))
    #expect(TranscriptGrouping.isSentenceEnd("Really? "))
  }

  @Test func isSentenceEnd_withCJKPeriod_returnsTrue() {
    #expect(TranscriptGrouping.isSentenceEnd("你好。")) // Chinese full stop
    #expect(TranscriptGrouping.isSentenceEnd("こんにちは。")) // Japanese period
  }

  @Test func isSentenceEnd_withCJKExclamation_returnsTrue() {
    #expect(TranscriptGrouping.isSentenceEnd("太棒了！")) // Chinese exclamation
  }

  @Test func isSentenceEnd_withCJKQuestion_returnsTrue() {
    #expect(TranscriptGrouping.isSentenceEnd("怎麼了？")) // Chinese question mark
  }

  @Test func isSentenceEnd_withNoEndingPunctuation_returnsFalse() {
    #expect(!TranscriptGrouping.isSentenceEnd("Hello world"))
    #expect(!TranscriptGrouping.isSentenceEnd("This is a comma,"))
    #expect(!TranscriptGrouping.isSentenceEnd("Semi-colon;"))
    #expect(!TranscriptGrouping.isSentenceEnd("Colon:"))
  }

  @Test func isSentenceEnd_withEmptyString_returnsFalse() {
    #expect(!TranscriptGrouping.isSentenceEnd(""))
    #expect(!TranscriptGrouping.isSentenceEnd("   "))
  }

  // MARK: - groupIntoSentences Tests

  @Test func groupIntoSentences_withEmptyInput_returnsEmpty() {
    let sentences = TranscriptGrouping.groupIntoSentences([])
    #expect(sentences.isEmpty)
  }

  @Test func groupIntoSentences_withSingleSegmentEndingSentence_returnsSingleSentence() {
    let segments = [makeSegment(id: 0, start: 0, end: 5, text: "Hello world.")]
    let sentences = TranscriptGrouping.groupIntoSentences(segments)

    #expect(sentences.count == 1)
    #expect(sentences[0].segments.count == 1)
    #expect(sentences[0].text == "Hello world.")
  }

  @Test func groupIntoSentences_groupsUntilPunctuation() {
    let segments = [
      makeSegment(id: 0, start: 0, end: 2, text: "This is"),
      makeSegment(id: 1, start: 2, end: 4, text: "a test."),
      makeSegment(id: 2, start: 4, end: 6, text: "New sentence."),
    ]
    let sentences = TranscriptGrouping.groupIntoSentences(segments)

    #expect(sentences.count == 2)
    #expect(sentences[0].segments.count == 2)
    #expect(sentences[0].text == "This is a test.")
    #expect(sentences[1].segments.count == 1)
    #expect(sentences[1].text == "New sentence.")
  }

  @Test func groupIntoSentences_respectsMaxSegmentsLimit() {
    // Create 6 segments without punctuation
    let segments = (0..<6).map { i in
      makeSegment(id: i, start: Double(i), end: Double(i + 1), text: "word\(i)")
    }
    let sentences = TranscriptGrouping.groupIntoSentences(segments)

    // With maxSegmentsPerSentence = 4, should create 2 sentences
    #expect(sentences.count == 2)
    #expect(sentences[0].segments.count == 4)
    #expect(sentences[1].segments.count == 2)
  }

  @Test func groupIntoSentences_handlesTrailingSegmentsWithoutPunctuation() {
    let segments = [
      makeSegment(id: 0, start: 0, end: 2, text: "Hello world."),
      makeSegment(id: 1, start: 2, end: 4, text: "Trailing"),
    ]
    let sentences = TranscriptGrouping.groupIntoSentences(segments)

    #expect(sentences.count == 2)
    #expect(sentences[1].text == "Trailing")
  }

  @Test func groupIntoSentences_assignsCorrectSentenceIds() {
    let segments = [
      makeSegment(id: 0, start: 0, end: 2, text: "First."),
      makeSegment(id: 1, start: 2, end: 4, text: "Second."),
      makeSegment(id: 2, start: 4, end: 6, text: "Third."),
    ]
    let sentences = TranscriptGrouping.groupIntoSentences(segments)

    #expect(sentences[0].id == 0)
    #expect(sentences[1].id == 1)
    #expect(sentences[2].id == 2)
  }

  // MARK: - highlightState Tests

  @Test func highlightState_withNilCurrentTime_returnsFuture() {
    let sentence = TranscriptSentence(id: 0, segments: [makeSegment(id: 0, start: 0, end: 5, text: "Test.")])
    let state = TranscriptGrouping.highlightState(for: sentence, currentTime: nil)
    #expect(state == .future)
  }

  @Test func highlightState_whenTimeBeforeSentence_returnsFuture() {
    let sentence = TranscriptSentence(id: 0, segments: [makeSegment(id: 0, start: 10, end: 15, text: "Test.")])
    let state = TranscriptGrouping.highlightState(for: sentence, currentTime: 5)
    #expect(state == .future)
  }

  @Test func highlightState_whenTimeAfterSentence_returnsPlayed() {
    let sentence = TranscriptSentence(id: 0, segments: [makeSegment(id: 0, start: 0, end: 5, text: "Test.")])
    let state = TranscriptGrouping.highlightState(for: sentence, currentTime: 10)
    #expect(state == .played)
  }

  @Test func highlightState_whenTimeWithinSegment_returnsActiveWithIndex() {
    let segments = [
      makeSegment(id: 0, start: 0, end: 3, text: "First"),
      makeSegment(id: 1, start: 3, end: 6, text: "Second"),
      makeSegment(id: 2, start: 6, end: 9, text: "Third."),
    ]
    let sentence = TranscriptSentence(id: 0, segments: segments)

    // Time in first segment
    let state0 = TranscriptGrouping.highlightState(for: sentence, currentTime: 1)
    #expect(state0 == .active(activeSegmentIndex: 0))

    // Time in second segment
    let state1 = TranscriptGrouping.highlightState(for: sentence, currentTime: 4)
    #expect(state1 == .active(activeSegmentIndex: 1))

    // Time in third segment
    let state2 = TranscriptGrouping.highlightState(for: sentence, currentTime: 7)
    #expect(state2 == .active(activeSegmentIndex: 2))
  }

  @Test func highlightState_whenTimeInGapBetweenSegments_returnsActiveWithNegativeIndex() {
    // Segments with a gap: [0-2], [4-6] (gap at 2-4)
    let segments = [
      makeSegment(id: 0, start: 0, end: 2, text: "First"),
      makeSegment(id: 1, start: 4, end: 6, text: "Second."),
    ]
    let sentence = TranscriptSentence(id: 0, segments: segments)

    // Time in the gap (sentence.containsTime returns true because 3 is between startTime=0 and endTime=6)
    let state = TranscriptGrouping.highlightState(for: sentence, currentTime: 3)
    #expect(state == .active(activeSegmentIndex: -1))
  }

  // MARK: - TranscriptSentence.containsTime Tests

  @Test func containsTime_whenTimeWithinBounds_returnsTrue() {
    let sentence = TranscriptSentence(id: 0, segments: [
      makeSegment(id: 0, start: 5, end: 10, text: "Test."),
    ])

    #expect(sentence.containsTime(5)) // at start
    #expect(sentence.containsTime(7)) // in middle
    #expect(sentence.containsTime(10)) // at end
  }

  @Test func containsTime_whenTimeOutsideBounds_returnsFalse() {
    let sentence = TranscriptSentence(id: 0, segments: [
      makeSegment(id: 0, start: 5, end: 10, text: "Test."),
    ])

    #expect(!sentence.containsTime(4.9))
    #expect(!sentence.containsTime(10.1))
  }

  // MARK: - TranscriptSentence.activeSegment Tests

  @Test func activeSegment_whenTimeInSegment_returnsSegment() {
    let segments = [
      makeSegment(id: 0, start: 0, end: 3, text: "First"),
      makeSegment(id: 1, start: 3, end: 6, text: "Second."),
    ]
    let sentence = TranscriptSentence(id: 0, segments: segments)

    let active = sentence.activeSegment(at: 4)
    #expect(active?.id == 1)
  }

  @Test func activeSegment_whenTimeInGap_returnsNil() {
    let segments = [
      makeSegment(id: 0, start: 0, end: 2, text: "First"),
      makeSegment(id: 1, start: 4, end: 6, text: "Second."),
    ]
    let sentence = TranscriptSentence(id: 0, segments: segments)

    let active = sentence.activeSegment(at: 3)
    #expect(active == nil)
  }

  @Test func activeSegment_whenTimeOutsideSentence_returnsNil() {
    let sentence = TranscriptSentence(id: 0, segments: [
      makeSegment(id: 0, start: 5, end: 10, text: "Test."),
    ])

    #expect(sentence.activeSegment(at: 4) == nil)
    #expect(sentence.activeSegment(at: 11) == nil)
  }

  // MARK: - SentenceHighlightState Equatable Tests

  @Test func sentenceHighlightState_equatable_activeWithSameIndex() {
    #expect(SentenceHighlightState.active(activeSegmentIndex: 0) == SentenceHighlightState.active(activeSegmentIndex: 0))
    #expect(SentenceHighlightState.active(activeSegmentIndex: 1) == SentenceHighlightState.active(activeSegmentIndex: 1))
  }

  @Test func sentenceHighlightState_equatable_activeWithDifferentIndex() {
    #expect(SentenceHighlightState.active(activeSegmentIndex: 0) != SentenceHighlightState.active(activeSegmentIndex: 1))
  }

  @Test func sentenceHighlightState_equatable_playedAndFuture() {
    #expect(SentenceHighlightState.played == SentenceHighlightState.played)
    #expect(SentenceHighlightState.future == SentenceHighlightState.future)
    #expect(SentenceHighlightState.played != SentenceHighlightState.future)
  }

  @Test func sentenceHighlightState_equatable_activeVsOthers() {
    #expect(SentenceHighlightState.active(activeSegmentIndex: 0) != SentenceHighlightState.played)
    #expect(SentenceHighlightState.active(activeSegmentIndex: 0) != SentenceHighlightState.future)
  }
}
