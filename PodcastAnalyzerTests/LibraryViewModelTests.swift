//
//  LibraryViewModelTests.swift
//  PodcastAnalyzerTests
//
//  Tests for LibraryViewModel deduplication, dictionary safety, and data loading
//

import SwiftData
import XCTest

@testable import PodcastAnalyzer

@MainActor
final class LibraryViewModelTests: XCTestCase {

  // Track view models so we can clean them up
  private var activeViewModels: [LibraryViewModel] = []

  override func tearDown() async throws {
    // Stop timers and observers from all test view models
    await MainActor.run {
      for vm in activeViewModels {
        vm.cleanup()
      }
      activeViewModels.removeAll()
    }
    cleanupTempFiles()
  }

  // MARK: - Helpers

  /// Creates an in-memory ModelContainer for testing
  private func makeTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
      for: EpisodeDownloadModel.self, PodcastInfoModel.self,
      configurations: config
    )
  }

  /// Creates a LibraryViewModel and tracks it for cleanup
  private func makeViewModel(context: ModelContext) -> LibraryViewModel {
    let vm = LibraryViewModel(modelContext: context)
    activeViewModels.append(vm)
    return vm
  }

  /// Creates a test EpisodeDownloadModel
  private func makeEpisodeModel(
    episodeTitle: String,
    podcastTitle: String,
    audioURL: String = "https://example.com/audio.mp3",
    isStarred: Bool = false,
    localAudioPath: String? = nil,
    isCompleted: Bool = false,
    pubDate: Date? = nil
  ) -> EpisodeDownloadModel {
    EpisodeDownloadModel(
      episodeTitle: episodeTitle,
      podcastTitle: podcastTitle,
      audioURL: audioURL,
      localAudioPath: localAudioPath,
      isStarred: isStarred,
      imageURL: "https://example.com/image.jpg",
      pubDate: pubDate ?? Date()
    )
  }

  /// Wait until a condition is true, polling every interval, with a timeout.
  private func waitUntil(
    timeout: TimeInterval = 3.0,
    interval: TimeInterval = 0.05,
    _ condition: () -> Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
      if Date() > deadline {
        XCTFail("Timed out waiting for condition")
        return
      }
      try await Task.sleep(for: .milliseconds(Int(interval * 1000)))
    }
  }

  /// Creates a temporary audio file and returns its path.
  /// The sync function checks if files exist on disk, so tests need real files.
  private func createTempAudioFile(name: String) -> String {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("LibraryViewModelTests", isDirectory: true)
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let filePath = tempDir.appendingPathComponent(name)
    FileManager.default.createFile(atPath: filePath.path, contents: Data([0xFF, 0xFB, 0x90, 0x00]))
    return filePath.path
  }

  /// Remove temp directory used by tests
  private func cleanupTempFiles() {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("LibraryViewModelTests", isDirectory: true)
    try? FileManager.default.removeItem(at: tempDir)
  }

  // MARK: - Dictionary Safety Tests

  func testDictionaryWithDuplicateKeysDoesNotCrash() {
    // Simulate what happens when SwiftData returns duplicate IDs
    let delimiter = "\u{1F}"
    let duplicateId = "Global News Podcast\(delimiter)Afghanistan war veterans demand apology from US"

    let entries: [(String, String)] = [
      (duplicateId, "value1"),
      (duplicateId, "value2"),
      ("other_key", "value3"),
    ]

    // This must NOT crash - uses uniquingKeysWith instead of uniqueKeysWithValues
    let dict = Dictionary(entries, uniquingKeysWith: { _, latest in latest })

    XCTAssertEqual(dict.count, 2, "Should have 2 unique keys")
    XCTAssertEqual(dict[duplicateId], "value2", "Should keep the latest value")
    XCTAssertEqual(dict["other_key"], "value3")
  }

  func testDictionaryUniqueKeysWithValuesSafeAlternative() {
    // Prove the safe alternative works correctly with and without duplicates
    let noDupes = [("key1", "a"), ("key2", "b")]
    let dict1 = Dictionary(noDupes, uniquingKeysWith: { _, latest in latest })
    XCTAssertEqual(dict1.count, 2)

    let withDupes = [("key1", "a"), ("key1", "b"), ("key2", "c")]
    let dict2 = Dictionary(withDupes, uniquingKeysWith: { _, latest in latest })
    XCTAssertEqual(dict2.count, 2)
    XCTAssertEqual(dict2["key1"], "b", "Should keep the latest value for duplicate key")
    XCTAssertEqual(dict2["key2"], "c")
  }

  func testDuplicateKeysWithManyEntries() {
    // Stress test: many duplicates should not crash
    var entries: [(String, Int)] = []
    for i in 0..<100 {
      entries.append(("key_\(i % 10)", i))  // 10 unique keys, 10 duplicates each
    }
    let dict = Dictionary(entries, uniquingKeysWith: { _, latest in latest })
    XCTAssertEqual(dict.count, 10)
    // Last value for key_0 should be 90
    XCTAssertEqual(dict["key_0"], 90)
  }

  // MARK: - Deduplication in Loaded Data

  func testLoadSavedEpisodesDeduplicates() async throws {
    let container = try makeTestContainer()
    let context = ModelContext(container)

    // Insert two models with the same episode+podcast (simulating duplicate)
    context.insert(makeEpisodeModel(
      episodeTitle: "Episode 1", podcastTitle: "Podcast A",
      isStarred: true, pubDate: Date(timeIntervalSince1970: 1_000_000)))
    context.insert(makeEpisodeModel(
      episodeTitle: "Episode 1", podcastTitle: "Podcast A",
      isStarred: true, pubDate: Date(timeIntervalSince1970: 2_000_000)))
    context.insert(makeEpisodeModel(
      episodeTitle: "Episode 2", podcastTitle: "Podcast A",
      isStarred: true, pubDate: Date(timeIntervalSince1970: 3_000_000)))
    try context.save()

    let viewModel = makeViewModel(context: context)
    viewModel.setModelContext(context)

    try await waitUntil { !viewModel.savedEpisodes.isEmpty }

    // model1 and model2 have the same ID, so only one should appear
    let savedIds = viewModel.savedEpisodes.map { $0.id }
    let uniqueIds = Set(savedIds)
    XCTAssertEqual(
      savedIds.count, uniqueIds.count,
      "Saved episodes should have no duplicate IDs. Got: \(savedIds)")
  }

  func testLoadDownloadedEpisodesDeduplicates() async throws {
    let container = try makeTestContainer()
    let context = ModelContext(container)

    let path1 = createTempAudioFile(name: "audio1.mp3")
    let path2 = createTempAudioFile(name: "audio2.mp3")
    let path3 = createTempAudioFile(name: "audio3.mp3")

    context.insert(makeEpisodeModel(
      episodeTitle: "Episode 1", podcastTitle: "Podcast A",
      localAudioPath: path1,
      pubDate: Date(timeIntervalSince1970: 1_000_000)))
    context.insert(makeEpisodeModel(
      episodeTitle: "Episode 1", podcastTitle: "Podcast A",
      localAudioPath: path2,
      pubDate: Date(timeIntervalSince1970: 2_000_000)))
    context.insert(makeEpisodeModel(
      episodeTitle: "Episode 2", podcastTitle: "Podcast A",
      localAudioPath: path3,
      pubDate: Date(timeIntervalSince1970: 3_000_000)))
    try context.save()

    let viewModel = makeViewModel(context: context)
    viewModel.setModelContext(context)

    try await waitUntil { !viewModel.downloadedEpisodes.isEmpty }

    let downloadedIds = viewModel.downloadedEpisodes.map { $0.id }
    let uniqueIds = Set(downloadedIds)
    XCTAssertEqual(
      downloadedIds.count, uniqueIds.count,
      "Downloaded episodes should have no duplicate IDs. Got: \(downloadedIds)")
  }

  // MARK: - Episode Key Format

  func testEpisodeKeyUsesUnitSeparator() {
    let model = makeEpisodeModel(
      episodeTitle: "Afghanistan war veterans demand apology from US",
      podcastTitle: "Global News Podcast")
    let delimiter = "\u{1F}"
    let expectedId = "Global News Podcast\(delimiter)Afghanistan war veterans demand apology from US"
    XCTAssertEqual(model.id, expectedId, "Episode ID should use Unit Separator delimiter")
  }

  func testEpisodeKeyWithSpecialCharacters() {
    let model = makeEpisodeModel(
      episodeTitle: "What's Next? | Part 2: The \"Big\" Plan",
      podcastTitle: "Tech Talk: Daily")
    let delimiter = "\u{1F}"
    let expectedId = "Tech Talk: Daily\(delimiter)What's Next? | Part 2: The \"Big\" Plan"
    XCTAssertEqual(model.id, expectedId)
  }

  // MARK: - Model Counts

  func testSavedCountMatchesStarredEpisodes() async throws {
    let container = try makeTestContainer()
    let context = ModelContext(container)

    context.insert(makeEpisodeModel(episodeTitle: "Ep1", podcastTitle: "P1", isStarred: true))
    context.insert(makeEpisodeModel(episodeTitle: "Ep2", podcastTitle: "P1", isStarred: true))
    context.insert(makeEpisodeModel(episodeTitle: "Ep3", podcastTitle: "P1", isStarred: true))
    context.insert(makeEpisodeModel(episodeTitle: "Ep4", podcastTitle: "P1", isStarred: false))
    context.insert(makeEpisodeModel(episodeTitle: "Ep5", podcastTitle: "P1", isStarred: false))
    try context.save()

    let viewModel = makeViewModel(context: context)
    viewModel.setModelContext(context)

    try await waitUntil { viewModel.savedEpisodes.count == 3 }

    XCTAssertEqual(viewModel.savedEpisodes.count, 3, "Should have 3 saved (starred) episodes")
  }

  func testDownloadedCountMatchesEpisodesWithLocalPath() async throws {
    let container = try makeTestContainer()
    let context = ModelContext(container)

    let path1 = createTempAudioFile(name: "audio1.mp3")
    let path2 = createTempAudioFile(name: "audio2.mp3")

    context.insert(makeEpisodeModel(
      episodeTitle: "Ep1", podcastTitle: "P1", localAudioPath: path1))
    context.insert(makeEpisodeModel(
      episodeTitle: "Ep2", podcastTitle: "P1", localAudioPath: path2))
    context.insert(makeEpisodeModel(
      episodeTitle: "Ep3", podcastTitle: "P1", localAudioPath: nil))
    context.insert(makeEpisodeModel(
      episodeTitle: "Ep4", podcastTitle: "P1", localAudioPath: ""))
    try context.save()

    let viewModel = makeViewModel(context: context)
    viewModel.setModelContext(context)

    try await waitUntil { viewModel.downloadedEpisodes.count == 2 }

    XCTAssertEqual(
      viewModel.downloadedEpisodes.count, 2,
      "Should have 2 downloaded episodes (non-nil, non-empty localAudioPath)")
  }

  // MARK: - Search Filtering

  func testSavedSearchFiltering() async throws {
    let container = try makeTestContainer()
    let context = ModelContext(container)

    context.insert(makeEpisodeModel(
      episodeTitle: "Morning Tech News", podcastTitle: "Daily Tech", isStarred: true))
    context.insert(makeEpisodeModel(
      episodeTitle: "Evening Sports", podcastTitle: "Sports Daily", isStarred: true))
    context.insert(makeEpisodeModel(
      episodeTitle: "Weekly Science", podcastTitle: "Science Hour", isStarred: true))
    try context.save()

    let viewModel = makeViewModel(context: context)
    viewModel.setModelContext(context)

    try await waitUntil { viewModel.savedEpisodes.count == 3 }

    // No search - all results
    XCTAssertEqual(viewModel.filteredSavedEpisodes.count, 3)

    // Search by episode title
    viewModel.savedSearchText = "tech"
    XCTAssertEqual(viewModel.filteredSavedEpisodes.count, 1)
    XCTAssertEqual(viewModel.filteredSavedEpisodes.first?.episodeInfo.title, "Morning Tech News")

    // Search by podcast title
    viewModel.savedSearchText = "science"
    XCTAssertEqual(viewModel.filteredSavedEpisodes.count, 1)

    // No match
    viewModel.savedSearchText = "xyz"
    XCTAssertEqual(viewModel.filteredSavedEpisodes.count, 0)

    // Clear search
    viewModel.savedSearchText = ""
    XCTAssertEqual(viewModel.filteredSavedEpisodes.count, 3)
  }

  func testDownloadedSearchFiltering() async throws {
    let container = try makeTestContainer()
    let context = ModelContext(container)

    let pathA = createTempAudioFile(name: "alpha.mp3")
    let pathB = createTempAudioFile(name: "beta.mp3")

    context.insert(makeEpisodeModel(
      episodeTitle: "Episode Alpha", podcastTitle: "Podcast One",
      localAudioPath: pathA))
    context.insert(makeEpisodeModel(
      episodeTitle: "Episode Beta", podcastTitle: "Podcast Two",
      localAudioPath: pathB))
    try context.save()

    let viewModel = makeViewModel(context: context)
    viewModel.setModelContext(context)

    try await waitUntil { viewModel.downloadedEpisodes.count == 2 }

    viewModel.downloadedSearchText = "alpha"
    XCTAssertEqual(viewModel.filteredDownloadedEpisodes.count, 1)

    viewModel.downloadedSearchText = "podcast"
    XCTAssertEqual(viewModel.filteredDownloadedEpisodes.count, 2)
  }

  // MARK: - Observer Lifecycle

  func testCleanupAndResetup() async throws {
    let container = try makeTestContainer()
    let context = ModelContext(container)

    context.insert(makeEpisodeModel(
      episodeTitle: "Ep1", podcastTitle: "P1", isStarred: true))
    try context.save()

    let viewModel = makeViewModel(context: context)
    viewModel.setModelContext(context)

    try await waitUntil { viewModel.savedEpisodes.count == 1 }

    // Cleanup removes observers (simulates onDisappear)
    viewModel.cleanup()

    // setModelContext re-adds observers (simulates onAppear)
    viewModel.setModelContext(context)

    // Should not crash and data should still be accessible
    XCTAssertEqual(viewModel.savedEpisodes.count, 1, "Data should persist after cleanup + re-setup")
  }

  // MARK: - LibraryEpisode Model

  func testLibraryEpisodeProgress() {
    let episode = LibraryEpisode(
      id: "test", podcastTitle: "Test", imageURL: nil, language: "en",
      episodeInfo: PodcastEpisodeInfo(title: "Ep", duration: 600),
      isStarred: false, isDownloaded: false, isCompleted: false,
      lastPlaybackPosition: 300)

    XCTAssertEqual(episode.progress, 0.5, accuracy: 0.01, "50% progress")
    XCTAssertTrue(episode.hasProgress, "Should have progress when position > 0 and not completed")
  }

  func testLibraryEpisodeNoProgressWhenCompleted() {
    let episode = LibraryEpisode(
      id: "test", podcastTitle: "Test", imageURL: nil, language: "en",
      episodeInfo: PodcastEpisodeInfo(title: "Ep", duration: 600),
      isStarred: false, isDownloaded: false, isCompleted: true,
      lastPlaybackPosition: 300)

    XCTAssertFalse(episode.hasProgress, "Completed episodes should not show progress")
  }

  func testLibraryEpisodeProgressWithNoDuration() {
    let episode = LibraryEpisode(
      id: "test", podcastTitle: "Test", imageURL: nil, language: "en",
      episodeInfo: PodcastEpisodeInfo(title: "Ep", duration: nil),
      isStarred: false, isDownloaded: false, isCompleted: false,
      lastPlaybackPosition: 300)

    XCTAssertEqual(episode.progress, 0, "Progress should be 0 when duration is nil")
  }

  func testLibraryEpisodeProgressCapsAt1() {
    let episode = LibraryEpisode(
      id: "test", podcastTitle: "Test", imageURL: nil, language: "en",
      episodeInfo: PodcastEpisodeInfo(title: "Ep", duration: 600),
      isStarred: false, isDownloaded: false, isCompleted: false,
      lastPlaybackPosition: 900)  // Position beyond duration

    XCTAssertEqual(episode.progress, 1.0, accuracy: 0.01, "Progress should cap at 1.0")
  }
}
