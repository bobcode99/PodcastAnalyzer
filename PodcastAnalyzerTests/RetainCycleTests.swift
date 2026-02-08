//
//  RetainCycleTests.swift
//  PodcastAnalyzerTests
//
//  Verifies that ViewModels can be deallocated after cleanup (no retain cycles).
//  Note: @Observable @MainActor classes may have deferred deallocation due to runtime
//  internals, so we allow a brief polling window for deallocation.
//

import SwiftData
import XCTest

@testable import PodcastAnalyzer

@MainActor
final class RetainCycleTests: XCTestCase {

  private func makeTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
      for: EpisodeDownloadModel.self, PodcastInfoModel.self, EpisodeAIAnalysis.self,
      EpisodeQuickTagsModel.self,
      configurations: config
    )
  }

  /// Waits up to `timeout` seconds for a weak reference to become nil.
  private func waitForDeallocation<T: AnyObject>(
    _ weakRef: () -> T?,
    timeout: TimeInterval = 2.0
  ) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while weakRef() != nil {
      if Date() > deadline { return false }
      // Yield to allow ARC to run
      try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
    }
    return true
  }

  // MARK: - SettingsViewModel (no async resources — should deallocate immediately)

  func testSettingsViewModelDeallocates() {
    var vm: SettingsViewModel? = SettingsViewModel()
    weak var weakVM = vm

    vm = nil

    XCTAssertNil(weakVM, "SettingsViewModel should be deallocated after nil assignment")
  }

  // MARK: - LibraryViewModel

  func testLibraryViewModelDeallocates() async throws {
    let container = try makeTestContainer()
    let context = ModelContext(container)

    var vm: LibraryViewModel? = LibraryViewModel(modelContext: context)
    weak var weakVM = vm

    vm?.cleanup()
    vm = nil

    let deallocated = await waitForDeallocation { weakVM }
    XCTAssertTrue(deallocated, "LibraryViewModel should be deallocated after cleanup and nil assignment")
  }

  // MARK: - HomeViewModel

  func testHomeViewModelDeallocates() async throws {
    let container = try makeTestContainer()
    let context = ModelContext(container)

    var vm: HomeViewModel? = HomeViewModel()
    weak var weakVM = vm

    vm?.setModelContext(context)
    vm?.cleanup()
    vm = nil

    let deallocated = await waitForDeallocation { weakVM }
    XCTAssertTrue(deallocated, "HomeViewModel should be deallocated after cleanup and nil assignment")
  }

  // MARK: - PodcastSearchViewModel

  func testPodcastSearchViewModelDeallocates() async {
    var vm: PodcastSearchViewModel? = PodcastSearchViewModel()
    weak var weakVM = vm

    vm?.cleanup()
    vm = nil

    let deallocated = await waitForDeallocation { weakVM }
    XCTAssertTrue(deallocated, "PodcastSearchViewModel should be deallocated after cleanup and nil assignment")
  }
}
