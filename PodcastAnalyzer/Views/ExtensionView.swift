import Foundation
//
//  ExtensionView.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/12/17.
//
import SwiftUI

extension View {
  @ViewBuilder
  func iosNavigationBarTitleDisplayModeInline() -> some View {
    #if os(iOS)
      self.navigationBarTitleDisplayMode(.inline)
    #else
      self  // Do nothing on macOS
    #endif
  }

  func disableAutocapitalization() -> some View {
    #if os(iOS)
      return self.textInputAutocapitalization(.never)
    #else
      return self
    #endif
  }
}
