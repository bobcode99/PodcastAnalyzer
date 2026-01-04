//
//  EpisodeStatusIconsCompact.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2026/1/4.
//


import Combine
import Foundation
import SwiftData
import SwiftUI

/// Compact status icons for overlays on artwork
struct EpisodeStatusIconsCompact: View {
  let isStarred: Bool
  let isDownloaded: Bool
  let hasTranscript: Bool
  let hasAIAnalysis: Bool

  init(
    isStarred: Bool = false,
    isDownloaded: Bool = false,
    hasTranscript: Bool = false,
    hasAIAnalysis: Bool = false
  ) {
    self.isStarred = isStarred
    self.isDownloaded = isDownloaded
    self.hasTranscript = hasTranscript
    self.hasAIAnalysis = hasAIAnalysis
  }

  private var hasAnyStatus: Bool {
    isStarred || isDownloaded || hasTranscript || hasAIAnalysis
  }

  var body: some View {
    if hasAnyStatus {
      HStack(spacing: 3) {
        if isStarred {
          statusIcon("star.fill", color: .yellow)
        }
        if isDownloaded {
          statusIcon("arrow.down.circle.fill", color: .green)
        }
        if hasTranscript {
          statusIcon("captions.bubble.fill", color: .purple)
        }
        if hasAIAnalysis {
          statusIcon("sparkles", color: .orange)
        }
      }
      .padding(4)
      .background(.ultraThinMaterial)
      .cornerRadius(6)
      .padding(4)
    }
  }

  private func statusIcon(_ name: String, color: Color) -> some View {
    Image(systemName: name)
      .font(.system(size: 9, weight: .bold))
      .foregroundColor(color)
  }
}