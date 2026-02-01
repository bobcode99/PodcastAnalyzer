//
//  EpisodeStatusIcons.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2026/1/4.
//

import Foundation
import SwiftUI

/// Reusable view for displaying episode status icons
struct EpisodeStatusIcons: View {
  let isStarred: Bool
  let isDownloaded: Bool
  let hasTranscript: Bool
  let hasAIAnalysis: Bool
  let isCompleted: Bool
  let showCompleted: Bool
  let isDownloading: Bool
  let downloadProgress: Double
  let isTranscribing: Bool

  init(
    isStarred: Bool = false,
    isDownloaded: Bool = false,
    hasTranscript: Bool = false,
    hasAIAnalysis: Bool = false,
    isCompleted: Bool = false,
    showCompleted: Bool = true,
    isDownloading: Bool = false,
    downloadProgress: Double = 0,
    isTranscribing: Bool = false
  ) {
    self.isStarred = isStarred
    self.isDownloaded = isDownloaded
    self.hasTranscript = hasTranscript
    self.hasAIAnalysis = hasAIAnalysis
    self.isCompleted = isCompleted
    self.showCompleted = showCompleted
    self.isDownloading = isDownloading
    self.downloadProgress = downloadProgress
    self.isTranscribing = isTranscribing
  }

  var body: some View {
    HStack(spacing: 4) {
      if isStarred {
        statusIcon("star.fill", color: .yellow)
      }

      // Download status: show progress if downloading, icon if downloaded
      if isDownloading {
        downloadProgressView
      } else if isDownloaded {
        statusIcon("arrow.down.circle.fill", color: .green)
      }

      // Transcript status: show progress if transcribing, icon if has transcript
      if isTranscribing {
        transcriptProgressView
      } else if hasTranscript {
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
      .foregroundStyle(color)
  }

  private var downloadProgressView: some View {
    ZStack {
      Circle()
        .stroke(Color.blue.opacity(0.3), lineWidth: 2)
      Circle()
        .trim(from: 0, to: downloadProgress)
        .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        .rotationEffect(.degrees(-90))
      Image(systemName: "arrow.down")
        .font(.system(size: 6, weight: .bold))
        .foregroundStyle(.blue)
    }
    .frame(width: 14, height: 14)
  }

  private var transcriptProgressView: some View {
    HStack(spacing: 2) {
      ProgressView()
        .scaleEffect(0.4)
        .frame(width: 10, height: 10)
      Image(systemName: "text.bubble")
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(.purple)
    }
  }
}