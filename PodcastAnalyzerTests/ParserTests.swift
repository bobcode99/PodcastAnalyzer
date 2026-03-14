//
//  ParserTests.swift
//  PodcastAnalyzerTests
//
//  Tests for SRTParser and VTTParser — deterministic, no side effects.
//  No singletons, no I/O, parallel-safe.
//

import Testing
@testable import PodcastAnalyzer

// MARK: - SRT Parser Tests

// SRTParser and TranscriptSegment inherit @MainActor from the app target's global default.
@MainActor
struct SRTParserTests {

    private let sampleSRT = """
        1
        00:00:00,000 --> 00:00:05,000
        Hello world.

        2
        00:00:06,000 --> 00:00:10,000
        Goodbye.
        """

    // MARK: extractPlainText

    @Test func extractPlainText_joinsSegmentsWithSpaces() {
        let result = SRTParser.extractPlainText(from: sampleSRT)
        #expect(result == "Hello world. Goodbye.")
    }

    @Test func extractPlainText_emptyContent_returnsEmptyString() {
        #expect(SRTParser.extractPlainText(from: "").isEmpty)
    }

    @Test func extractPlainText_skipsSequenceNumbersAndTimestamps() {
        // Verify sequence numbers (1, 2) and timestamps don't appear in output
        let result = SRTParser.extractPlainText(from: sampleSRT)
        #expect(!result.contains("-->"))
        #expect(!result.contains("00:00:"))
    }

    // MARK: parseSegments

    @Test func parseSegments_returnsCorrectCount() {
        let segments = SRTParser.parseSegments(from: sampleSRT)
        #expect(segments.count == 2)
    }

    @Test func parseSegments_emptyContent_returnsEmpty() {
        #expect(SRTParser.parseSegments(from: "").isEmpty)
    }

    @Test func parseSegments_firstSegment_hasCorrectFields() throws {
        let segments = SRTParser.parseSegments(from: sampleSRT)
        let first = try #require(segments.first)
        #expect(first.id == 1)
        #expect(first.startTime == 0.0)
        #expect(first.endTime == 5.0)
        #expect(first.text == "Hello world.")
    }

    @Test func parseSegments_secondSegment_hasCorrectFields() throws {
        let segments = SRTParser.parseSegments(from: sampleSRT)
        let second = try #require(segments.last)
        #expect(second.id == 2)
        #expect(second.startTime == 6.0)
        #expect(second.endTime == 10.0)
        #expect(second.text == "Goodbye.")
    }

    @Test func parseSegments_fileWithoutTrailingNewline_parsesLastSegment() {
        let srt = "1\n00:00:00,000 --> 00:00:05,000\nTrailing."
        let segments = SRTParser.parseSegments(from: srt)
        #expect(segments.count == 1)
        #expect(segments.first?.text == "Trailing.")
    }

    // MARK: estimateTokenCount

    @Test(arguments: [
        ("", "en", 0),
        ("ABCD", "en", 1),      // ceil(4 / 4.0) = 1
        ("ABCDE", "en", 2),     // ceil(5 / 4.0) = 2
        ("你好", "zh", 2),       // ceil(2 / 1.5) = 2
        ("abc", "ja", 2),       // ceil(3 / 1.5) = 2
        ("abc", "ko", 2),       // ceil(3 / 1.5) = 2
        ("hello", "EN", 2),     // case-insensitive language code
    ] as [(String, String, Int)])
    func estimateTokenCount(text: String, language: String, expected: Int) {
        #expect(SRTParser.estimateTokenCount(for: text, language: language) == expected)
    }

    // MARK: TranscriptSegment.getText

    @Test func getText_returnsSegmentsInRange() {
        let segments = [
            TranscriptSegment(id: 1, startTime: 0, endTime: 5, text: "One"),
            TranscriptSegment(id: 2, startTime: 5, endTime: 10, text: "Two"),
            TranscriptSegment(id: 3, startTime: 10, endTime: 15, text: "Three"),
        ]
        let result = TranscriptSegment.getText(from: segments, startIndex: 1, endIndex: 2)
        #expect(result == "One Two")
    }

    @Test func getText_singleSegment() {
        let segments = [
            TranscriptSegment(id: 5, startTime: 0, endTime: 5, text: "Only"),
        ]
        let result = TranscriptSegment.getText(from: segments, startIndex: 5, endIndex: 5)
        #expect(result == "Only")
    }

    @Test func getText_noMatchingRange_returnsEmpty() {
        let segments = [
            TranscriptSegment(id: 1, startTime: 0, endTime: 5, text: "One"),
        ]
        let result = TranscriptSegment.getText(from: segments, startIndex: 10, endIndex: 20)
        #expect(result.isEmpty)
    }
}

// MARK: - VTT Parser Tests

// TranscriptSegment properties inherit @MainActor from the app target.
@MainActor
struct VTTParserTests {

    private let sampleVTT = """
        WEBVTT

        00:00:00.000 --> 00:00:05.000
        Hello world.

        00:00:06.000 --> 00:00:10.000
        Goodbye.
        """

    // MARK: isVTTContent

    @Test(arguments: [
        ("WEBVTT\n\n00:00:00.000 --> 00:00:05.000\nHello.", true),
        ("WEBVTT", true),
        ("  WEBVTT", true),      // leading whitespace trimmed
        ("1\n00:00:00,000 --> 00:00:05,000\nHello.", false),
        ("", false),
    ] as [(String, Bool)])
    func isVTTContent(content: String, expected: Bool) {
        #expect(VTTParser.isVTTContent(content) == expected)
    }

    // MARK: isVTTType

    @Test(arguments: [
        ("text/vtt", true),
        ("TEXT/VTT", true),          // case-insensitive
        ("application/x-vtt", true), // contains "vtt"
        ("application/srt", false),
        ("text/plain", false),
        ("", false),
    ] as [(String, Bool)])
    func isVTTType(mimeType: String, expected: Bool) {
        #expect(VTTParser.isVTTType(mimeType) == expected)
    }

    // MARK: parseSegments

    @Test func parseSegments_returnsCorrectCount() {
        let segments = VTTParser.parseSegments(from: sampleVTT)
        #expect(segments.count == 2)
    }

    @Test func parseSegments_firstSegment() throws {
        let segments = VTTParser.parseSegments(from: sampleVTT)
        let first = try #require(segments.first)
        #expect(first.startTime == 0.0)
        #expect(first.endTime == 5.0)
        #expect(first.text == "Hello world.")
    }

    @Test func parseSegments_skipsWEBVTTHeader() {
        // Header block should be filtered out
        let segments = VTTParser.parseSegments(from: sampleVTT)
        #expect(!segments.contains(where: { $0.text.contains("WEBVTT") }))
    }

    @Test func parseSegments_emptyContent_returnsEmpty() {
        #expect(VTTParser.parseSegments(from: "WEBVTT\n").isEmpty)
    }

    @Test func parseSegments_decodesHTMLEntities() throws {
        let vtt = "WEBVTT\n\n00:00:00.000 --> 00:00:05.000\nHello &amp; World &lt;3"
        let segments = VTTParser.parseSegments(from: vtt)
        let first = try #require(segments.first)
        #expect(first.text == "Hello & World <3")
    }

    @Test func parseSegments_stripsVoiceTags() throws {
        let vtt = "WEBVTT\n\n00:00:00.000 --> 00:00:05.000\n<v Speaker>Hello there."
        let segments = VTTParser.parseSegments(from: vtt)
        let first = try #require(segments.first)
        #expect(first.text == "Hello there.")
    }

    @Test func parseSegments_mmSSFormat_parsedCorrectly() throws {
        // VTT also supports MM:SS.mmm timestamps
        let vtt = "WEBVTT\n\n01:05.000 --> 01:10.000\nShort format."
        let segments = VTTParser.parseSegments(from: vtt)
        let first = try #require(segments.first)
        #expect(first.startTime == 65.0)
        #expect(first.endTime == 70.0)
    }

    // MARK: convertToSRT

    @Test func convertToSRT_producesValidSRTOutput() {
        let srt = VTTParser.convertToSRT(sampleVTT)
        // SRT uses comma separator for milliseconds
        #expect(srt.contains("-->"))
        #expect(srt.contains(","))          // SRT millisecond separator
        #expect(!srt.contains("WEBVTT"))    // VTT header stripped
        #expect(srt.contains("Hello world."))
        #expect(srt.contains("Goodbye."))
    }

    @Test func convertToSRT_sequenceNumbersAscend() {
        let srt = VTTParser.convertToSRT(sampleVTT)
        // Both segments should appear with sequence numbers
        #expect(srt.hasPrefix("1\n"))
        #expect(srt.contains("2\n"))
    }

    // MARK: extractPlainText

    @Test func extractPlainText_joinsBothSegments() {
        let text = VTTParser.extractPlainText(from: sampleVTT)
        #expect(text == "Hello world. Goodbye.")
    }
}
