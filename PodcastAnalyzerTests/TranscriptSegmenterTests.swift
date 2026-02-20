//
//  TranscriptSegmenterTests.swift
//  PodcastAnalyzerTests
//
//  Tests for TranscriptSegmenter.isSentenceEnd.
//  Pure function tests — no singletons, no I/O, parallel-safe.
//

import Testing
@testable import PodcastAnalyzer

// TranscriptSegmenter inherits @MainActor from the app target's global default.
@MainActor
struct TranscriptSegmenterTests {

    /// Convenience factory: isCJK/maxLength don't affect isSentenceEnd.
    private func segmenter() -> TranscriptSegmenter {
        TranscriptSegmenter(isCJK: false, maxLength: 100)
    }

    // MARK: isSentenceEnd — terminal punctuation (should return true)

    @Test(arguments: [
        "Hello.",
        "Wow!",
        "Really?",
        "你好。",       // CJK full-stop
        "怎麼了？",     // CJK question mark
        "太好了！",     // CJK exclamation
        "Ends with space. ",    // trimmed → last char is '.'
    ])
    func isSentenceEnd_returnsTrueForTerminalPunctuation(text: String) {
        #expect(segmenter().isSentenceEnd(text))
    }

    // MARK: isSentenceEnd — non-terminal (should return false)

    @Test(arguments: [
        "Hello",
        "comma,",
        "semicolon;",
        "colon:",
        "",
        "   ",          // whitespace only → trimmed to "" → no last char
    ])
    func isSentenceEnd_returnsFalseForNonTerminal(text: String) {
        #expect(!segmenter().isSentenceEnd(text))
    }

    // MARK: isSentenceEnd — edge cases

    @Test func isSentenceEnd_singlePeriod_returnsTrue() {
        #expect(segmenter().isSentenceEnd("."))
    }

    @Test func isSentenceEnd_singleLetter_returnsFalse() {
        #expect(!segmenter().isSentenceEnd("A"))
    }

    @Test func isSentenceEnd_sentenceEndingWithTrailingWhitespace() {
        // Trailing whitespace trimmed — last real char is '.'
        #expect(segmenter().isSentenceEnd("Done.\n"))
    }
}
