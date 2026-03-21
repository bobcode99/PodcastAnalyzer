//
//  RSSTranscriptWarningBanner.swift
//  PodcastAnalyzer
//
//  Warning banner for RSS-sourced transcripts that may have DAI timestamp drift.
//  Shows an expandable time-offset slider and optional regenerate button.
//

import SwiftUI

/// Displays a warning banner for RSS-sourced transcripts where Dynamic Ad Insertion
/// may cause transcript timestamps to drift from actual audio playback position.
struct RSSTranscriptWarningBanner: View {
    @Binding var showOffsetSlider: Bool
    @Binding var showRegenerateConfirmation: Bool
    var transcriptTimeOffset: Double
    var hasLocalAudio: Bool
    var onOffsetChanged: (Double) -> Void

    var body: some View {
        VStack(spacing: 0) {
            warningRow
            if showOffsetSlider {
                offsetSliderPanel
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Divider()
        }
    }

    private var warningRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            Text("Timestamps may not match if episode includes ads")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Adjust offset", systemImage: "slider.horizontal.3") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showOffsetSlider.toggle()
                }
            }
            .font(.caption)
            .foregroundStyle(.blue)
            .labelStyle(.iconOnly)
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
    }

    private var offsetSliderPanel: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Time Offset")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(offsetLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.primary)
                Button("Reset", systemImage: "arrow.counterclockwise") {
                    onOffsetChanged(0)
                }
                .font(.caption2)
                .foregroundStyle(.blue)
                .labelStyle(.iconOnly)
                .disabled(transcriptTimeOffset == 0)
            }
            HStack(spacing: 8) {
                Button {
                    onOffsetChanged(transcriptTimeOffset - 5)
                } label: {
                    Text("-5s")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(.rect(cornerRadius: 4))
                }
                Slider(
                    value: Binding(
                        get: { transcriptTimeOffset },
                        set: { onOffsetChanged($0) }
                    ),
                    in: -120...120,
                    step: 0.5
                )
                Button {
                    onOffsetChanged(transcriptTimeOffset + 5)
                } label: {
                    Text("+5s")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(.rect(cornerRadius: 4))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    /// Offset formatted as e.g. "+12.5s" or "-3.0s" with explicit sign
    private var offsetLabel: String {
        let formatted = transcriptTimeOffset.formatted(.number.precision(.fractionLength(1)))
        return transcriptTimeOffset >= 0 ? "+\(formatted)s" : "\(formatted)s"
    }
}
