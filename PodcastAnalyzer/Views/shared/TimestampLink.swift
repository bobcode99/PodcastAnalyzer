//
//  TimestampLink.swift
//  PodcastAnalyzer
//
//  Reusable underlined-timestamp Menu used in transcript search results
//  and episode detail timestamp chips.
//

import SwiftUI

/// An underlined timestamp that opens a Menu with "Play from …" and "Share" actions.
struct TimestampLink: View {
    let text: String
    let seconds: TimeInterval
    let onPlay: () -> Void
    let onShare: () -> Void

    var body: some View {
        Menu {
            Button("Play from \(text)", systemImage: "play.fill", action: onPlay)
            Button("Share", systemImage: "square.and.arrow.up", action: onShare)
        } label: {
            Text(text)
                .font(.caption2)
                .underline()
                .foregroundStyle(.tint)
                .monospacedDigit()
        }
    }
}
