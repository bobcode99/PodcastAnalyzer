//
//  TranscriptHighlightTests.swift
//  PodcastAnalyzerTests
//
//  Tests for transcript segment highlighting logic
//

import XCTest
@testable import PodcastAnalyzer

@MainActor
final class TranscriptHighlightTests: XCTestCase {

    // MARK: - Test Data from SRT Example

    /// Creates test segments from the provided SRT example
    static let testSegments: [TranscriptSegment] = [
        TranscriptSegment(id: 1, startTime: 0.000, endTime: 0.780, text: "Hello, hello."),
        TranscriptSegment(id: 2, startTime: 0.840, endTime: 2.220, text: "Today is a great day, isn't it?"),
        TranscriptSegment(id: 3, startTime: 2.279, endTime: 4.080, text: "In this episode, I'm gonna gush about"),
        TranscriptSegment(id: 4, startTime: 4.080, endTime: 5.040, text: "threat locker."),
        TranscriptSegment(id: 5, startTime: 5.099, endTime: 5.519, text: "Why?"),
        TranscriptSegment(id: 6, startTime: 5.580, endTime: 7.080, text: "Well, currently they're my biggest"),
        TranscriptSegment(id: 7, startTime: 7.080, endTime: 8.460, text: "sponsor, which makes them my favorite"),
        TranscriptSegment(id: 8, startTime: 8.460, endTime: 9.240, text: "sponsor."),
    ]

    // MARK: - Sentence Grouping Tests

    func testSentenceGrouping() {
        let sentences = TranscriptGrouping.groupIntoSentences(Self.testSegments)

        // Expected sentences based on punctuation:
        // 1. "Hello, hello." (segment 1)
        // 2. "Today is a great day, isn't it?" (segment 2)
        // 3. "In this episode, I'm gonna gush about threat locker." (segments 3-4)
        // 4. "Why?" (segment 5)
        // 5. "Well, currently they're my biggest sponsor, which makes them my favorite sponsor." (segments 6-8)

        XCTAssertEqual(sentences.count, 5, "Should have 5 sentences")

        // Sentence 1: one segment
        XCTAssertEqual(sentences[0].segments.count, 1)
        XCTAssertEqual(sentences[0].segments[0].id, 1)

        // Sentence 2: one segment
        XCTAssertEqual(sentences[1].segments.count, 1)
        XCTAssertEqual(sentences[1].segments[0].id, 2)

        // Sentence 3: two segments (3 and 4)
        XCTAssertEqual(sentences[2].segments.count, 2)
        XCTAssertEqual(sentences[2].segments[0].id, 3)
        XCTAssertEqual(sentences[2].segments[1].id, 4)

        // Sentence 4: one segment
        XCTAssertEqual(sentences[3].segments.count, 1)
        XCTAssertEqual(sentences[3].segments[0].id, 5)

        // Sentence 5: three segments (6, 7, 8)
        XCTAssertEqual(sentences[4].segments.count, 3)
        XCTAssertEqual(sentences[4].segments[0].id, 6)
        XCTAssertEqual(sentences[4].segments[1].id, 7)
        XCTAssertEqual(sentences[4].segments[2].id, 8)
    }

    // MARK: - Active Segment Detection Tests

    func testActiveSegmentExactMatch() {
        let sentences = TranscriptGrouping.groupIntoSentences(Self.testSegments)
        let sentence3 = sentences[2] // "In this episode... threat locker."

        // Time 3.0 should be in segment 3 (2.279 - 4.080)
        let activeAt3 = sentence3.activeSegment(at: 3.0)
        XCTAssertNotNil(activeAt3, "Should find active segment at time 3.0")
        XCTAssertEqual(activeAt3?.id, 3, "Active segment at 3.0 should be segment 3")

        // Time 4.5 should be in segment 4 (4.080 - 5.040)
        let activeAt4_5 = sentence3.activeSegment(at: 4.5)
        XCTAssertNotNil(activeAt4_5, "Should find active segment at time 4.5")
        XCTAssertEqual(activeAt4_5?.id, 4, "Active segment at 4.5 should be segment 4")
    }

    func testActiveSegmentAtBoundary() {
        let sentences = TranscriptGrouping.groupIntoSentences(Self.testSegments)
        let sentence3 = sentences[2]

        // Time exactly at segment boundary (4.080) - both segments share this boundary
        // segment 3: 2.279-4.080, segment 4: 4.080-5.040
        // Since we use time >= start && time <= end, both match at 4.080
        // But .first will return segment 3 (the one ending at 4.080)
        let activeAtBoundary = sentence3.activeSegment(at: 4.080)
        XCTAssertNotNil(activeAtBoundary, "Should find active segment at boundary 4.080")
        // Either segment 3 or 4 is acceptable since they share the boundary
        XCTAssertTrue(activeAtBoundary?.id == 3 || activeAtBoundary?.id == 4,
                      "Should be segment 3 or 4 at boundary")
    }

    // MARK: - Gap Handling Tests (CORRECT BEHAVIOR)

    func testActiveSegmentInGapReturnsNil() {
        // Create a sentence with a gap between segments
        let segmentsWithGap = [
            TranscriptSegment(id: 100, startTime: 0.0, endTime: 1.0, text: "First part"),
            TranscriptSegment(id: 101, startTime: 1.5, endTime: 2.5, text: "second part."), // Gap: 1.0-1.5
        ]

        let sentences = TranscriptGrouping.groupIntoSentences(segmentsWithGap)
        XCTAssertEqual(sentences.count, 1, "Should have 1 sentence")

        let sentence = sentences[0]

        // Sentence time range: 0.0 - 2.5
        XCTAssertEqual(sentence.startTime, 0.0)
        XCTAssertEqual(sentence.endTime, 2.5)

        // Time 1.2 is within sentence but in the gap between segments
        XCTAssertTrue(sentence.containsTime(1.2), "Sentence should contain time 1.2 (within overall range)")

        // CORRECT BEHAVIOR: No segment contains time 1.2, so return nil
        let activeInGap = sentence.activeSegment(at: 1.2)
        XCTAssertNil(activeInGap, "Should return nil when time is in a gap between segments")
    }

    func testActiveSegmentBeforeFirstSegment() {
        let segmentsWithGap = [
            TranscriptSegment(id: 100, startTime: 1.0, endTime: 2.0, text: "First part"),
            TranscriptSegment(id: 101, startTime: 2.5, endTime: 3.5, text: "second part."),
        ]

        let sentences = TranscriptGrouping.groupIntoSentences(segmentsWithGap)
        let sentence = sentences[0]

        // Time 0.5 is before any segment
        let activeBeforeFirst = sentence.activeSegment(at: 0.5)
        XCTAssertNil(activeBeforeFirst, "Should return nil when time is before first segment")
    }

    func testActiveSegmentAfterLastSegment() {
        let segmentsWithGap = [
            TranscriptSegment(id: 100, startTime: 0.0, endTime: 1.0, text: "First part"),
            TranscriptSegment(id: 101, startTime: 1.5, endTime: 2.5, text: "second part."),
        ]

        let sentences = TranscriptGrouping.groupIntoSentences(segmentsWithGap)
        let sentence = sentences[0]

        // Time 3.0 is after all segments
        let activeAfterLast = sentence.activeSegment(at: 3.0)
        XCTAssertNil(activeAfterLast, "Should return nil when time is after last segment")
    }

    // MARK: - Test with real SRT gap

    func testRealSRTGap() {
        // From the actual SRT: segment 1 ends at 0.780, segment 2 starts at 0.840
        // Gap of 60ms between separate sentences
        let sentences = TranscriptGrouping.groupIntoSentences(Self.testSegments)

        // Check segment 3-4 boundary in sentence 3
        let sentence3 = sentences[2] // segments 3 and 4

        // Segment 3: 2.279 - 4.080
        // Segment 4: 4.080 - 5.040
        // No gap here, they share boundary at 4.080

        // Verify times within each segment find correct active segment
        let activeAt3 = sentence3.activeSegment(at: 3.0)
        XCTAssertEqual(activeAt3?.id, 3, "Time 3.0 should be in segment 3")

        let activeAt4_5 = sentence3.activeSegment(at: 4.5)
        XCTAssertEqual(activeAt4_5?.id, 4, "Time 4.5 should be in segment 4")
    }

    // MARK: - Highlight Logic Simulation

    func testHighlightLogicSimulation() {
        let sentences = TranscriptGrouping.groupIntoSentences(Self.testSegments)
        let sentence3 = sentences[2] // "In this episode... threat locker." (segments 3-4)

        let currentTime: TimeInterval = 3.5 // Middle of segment 3
        let activeSegment = sentence3.activeSegment(at: currentTime)

        XCTAssertNotNil(activeSegment, "Should find active segment")
        XCTAssertEqual(activeSegment?.id, 3, "Segment 3 should be active at time 3.5")

        // Verify segment states
        for segment in sentence3.segments {
            let isActiveSegment = activeSegment?.id == segment.id
            let isPast = currentTime > segment.endTime

            if segment.id == 3 {
                XCTAssertTrue(isActiveSegment, "Segment 3 should be ACTIVE at time 3.5")
                XCTAssertFalse(isPast, "Segment 3 should NOT be PAST at time 3.5")
            } else if segment.id == 4 {
                XCTAssertFalse(isActiveSegment, "Segment 4 should NOT be ACTIVE at time 3.5")
                XCTAssertFalse(isPast, "Segment 4 should be FUTURE at time 3.5")
            }
        }
    }

    // MARK: - Past/Future Coloring When in Gap

    func testHighlightingInGap() {
        // When time is in a gap:
        // - No segment is ACTIVE (activeSegment returns nil)
        // - Past segments should be colored as PAST (time > segment.endTime)
        // - Future segments should be colored as FUTURE (time < segment.startTime)

        let segmentsWithGap = [
            TranscriptSegment(id: 100, startTime: 0.0, endTime: 1.0, text: "First part"),
            TranscriptSegment(id: 101, startTime: 1.5, endTime: 2.5, text: "second part."),
        ]

        let sentences = TranscriptGrouping.groupIntoSentences(segmentsWithGap)
        let sentence = sentences[0]

        let currentTime: TimeInterval = 1.2 // In the gap between 1.0 and 1.5
        let activeSegment = sentence.activeSegment(at: currentTime)

        // No active segment in gap
        XCTAssertNil(activeSegment, "No segment should be ACTIVE when in gap")

        // Check past/future status for each segment
        let segment100 = sentence.segments[0]
        let segment101 = sentence.segments[1]

        // Segment 100 (0.0-1.0) is PAST because currentTime (1.2) > endTime (1.0)
        XCTAssertTrue(currentTime > segment100.endTime, "Segment 100 should be PAST")

        // Segment 101 (1.5-2.5) is FUTURE because currentTime (1.2) < startTime (1.5)
        XCTAssertTrue(currentTime < segment101.startTime, "Segment 101 should be FUTURE")
    }

    // MARK: - Multi-Segment Sentence: Only ONE Active at a Time

    func testMultiSegmentSentenceOnlyOneActive() {
        let sentences = TranscriptGrouping.groupIntoSentences(Self.testSegments)
        let sentence5 = sentences[4] // segments 6, 7, 8

        // Test at time 7.5 (in segment 7: 7.080-8.460)
        let activeAt7_5 = sentence5.activeSegment(at: 7.5)
        XCTAssertNotNil(activeAt7_5)
        XCTAssertEqual(activeAt7_5?.id, 7, "Only segment 7 should be active at time 7.5")

        // Count how many segments would be marked as active
        var activeCount = 0
        for segment in sentence5.segments {
            if activeAt7_5?.id == segment.id {
                activeCount += 1
            }
        }
        XCTAssertEqual(activeCount, 1, "Exactly ONE segment should be active at any time")
    }

    // MARK: - Edge Cases

    func testEmptySegments() {
        let emptySegments: [TranscriptSegment] = []
        let sentences = TranscriptGrouping.groupIntoSentences(emptySegments)
        XCTAssertTrue(sentences.isEmpty, "Empty segments should produce empty sentences")
    }

    func testSingleSegment() {
        let singleSegment = [
            TranscriptSegment(id: 1, startTime: 0.0, endTime: 1.0, text: "Only segment.")
        ]
        let sentences = TranscriptGrouping.groupIntoSentences(singleSegment)
        XCTAssertEqual(sentences.count, 1)
        XCTAssertEqual(sentences[0].segments.count, 1)

        let active = sentences[0].activeSegment(at: 0.5)
        XCTAssertEqual(active?.id, 1)
    }
}
