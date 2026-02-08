//
//  StressTestSuite.swift
//  PodcastAnalyzerUITests
//
//  UI stress tests: rapidly cycle tabs, open/close views, trigger play/pause.
//  Verifies app stability under repeated interactions (SC-004).
//

import XCTest

final class StressTestSuite: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  // MARK: - Tab Cycling Stress Test

  @MainActor
  func testRapidTabCyclingDoesNotCrash() throws {
    let app = XCUIApplication()
    app.launch()

    // Wait for app to settle
    sleep(2)

    let tabBar = app.tabBars.firstMatch

    // Cycle through tabs rapidly
    for _ in 0..<50 {
      // Tap each tab in sequence
      if tabBar.buttons["Home"].exists {
        tabBar.buttons["Home"].tap()
      }
      if tabBar.buttons["Library"].exists {
        tabBar.buttons["Library"].tap()
      }
      if tabBar.buttons["Settings"].exists {
        tabBar.buttons["Settings"].tap()
      }
    }

    // App should still be running
    XCTAssertTrue(app.state == .runningForeground, "App should still be running after rapid tab cycling")
  }

  // MARK: - Play/Pause Stress Test

  @MainActor
  func testRapidPlayPauseDoesNotCrash() throws {
    let app = XCUIApplication()
    app.launch()

    // Wait for app to settle
    sleep(2)

    // Find play/pause button in mini player
    let playButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'play' OR label CONTAINS 'pause'")).firstMatch

    if playButton.exists {
      for _ in 0..<20 {
        playButton.tap()
        usleep(100_000)  // 100ms between taps
      }
    }

    // App should still be running
    XCTAssertTrue(app.state == .runningForeground, "App should still be running after rapid play/pause")
  }

  // MARK: - Memory Metrics

  @MainActor
  func testTabCyclingMemoryMetrics() throws {
    let app = XCUIApplication()

    measure(metrics: [XCTMemoryMetric(application: app)]) {
      app.launch()

      sleep(1)

      let tabBar = app.tabBars.firstMatch

      for _ in 0..<10 {
        if tabBar.buttons["Home"].exists { tabBar.buttons["Home"].tap() }
        if tabBar.buttons["Library"].exists { tabBar.buttons["Library"].tap() }
        if tabBar.buttons["Settings"].exists { tabBar.buttons["Settings"].tap() }
      }

      sleep(1)
    }
  }
}
