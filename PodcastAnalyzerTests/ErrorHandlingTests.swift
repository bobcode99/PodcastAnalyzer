//
//  ErrorHandlingTests.swift
//  PodcastAnalyzerTests
//
//  Tests error handling: malformed RSS, download state recovery, disk space checks.
//

import XCTest

@testable import PodcastAnalyzer

@MainActor
final class ErrorHandlingTests: XCTestCase {

  // MARK: - RSS Error Isolation

  func testMalformedRSSReturnsErrorWithoutCrash() async {
    let service = PodcastRssService()

    do {
      _ = try await service.fetchPodcast(from: "https://httpbin.org/html")
      XCTFail("Should have thrown for non-RSS content")
    } catch {
      // Expected — malformed feed should throw, not crash
      // Any error type is acceptable as long as it doesn't crash
    }
  }

  func testEmptyURLReturnsError() async {
    let service = PodcastRssService()

    do {
      _ = try await service.fetchPodcast(from: "")
      XCTFail("Should have thrown for empty URL")
    } catch is PodcastServiceError {
      // Expected — empty string is an invalid URL
    } catch {
      // Other error types are acceptable too (URLError, etc.)
    }
  }

  // MARK: - Download State Recovery

  func testDownloadStateReturnsNotDownloadedForMissingFile() {
    let manager = DownloadManager.shared

    // Query state for an episode that has no download record
    let state = manager.getDownloadState(
      episodeTitle: "NonExistent Episode \(UUID().uuidString)",
      podcastTitle: "NonExistent Podcast"
    )
    XCTAssertEqual(state, .notDownloaded,
                   "Unknown episode should return .notDownloaded")
  }

  // MARK: - Download State Enum

  func testDownloadStateEquality() {
    XCTAssertEqual(DownloadState.notDownloaded, DownloadState.notDownloaded)
    XCTAssertEqual(
      DownloadState.downloaded(localPath: "/test"),
      DownloadState.downloaded(localPath: "/test"))
    XCTAssertNotEqual(
      DownloadState.downloaded(localPath: "/test1"),
      DownloadState.downloaded(localPath: "/test2"))
    XCTAssertEqual(
      DownloadState.failed(error: "test"),
      DownloadState.failed(error: "test"))
    XCTAssertNotEqual(
      DownloadState.notDownloaded,
      DownloadState.downloading(progress: 0))
  }
}
