//
//  RSSTranscriptWarningBanner.swift
//  PodcastAnalyzer
//
//  Warning banner for RSS-sourced transcripts that may have DAI timestamp drift.
//  Shows an optional regenerate button when local audio is available.
//

import SwiftUI

/// Displays a warning banner for RSS-sourced transcripts where Dynamic Ad Insertion
/// may cause transcript timestamps to drift from actual audio playback position.
struct RSSTranscriptWarningBanner: View {
    @Binding var showRegenerateConfirmation: Bool
    var hasLocalAudio: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("Timestamps may not match if episode includes ads")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if hasLocalAudio {
                    Button("Regenerate", systemImage: "waveform.badge.mic") {
                        showRegenerateConfirmation = true
                    }
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .labelStyle(.titleAndIcon)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            Divider()
        }
    }
}
