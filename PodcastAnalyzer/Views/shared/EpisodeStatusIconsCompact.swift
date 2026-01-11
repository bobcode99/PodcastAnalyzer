//
//  EpisodeStatusIconsCompact.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2026/1/4.
//

import Foundation
import SwiftUI

/// Compact status icons for overlays on artwork
struct EpisodeStatusIconsCompact: View {
  let isStarred: Bool
  let isDownloaded: Bool
  let hasTranscript: Bool
  let hasAIAnalysis: Bool
  let isDownloading: Bool
  let downloadProgress: Double
  let isTranscribing: Bool

  init(
    isStarred: Bool = false,
    isDownloaded: Bool = false,
    hasTranscript: Bool = false,
    hasAIAnalysis: Bool = false,
    isDownloading: Bool = false,
    downloadProgress: Double = 0,
    isTranscribing: Bool = false
  ) {
    self.isStarred = isStarred
    self.isDownloaded = isDownloaded
    self.hasTranscript = hasTranscript
    self.hasAIAnalysis = hasAIAnalysis
    self.isDownloading = isDownloading
    self.downloadProgress = downloadProgress
    self.isTranscribing = isTranscribing
  }

  private var hasAnyStatus: Bool {
    isStarred || isDownloaded || hasTranscript || hasAIAnalysis || isDownloading || isTranscribing
  }

  var body: some View {
    if hasAnyStatus {
      HStack(spacing: 3) {
        if isStarred {
          statusIcon("star.fill", color: .yellow)
        }

        // Download status: show progress if downloading, checkmark if downloaded
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
        .foregroundColor(.blue)
    }
    .frame(width: 14, height: 14)
  }

  private var transcriptProgressView: some View {
    HStack(spacing: 2) {
      ProgressView()
        .scaleEffect(0.4)
        .frame(width: 10, height: 10)
      Image(systemName: "text.bubble")
        .font(.system(size: 7, weight: .bold))
        .foregroundColor(.purple)
    }
  }
}