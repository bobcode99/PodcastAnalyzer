//
//  PodcastGridItemTests.swift
//  PodcastAnalyzerTests
//
//  Guards the full display pipeline for the Library grid "X days ago" label:
//    1. PodcastGridItem.latestEpisodeDate — picks max episode pubDate, ignores model.lastUpdated
//    2. PodcastGridCell display string — nil when no pubDate, non-empty otherwise
//    3. Formatters.formatRelativeDate — produces non-empty output for any valid date
//
//  The display label must reflect the most recent episode's pubDate,
//  NOT the RSS feed refresh timestamp stored in model.lastUpdated.
//

import Foundation
import SwiftData
import Testing
@testable import PodcastAnalyzer

// MARK: - Helpers

@MainActor
private func makeEpisode(title: String = "Ep", pubDate: Date?) -> PodcastEpisodeInfo {
    PodcastEpisodeInfo(
        title: title,
        pubDate: pubDate,
        audioURL: "https://example.com/\(title).mp3"
    )
}

/// Build a PodcastInfoModel with the given episodes and a `lastUpdated` that is
/// deliberately *later* than every episode's pubDate — so any test that
/// accidentally reads `model.lastUpdated` will fail.
@MainActor
private func makeModel(
    episodes: [PodcastEpisodeInfo],
    lastUpdated: Date = Date()
) throws -> PodcastInfoModel {
    let schema = Schema([PodcastInfoModel.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: config)
    let context = ModelContext(container)

    let info = PodcastInfo(
        title: "Test Podcast",
        description: nil,
        episodes: episodes,
        rssUrl: "https://example.com/feed.rss",
        imageURL: "https://example.com/art.jpg",
        language: "en"
    )
    let model = PodcastInfoModel(podcastInfo: info, lastUpdated: lastUpdated)
    context.insert(model)
    return model
}

// MARK: - Tests

@MainActor
struct PodcastGridItemLatestEpisodeDateTests {

    /// Must pick the MAX pubDate across episodes, regardless of array order.
    @Test func picksMaxPubDate_whenEpisodesInReverseChronoOrder() throws {
        let newest = Date(timeIntervalSince1970: 1_700_000_000)
        let middle = Date(timeIntervalSince1970: 1_600_000_000)
        let oldest = Date(timeIntervalSince1970: 1_500_000_000)

        let model = try makeModel(episodes: [
            makeEpisode(title: "newest", pubDate: newest),
            makeEpisode(title: "middle", pubDate: middle),
            makeEpisode(title: "oldest", pubDate: oldest)
        ])

        let item = PodcastGridItem(from: model)
        #expect(item.latestEpisodeDate == newest)
    }

    @Test func picksMaxPubDate_whenEpisodesInChronoOrder() throws {
        let newest = Date(timeIntervalSince1970: 1_700_000_000)
        let middle = Date(timeIntervalSince1970: 1_600_000_000)
        let oldest = Date(timeIntervalSince1970: 1_500_000_000)

        let model = try makeModel(episodes: [
            makeEpisode(title: "oldest", pubDate: oldest),
            makeEpisode(title: "middle", pubDate: middle),
            makeEpisode(title: "newest", pubDate: newest)
        ])

        let item = PodcastGridItem(from: model)
        #expect(item.latestEpisodeDate == newest)
    }

    @Test func picksMaxPubDate_whenEpisodesShuffled() throws {
        let newest = Date(timeIntervalSince1970: 1_700_000_000)
        let middle = Date(timeIntervalSince1970: 1_600_000_000)
        let oldest = Date(timeIntervalSince1970: 1_500_000_000)

        let model = try makeModel(episodes: [
            makeEpisode(title: "middle", pubDate: middle),
            makeEpisode(title: "newest", pubDate: newest),
            makeEpisode(title: "oldest", pubDate: oldest)
        ])

        let item = PodcastGridItem(from: model)
        #expect(item.latestEpisodeDate == newest)
    }

    /// Regression guard: the value must come from episode pubDates, never from
    /// PodcastInfoModel.lastUpdated (the RSS refresh timestamp).
    @Test func ignoresModelLastUpdated() throws {
        let episodeDate = Date(timeIntervalSince1970: 1_600_000_000)
        // Refresh timestamp is intentionally 1 year newer than the newest episode.
        let refreshTimestamp = Date(timeIntervalSince1970: 1_700_000_000)

        let model = try makeModel(
            episodes: [makeEpisode(title: "only", pubDate: episodeDate)],
            lastUpdated: refreshTimestamp
        )

        let item = PodcastGridItem(from: model)
        #expect(item.latestEpisodeDate == episodeDate)
        #expect(item.latestEpisodeDate != refreshTimestamp)
    }

    /// Episodes missing pubDate must be skipped, and the newest of the
    /// remaining pubDates must be returned.
    @Test func skipsEpisodesWithNilPubDate() throws {
        let dated = Date(timeIntervalSince1970: 1_600_000_000)

        let model = try makeModel(episodes: [
            makeEpisode(title: "no-date-1", pubDate: nil),
            makeEpisode(title: "dated", pubDate: dated),
            makeEpisode(title: "no-date-2", pubDate: nil)
        ])

        let item = PodcastGridItem(from: model)
        #expect(item.latestEpisodeDate == dated)
    }

    @Test func returnsNil_whenNoEpisodesHavePubDate() throws {
        let model = try makeModel(episodes: [
            makeEpisode(title: "a", pubDate: nil),
            makeEpisode(title: "b", pubDate: nil)
        ])

        let item = PodcastGridItem(from: model)
        #expect(item.latestEpisodeDate == nil)
    }

    @Test func returnsNil_whenEpisodesEmpty() throws {
        let model = try makeModel(episodes: [])

        let item = PodcastGridItem(from: model)
        #expect(item.latestEpisodeDate == nil)
    }

    /// Sanity check: episodeCount still reflects the total, unaffected by nil pubDates.
    @Test func episodeCount_includesEpisodesWithNilPubDate() throws {
        let model = try makeModel(episodes: [
            makeEpisode(title: "a", pubDate: nil),
            makeEpisode(title: "b", pubDate: Date(timeIntervalSince1970: 1_600_000_000)),
            makeEpisode(title: "c", pubDate: nil)
        ])

        let item = PodcastGridItem(from: model)
        #expect(item.episodeCount == 3)
    }
}

// MARK: - PodcastGridCell display string tests
//
// These mirror the logic inside PodcastGridCell.latestEpisodeDate (private):
//
//   guard let date = item.latestEpisodeDate else { return nil }
//   return Formatters.formatRelativeDate(date)
//
// Since the computed property is private to the View, we replicate the same
// one-liner here so we can assert both the nil-guard behaviour and the
// content of the formatted string.

@MainActor
struct PodcastGridCellDisplayStringTests {

    // Mirror of PodcastGridCell.latestEpisodeDate, used as the test subject.
    private func displayString(for item: PodcastGridItem,
                               relativeTo ref: Date = Date()) -> String? {
        guard let date = item.latestEpisodeDate else { return nil }
        return Formatters.formatRelativeDate(date, relativeTo: ref)
    }

    // MARK: nil-guard

    @Test func displayString_isNil_whenEpisodesEmpty() throws {
        let model = try makeModel(episodes: [])
        let item = PodcastGridItem(from: model)
        #expect(displayString(for: item) == nil)
    }

    @Test func displayString_isNil_whenNoEpisodeHasPubDate() throws {
        let model = try makeModel(episodes: [
            makeEpisode(title: "a", pubDate: nil),
            makeEpisode(title: "b", pubDate: nil)
        ])
        let item = PodcastGridItem(from: model)
        #expect(displayString(for: item) == nil)
    }

    // MARK: non-nil / non-empty

    @Test func displayString_isNonEmpty_forRecentEpisode() throws {
        let ref = Date(timeIntervalSince1970: 1_700_200_000)
        let pubDate = Date(timeIntervalSince1970: 1_700_113_600) // ~1 day before ref
        let model = try makeModel(episodes: [makeEpisode(title: "ep", pubDate: pubDate)])
        let item = PodcastGridItem(from: model)
        let result = displayString(for: item, relativeTo: ref)
        #expect(result != nil)
        #expect(result?.isEmpty == false)
    }

    @Test func displayString_isNonEmpty_forOldEpisode() throws {
        let ref = Date(timeIntervalSince1970: 1_700_200_000)
        let pubDate = Date(timeIntervalSince1970: 1_668_664_000) // ~1 year before ref
        let model = try makeModel(episodes: [makeEpisode(title: "old", pubDate: pubDate)])
        let item = PodcastGridItem(from: model)
        let result = displayString(for: item, relativeTo: ref)
        #expect(result != nil)
        #expect(result?.isEmpty == false)
    }

    // MARK: end-to-end regression: string reflects episode pubDate, not model.lastUpdated

    /// The display string must be derived from the episode pubDate.
    /// If it accidentally used model.lastUpdated the two strings would differ.
    @Test func displayString_reflectsEpisodePubDate_notModelLastUpdated() throws {
        let ref           = Date(timeIntervalSince1970: 1_700_200_000)
        let episodeDate   = Date(timeIntervalSince1970: 1_600_000_000) // ~3 yrs before ref
        let refreshDate   = Date(timeIntervalSince1970: 1_699_500_000) // ~8 days before ref

        let model = try makeModel(
            episodes: [makeEpisode(title: "ep", pubDate: episodeDate)],
            lastUpdated: refreshDate
        )
        let item = PodcastGridItem(from: model)

        let expectedFromEpisode = Formatters.formatRelativeDate(episodeDate, relativeTo: ref)
        let wouldBeFromRefresh  = Formatters.formatRelativeDate(refreshDate, relativeTo: ref)

        let actual = displayString(for: item, relativeTo: ref)
        #expect(actual == expectedFromEpisode)
        #expect(actual != wouldBeFromRefresh)
    }

    /// Among multiple episodes, the display string is derived from the NEWEST pubDate.
    @Test func displayString_usesNewestEpisodePubDate() throws {
        let ref    = Date(timeIntervalSince1970: 1_700_200_000)
        let newest = Date(timeIntervalSince1970: 1_700_100_000)
        let older  = Date(timeIntervalSince1970: 1_699_000_000)

        let model = try makeModel(episodes: [
            makeEpisode(title: "older",  pubDate: older),
            makeEpisode(title: "newest", pubDate: newest)
        ])
        let item = PodcastGridItem(from: model)

        let expected = Formatters.formatRelativeDate(newest, relativeTo: ref)
        let actual   = displayString(for: item, relativeTo: ref)
        #expect(actual == expected)
    }
}

// MARK: - Formatters.formatRelativeDate unit tests
//
// These verify the formatter itself against a fixed reference date so results
// are deterministic regardless of when the test suite runs.

struct FormattersRelativeDateTests {

    // Fixed anchor to make all assertions deterministic.
    private let ref = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func returns_nonEmpty_forSameInstant() {
        #expect(!Formatters.formatRelativeDate(ref, relativeTo: ref).isEmpty)
    }

    @Test func returns_nonEmpty_for1DayAgo() {
        let oneDayAgo = Date(timeIntervalSince1970: 1_699_913_600) // ref − 86 400 s
        #expect(!Formatters.formatRelativeDate(oneDayAgo, relativeTo: ref).isEmpty)
    }

    @Test func returns_nonEmpty_for7DaysAgo() {
        let sevenDaysAgo = Date(timeIntervalSince1970: 1_699_395_200) // ref − 7 × 86 400 s
        #expect(!Formatters.formatRelativeDate(sevenDaysAgo, relativeTo: ref).isEmpty)
    }

    @Test func returns_nonEmpty_for1YearAgo() {
        let oneYearAgo = Date(timeIntervalSince1970: 1_668_464_000) // ref − ~365 days
        #expect(!Formatters.formatRelativeDate(oneYearAgo, relativeTo: ref).isEmpty)
    }

    /// Older dates must produce a different string than more recent ones —
    /// verifies the formatter distinguishes granularity rather than collapsing everything.
    @Test func olderDate_producesDifferentString_thanNewerDate() {
        let oneDayAgo  = Date(timeIntervalSince1970: 1_699_913_600)
        let oneYearAgo = Date(timeIntervalSince1970: 1_668_464_000)
        let dayStr  = Formatters.formatRelativeDate(oneDayAgo,  relativeTo: ref)
        let yearStr = Formatters.formatRelativeDate(oneYearAgo, relativeTo: ref)
        #expect(dayStr != yearStr)
    }
}
