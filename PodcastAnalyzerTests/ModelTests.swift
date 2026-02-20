//
//  ModelTests.swift
//  PodcastAnalyzerTests
//
//  Tests for computed properties on pure model types:
//    - PodcastEpisodeInfo.formattedDuration
//    - LibraryEpisode.progress / hasProgress
//    - DownloadState Equatable and Codable
//  No singletons, no I/O, parallel-safe.
//

import Foundation
import Testing
@testable import PodcastAnalyzer

// MARK: - PodcastEpisodeInfo.formattedDuration

// App-target types inherit @MainActor under Swift 6 global isolation.
@MainActor
struct FormattedDurationTests {

    private func ep(_ duration: Int?) -> PodcastEpisodeInfo {
        PodcastEpisodeInfo(title: "T", duration: duration)
    }

    @Test func duration_nil_returnsNil() {
        #expect(ep(nil).formattedDuration == nil)
    }

    @Test func duration_zero_returnsNil() {
        #expect(ep(0).formattedDuration == nil)
    }

    @Test func duration_secondsOnly() {
        #expect(ep(30).formattedDuration == "30s")
    }

    @Test func duration_minutesAndSeconds_whenMinutesLessThan10() {
        #expect(ep(65).formattedDuration == "1m 5s")    // 1m 5s
        #expect(ep(200).formattedDuration == "3m 20s")  // 3m 20s
    }

    @Test func duration_minutesOnly_whenNoSeconds() {
        #expect(ep(2880).formattedDuration == "48m")  // 48m exactly
        #expect(ep(600).formattedDuration == "10m")   // 10m, no seconds shown
    }

    @Test func duration_minutesOnly_whenMinutesAtLeast10() {
        // seconds > 0 but minutes >= 10 → shows only "Xm"
        #expect(ep(605).formattedDuration == "10m")   // 10m 5s, but minutes >= 10
    }

    @Test func duration_hoursAndMinutes() {
        #expect(ep(3900).formattedDuration == "1h 5m")   // 1h 5m
        #expect(ep(7200).formattedDuration == "2h 0m")   // 2h 0m (shows 0m)
    }
}

// MARK: - LibraryEpisode.progress / hasProgress

@MainActor
struct LibraryEpisodeProgressTests {

    private func makeEpisode(
        savedDuration: TimeInterval = 0,
        rssDuration: Int? = nil,
        position: TimeInterval,
        completed: Bool
    ) -> LibraryEpisode {
        let episodeInfo = PodcastEpisodeInfo(title: "T", duration: rssDuration)
        return LibraryEpisode(
            id: "test",
            podcastTitle: "P",
            imageURL: nil,
            language: "en",
            episodeInfo: episodeInfo,
            isStarred: false,
            isDownloaded: false,
            isCompleted: completed,
            lastPlaybackPosition: position,
            savedDuration: savedDuration
        )
    }

    // MARK: hasProgress

    @Test func hasProgress_trueWhenPositionNonZeroAndNotCompleted() {
        let ep = makeEpisode(position: 300, completed: false)
        #expect(ep.hasProgress)
    }

    @Test func hasProgress_falseWhenPositionIsZero() {
        let ep = makeEpisode(position: 0, completed: false)
        #expect(!ep.hasProgress)
    }

    @Test func hasProgress_falseWhenCompleted() {
        let ep = makeEpisode(position: 300, completed: true)
        #expect(!ep.hasProgress)
    }

    // MARK: progress — uses savedDuration first

    @Test func progress_midpoint_withSavedDuration() {
        let ep = makeEpisode(savedDuration: 600, position: 300, completed: false)
        #expect(ep.progress == 0.5)
    }

    @Test func progress_fallsBackToRssDuration() {
        let ep = makeEpisode(savedDuration: 0, rssDuration: 600, position: 300, completed: false)
        #expect(ep.progress == 0.5)
    }

    @Test func progress_capsAt1_whenPositionExceedsDuration() {
        let ep = makeEpisode(savedDuration: 600, position: 900, completed: false)
        #expect(ep.progress == 1.0)
    }

    @Test func progress_isZero_whenNoDuration() {
        let ep = makeEpisode(savedDuration: 0, rssDuration: nil, position: 300, completed: false)
        #expect(ep.progress == 0)
    }

    @Test func progress_isZero_whenRssDurationIsZero() {
        let ep = makeEpisode(savedDuration: 0, rssDuration: 0, position: 300, completed: false)
        #expect(ep.progress == 0)
    }
}

// MARK: - DownloadState Equatable

@MainActor
struct DownloadStateEquatableTests {

    @Test func notDownloaded_equalsItself() {
        #expect(DownloadState.notDownloaded == .notDownloaded)
    }

    @Test func finishing_equalsItself() {
        #expect(DownloadState.finishing == .finishing)
    }

    @Test func downloaded_equalsSamePath() {
        #expect(DownloadState.downloaded(localPath: "/a") == .downloaded(localPath: "/a"))
    }

    @Test func downloaded_notEqualDifferentPath() {
        #expect(DownloadState.downloaded(localPath: "/a") != .downloaded(localPath: "/b"))
    }

    @Test func downloading_equalsSameProgress() {
        #expect(DownloadState.downloading(progress: 0.5) == .downloading(progress: 0.5))
    }

    @Test func failed_equalsSameError() {
        #expect(DownloadState.failed(error: "oops") == .failed(error: "oops"))
    }

    @Test func differentCases_areNotEqual() {
        #expect(DownloadState.notDownloaded != .finishing)
        #expect(DownloadState.notDownloaded != .downloaded(localPath: "/a"))
    }
}

// MARK: - DownloadState Codable

@MainActor
struct DownloadStateCodableTests {

    @Test func codableRoundTrip() throws {
        let states: [DownloadState] = [
            .notDownloaded,
            .downloading(progress: 0.5),
            .finishing,
            .downloaded(localPath: "/foo/bar.mp3"),
            .failed(error: "network error"),
        ]
        for state in states {
            let data = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(DownloadState.self, from: data)
            #expect(decoded == state, "Round-trip failed for \(state)")
        }
    }
}
