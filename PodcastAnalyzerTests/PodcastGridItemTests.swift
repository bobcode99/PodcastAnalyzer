//
//  PodcastGridItemTests.swift
//  PodcastAnalyzerTests
//
//  Guards PodcastGridItem.latestEpisodeDate against regression to model.lastUpdated.
//  The Library grid must display "X days ago" relative to the most recent
//  episode's pubDate — NOT the RSS feed refresh timestamp.
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
