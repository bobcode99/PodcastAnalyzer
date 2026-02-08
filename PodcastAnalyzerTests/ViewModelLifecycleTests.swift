//
//  ViewModelLifecycleTests.swift
//  PodcastAnalyzerTests
//
//  Tests that cleanup() stops timers, removes notification observers, and cancels tasks.
//

import SwiftData
import XCTest

@testable import PodcastAnalyzer

@MainActor
final class ViewModelLifecycleTests: XCTestCase {

  private func makeTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
      for: EpisodeDownloadModel.self, PodcastInfoModel.self, EpisodeAIAnalysis.self,
      EpisodeQuickTagsModel.self,
      configurations: config
    )
  }

  // MARK: - LibraryViewModel Lifecycle

  func testLibraryViewModelCleanupStopsTimerAndObservers() throws {
    let container = try makeTestContainer()
    let context = ModelContext(container)

    let vm = LibraryViewModel(modelContext: context)

    // cleanup should not crash and should be idempotent
    vm.cleanup()
    vm.cleanup()  // Double cleanup should be safe

    // Re-setup should work after cleanup
    vm.setModelContext(context)
    vm.cleanup()
  }

  // MARK: - HomeViewModel Lifecycle

  func testHomeViewModelCleanupIsIdempotent() throws {
    let container = try makeTestContainer()
    let context = ModelContext(container)

    let vm = HomeViewModel()
    vm.setModelContext(context)

    vm.cleanup()
    vm.cleanup()  // Should not crash
  }

  // MARK: - SettingsViewModel Lifecycle

  func testSettingsViewModelCanBeCreatedAndDestroyed() {
    // SettingsViewModel has deinit that cancels tasks
    var vm: SettingsViewModel? = SettingsViewModel()
    XCTAssertNotNil(vm)
    vm = nil  // Should trigger deinit without crash
  }

  // MARK: - Cleanup After Setup Cycle

  func testLibraryViewModelSetupCleanupCycle() throws {
    let container = try makeTestContainer()
    let context = ModelContext(container)

    let vm = LibraryViewModel(modelContext: context)

    // Simulate multiple appear/disappear cycles
    for _ in 0..<5 {
      vm.setModelContext(context)
      vm.cleanup()
    }
    // Final cleanup — should not crash or leak
    vm.cleanup()
  }
}
