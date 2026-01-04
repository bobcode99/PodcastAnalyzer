//
//  EpisodeStatusIcons.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2026/1/4.
//


import Combine
import Foundation
import SwiftData
import SwiftUI

/// Reusable view for displaying episode status icons
struct EpisodeStatusIcons: View {
  let isStarred: Bool
  let isDownloaded: Bool
  let hasTranscript: Bool
  let hasAIAnalysis: Bool
  let isCompleted: Bool
  let showCompleted: Bool

  init(
    isStarred: Bool = false,
    isDownloaded: Bool = false,
    hasTranscript: Bool = false,
    hasAIAnalysis: Bool = false,
    isCompleted: Bool = false,
    showCompleted: Bool = true
  ) {
    self.isStarred = isStarred
    self.isDownloaded = isDownloaded
    self.hasTranscript = hasTranscript
    self.hasAIAnalysis = hasAIAnalysis
    self.isCompleted = isCompleted
    self.showCompleted = showCompleted
  }

  var body: some View {
    HStack(spacing: 4) {
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

      if showCompleted && isCompleted {
        statusIcon("checkmark.circle.fill", color: .green)
      }
    }
  }

  private func statusIcon(_ name: String, color: Color) -> some View {
    Image(systemName: name)
      .font(.system(size: 10))
      .foregroundColor(color)
  }
}