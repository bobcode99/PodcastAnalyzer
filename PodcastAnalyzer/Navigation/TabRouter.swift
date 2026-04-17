//
//  TabRouter.swift
//  PodcastAnalyzer
//
//  Per-tab navigation router that owns a NavigationPath.
//

import SwiftUI

@Observable
final class TabRouter {
  var path = NavigationPath()

  func push<V: Hashable>(_ value: V) {
    path.append(value)
  }

  func pop() {
    guard !path.isEmpty else { return }
    path.removeLast()
  }

  func popToRoot() {
    path = NavigationPath()
  }
}
