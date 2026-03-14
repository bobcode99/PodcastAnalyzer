//
//  EpisodeKeyTests.swift
//  PodcastAnalyzerTests
//
//  Tests for EpisodeKeyUtils.makeKey and parseKey.
//  Pure function tests — no singletons, no I/O, parallel-safe.
//

import Testing
@testable import PodcastAnalyzer

// EpisodeKeyUtils inherits @MainActor from the Swift 6 app target default.
@MainActor
struct EpisodeKeyTests {

    // MARK: - makeKey

    @Test func makeKey_usesUnitSeparatorDelimiter() {
        let key = EpisodeKeyUtils.makeKey(podcastTitle: "My Show", episodeTitle: "Ep 1")
        #expect(key == "My Show\u{1F}Ep 1")
    }

    @Test func makeKey_emptyTitles() {
        let key = EpisodeKeyUtils.makeKey(podcastTitle: "", episodeTitle: "")
        #expect(key == "\u{1F}")
    }

    // MARK: - parseKey (new format)

    @Test func parseKey_newFormat_roundTrips() throws {
        let key = EpisodeKeyUtils.makeKey(podcastTitle: "Show", episodeTitle: "Title")
        let parsed = try #require(EpisodeKeyUtils.parseKey(key))
        #expect(parsed.podcastTitle == "Show")
        #expect(parsed.episodeTitle == "Title")
    }

    @Test func parseKey_newFormat_titlesWithSpacesAndSpecialChars() throws {
        let key = EpisodeKeyUtils.makeKey(podcastTitle: "My Podcast: Season 2", episodeTitle: "Ep #1 — Intro")
        let parsed = try #require(EpisodeKeyUtils.parseKey(key))
        #expect(parsed.podcastTitle == "My Podcast: Season 2")
        #expect(parsed.episodeTitle == "Ep #1 — Intro")
    }

    // MARK: - parseKey (legacy pipe format)

    @Test func parseKey_legacyPipeFormat_returnsComponents() throws {
        let parsed = try #require(EpisodeKeyUtils.parseKey("My Show|Ep 1"))
        #expect(parsed.podcastTitle == "My Show")
        #expect(parsed.episodeTitle == "Ep 1")
    }

    @Test func parseKey_legacyPipeFormat_usesLastPipe() throws {
        // Episode title itself contains a pipe — lastIndex(of:) picks the rightmost
        let parsed = try #require(EpisodeKeyUtils.parseKey("Show|Title|With|Pipes"))
        #expect(parsed.podcastTitle == "Show|Title|With")
        #expect(parsed.episodeTitle == "Pipes")
    }

    // MARK: - parseKey (no delimiter)

    @Test func parseKey_noDelimiter_returnsNil() {
        #expect(EpisodeKeyUtils.parseKey("NoDelimiterAtAll") == nil)
    }

    @Test func parseKey_emptyString_returnsNil() {
        #expect(EpisodeKeyUtils.parseKey("") == nil)
    }
}
