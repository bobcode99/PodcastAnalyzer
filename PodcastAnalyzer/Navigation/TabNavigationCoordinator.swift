//
//  TabNavigationCoordinator.swift
//  PodcastAnalyzer
//
//  Centralized navigation coordinator that manages per-tab routers
//  and tracks which tab is currently visible.
//

import SwiftUI

enum TabIdentifier: Int {
  case home
  case library
  case settings
  case search
}

@Observable
final class TabNavigationCoordinator {
  var homeRouter = TabRouter()
  var libraryRouter = TabRouter()
  var settingsRouter = TabRouter()
  var searchRouter = TabRouter()

  var visibleTab: TabIdentifier = .home

  var activeRouter: TabRouter {
    router(for: visibleTab)
  }

  func router(for tab: TabIdentifier) -> TabRouter {
    switch tab {
    case .home: homeRouter
    case .library: libraryRouter
    case .settings: settingsRouter
    case .search: searchRouter
    }
  }
}

// MARK: - Environment Key

private struct TabNavigationCoordinatorKey: EnvironmentKey {
  static let defaultValue: TabNavigationCoordinator? = nil
}

extension EnvironmentValues {
  var tabNavigationCoordinator: TabNavigationCoordinator? {
    get { self[TabNavigationCoordinatorKey.self] }
    set { self[TabNavigationCoordinatorKey.self] = newValue }
  }
}
