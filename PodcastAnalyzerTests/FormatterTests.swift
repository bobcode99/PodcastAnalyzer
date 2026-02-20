//
//  FormatterTests.swift
//  PodcastAnalyzerTests
//
//  Tests for SRTFormatter.formatTime and formatTimeSafe.
//  Pure function tests — no singletons, no I/O, parallel-safe.
//

import Foundation
import Testing
@testable import PodcastAnalyzer

struct SRTFormatterTests {

    // MARK: - formatTime

    // Values chosen to be exact in IEEE 754 binary64 (no rounding surprises).
    @Test(arguments: zip(
        [0.0, 61.5, 3661.0, 3723.25] as [TimeInterval],
        ["00:00:00,000", "00:01:01,500", "01:01:01,000", "01:02:03,250"]
    ))
    func formatTime(interval: TimeInterval, expected: String) {
        #expect(SRTFormatter.formatTime(interval) == expected)
    }

    @Test func formatTime_largeHours() {
        // 90061s = 25h 1m 1s
        #expect(SRTFormatter.formatTime(90061.0) == "25:01:01,000")
    }

    // MARK: - formatTimeSafe

    @Test(arguments: [Double.nan, Double.infinity, -Double.infinity, -1.0])
    func formatTimeSafe_returnsZeroString(value: Double) {
        #expect(SRTFormatter.formatTimeSafe(value) == "00:00:00,000")
    }

    @Test func formatTimeSafe_positiveInput_matchesFormatTime() {
        let interval: TimeInterval = 90.0  // 1m 30s
        #expect(SRTFormatter.formatTimeSafe(interval) == SRTFormatter.formatTime(interval))
    }
}
