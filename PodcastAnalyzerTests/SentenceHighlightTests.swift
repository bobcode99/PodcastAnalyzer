//
//  SentenceHighlightTests.swift
//  PodcastAnalyzerTests
//
//  Tests for sentence highlight mode: paragraph grouping, per-segment highlighting,
//  and CJK text joining for English, Chinese, Japanese, and Korean transcripts.
//

import Foundation
import Testing
@testable import PodcastAnalyzer

// MARK: - Helper

private func makeSegment(id: Int, start: TimeInterval, end: TimeInterval, text: String) -> TranscriptSegment {
    TranscriptSegment(id: id, startTime: start, endTime: end, text: text)
}

// MARK: - Paragraph Grouping Tests

@MainActor
struct ParagraphGroupingTests {

    @Test func englishGroupsAtSentenceEnding() {
        let segments = [
            makeSegment(id: 0, start: 0, end: 2.58, text: "This BBC podcast is supported by ads"),
            makeSegment(id: 1, start: 2.58, end: 3.899, text: "outside the UK."),
            makeSegment(id: 2, start: 3.96, end: 7.86, text: "If journalism is the 1st draft of"),
            makeSegment(id: 3, start: 7.86, end: 8.279, text: "history."),
            makeSegment(id: 4, start: 8.339, end: 10.619, text: "What happens if that draft is flawed?"),
        ]

        let sentences = TranscriptGrouping.groupIntoParagraphSentences(segments)

        #expect(sentences.count == 3)
        // Sentence 1: "This BBC podcast is supported by ads outside the UK."
        #expect(sentences[0].segments.count == 2)
        #expect(sentences[0].text == "This BBC podcast is supported by ads outside the UK.")
        // Sentence 2: "If journalism is the 1st draft of history."
        #expect(sentences[1].segments.count == 2)
        #expect(sentences[1].text == "If journalism is the 1st draft of history.")
        // Sentence 3: "What happens if that draft is flawed?"
        #expect(sentences[2].segments.count == 1)
    }

    @Test func chineseGroupsAtSentenceEnding() {
        let segments = [
            makeSegment(id: 0, start: 0, end: 2, text: "这个BBC播客"),
            makeSegment(id: 1, start: 2, end: 4, text: "在英国以外有广告。"),
            makeSegment(id: 2, start: 4, end: 6, text: "如果新闻是历史的"),
            makeSegment(id: 3, start: 6, end: 8, text: "第一稿。"),
        ]

        let sentences = TranscriptGrouping.groupIntoParagraphSentences(segments)

        #expect(sentences.count == 2)
        // CJK text joined without spaces
        #expect(sentences[0].text == "这个BBC播客在英国以外有广告。")
        #expect(sentences[1].text == "如果新闻是历史的第一稿。")
    }

    @Test func japaneseGroupsAtSentenceEnding() {
        let segments = [
            makeSegment(id: 0, start: 0, end: 3, text: "このBBCポッドキャストは"),
            makeSegment(id: 1, start: 3, end: 5, text: "広告でサポートされています。"),
            makeSegment(id: 2, start: 5, end: 8, text: "ジャーナリズムとは何か？"),
        ]

        let sentences = TranscriptGrouping.groupIntoParagraphSentences(segments)

        #expect(sentences.count == 2)
        #expect(sentences[0].text == "このBBCポッドキャストは広告でサポートされています。")
        #expect(sentences[1].segments.count == 1)
    }

    @Test func koreanGroupsAtSentenceEnding() {
        let segments = [
            makeSegment(id: 0, start: 0, end: 2, text: "이 팟캐스트는"),
            makeSegment(id: 1, start: 2, end: 4, text: "광고로 지원됩니다."),
            makeSegment(id: 2, start: 4, end: 6, text: "언론이란 무엇인가?"),
        ]

        let sentences = TranscriptGrouping.groupIntoParagraphSentences(segments)

        #expect(sentences.count == 2)
        // Korean contains Hangul → CJK, joined without spaces
        #expect(sentences[0].text == "이 팟캐스트는광고로 지원됩니다.")
        #expect(sentences[1].segments.count == 1)
    }

    @Test func maxSegmentsForceBreak() {
        // 9 segments without punctuation — should break at 8
        let segments = (0..<9).map {
            makeSegment(id: $0, start: Double($0), end: Double($0 + 1), text: "word\($0)")
        }

        let sentences = TranscriptGrouping.groupIntoParagraphSentences(segments)

        #expect(sentences.count == 2)
        #expect(sentences[0].segments.count == 8)
        #expect(sentences[1].segments.count == 1)
    }

    @Test func charLimitForceBreak() {
        // 4 segments each 120 chars, no punctuation
        // After segment 2: 240 chars (< 300, no break)
        // After segment 3: 360 chars (>= 300, breaks → sentence 1 = 3 segments)
        // Segment 4 is leftover → sentence 2 = 1 segment
        let longText = String(repeating: "a", count: 120)
        let segments = (0..<4).map {
            makeSegment(id: $0, start: Double($0), end: Double($0 + 1), text: longText)
        }

        let sentences = TranscriptGrouping.groupIntoParagraphSentences(segments)

        #expect(sentences.count == 2)
        #expect(sentences[0].segments.count == 3)
        #expect(sentences[1].segments.count == 1)
    }
}

// MARK: - Per-Segment Highlight State Tests

@MainActor
struct SegmentHighlightStateTests {

    private func makeSentence() -> TranscriptSentence {
        TranscriptSentence(id: 0, segments: [
            makeSegment(id: 0, start: 0, end: 2.58, text: "This BBC podcast is supported by ads"),
            makeSegment(id: 1, start: 2.58, end: 3.899, text: "outside the UK."),
        ])
    }

    @Test func firstSegmentHighlightedAtStart() {
        let sentence = makeSentence()
        let state = TranscriptGrouping.highlightState(for: sentence, currentTime: 1.0)

        #expect(state == .active(activeSegmentIndex: 0))
    }

    @Test func secondSegmentHighlightedAfterFirst() {
        let sentence = makeSentence()
        let state = TranscriptGrouping.highlightState(for: sentence, currentTime: 3.0)

        #expect(state == .active(activeSegmentIndex: 1))
    }

    @Test func sentencePlayedAfterEnd() {
        let sentence = makeSentence()
        let state = TranscriptGrouping.highlightState(for: sentence, currentTime: 5.0)

        #expect(state == .played)
    }

    @Test func sentenceFutureBeforeStart() {
        let sentence = makeSentence()
        let state = TranscriptGrouping.highlightState(for: sentence, currentTime: nil)

        #expect(state == .future)
    }

    @Test func crossSentenceTransition() {
        let sentences = [
            TranscriptSentence(id: 0, segments: [
                makeSegment(id: 0, start: 0, end: 2.58, text: "This BBC podcast is supported by ads"),
                makeSegment(id: 1, start: 2.58, end: 3.899, text: "outside the UK."),
            ]),
            TranscriptSentence(id: 1, segments: [
                makeSegment(id: 2, start: 3.96, end: 7.86, text: "If journalism is the 1st draft of"),
                makeSegment(id: 3, start: 7.86, end: 8.279, text: "history."),
            ]),
        ]

        // At time 4.0: sentence 0 should be played, sentence 1 should be active (segment index 0)
        let state0 = TranscriptGrouping.highlightState(for: sentences[0], currentTime: 4.0)
        let state1 = TranscriptGrouping.highlightState(for: sentences[1], currentTime: 4.0)

        #expect(state0 == .played)
        #expect(state1 == .active(activeSegmentIndex: 0))
    }
}

// MARK: - CJK Text Joining Tests

@MainActor
struct SentenceTextJoiningTests {

    @Test func englishJoinedWithSpaces() {
        let sentence = TranscriptSentence(id: 0, segments: [
            makeSegment(id: 0, start: 0, end: 2, text: "This is"),
            makeSegment(id: 1, start: 2, end: 4, text: "a test."),
        ])
        #expect(sentence.text == "This is a test.")
    }

    @Test func chineseJoinedWithoutSpaces() {
        let sentence = TranscriptSentence(id: 0, segments: [
            makeSegment(id: 0, start: 0, end: 2, text: "这个"),
            makeSegment(id: 1, start: 2, end: 4, text: "函数"),
            makeSegment(id: 2, start: 4, end: 6, text: "有问题。"),
        ])
        #expect(sentence.text == "这个函数有问题。")
    }

    @Test func japaneseJoinedWithoutSpaces() {
        let sentence = TranscriptSentence(id: 0, segments: [
            makeSegment(id: 0, start: 0, end: 2, text: "これは"),
            makeSegment(id: 1, start: 2, end: 4, text: "テストです。"),
        ])
        #expect(sentence.text == "これはテストです。")
    }

    @Test func koreanJoinedWithoutSpaces() {
        let sentence = TranscriptSentence(id: 0, segments: [
            makeSegment(id: 0, start: 0, end: 2, text: "이것은"),
            makeSegment(id: 1, start: 2, end: 4, text: "테스트입니다."),
        ])
        #expect(sentence.text == "이것은테스트입니다.")
    }
}
