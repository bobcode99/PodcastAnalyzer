//
//  ExpandedPlayerView.swift
//  PodcastAnalyzer
//
//  Expanded player view that shows when mini player is tapped (about 3/8 screen height)
//

import SwiftUI

struct ExpandedPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ExpandedPlayerViewModel()
    @State private var showEpisodeDetail = false
    @State private var showSpeedPicker = false

    private let playbackSpeeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Episode artwork and info
                HStack(spacing: 16) {
                    // Artwork
                    if let imageURL = viewModel.imageURL {
                        AsyncImage(url: imageURL) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Color.gray
                            }
                        }
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 80, height: 80)
                            .overlay(
                                Image(systemName: "music.note")
                                    .foregroundColor(.white)
                            )
                    }

                    // Episode info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.episodeTitle)
                            .font(.headline)
                            .lineLimit(2)

                        Text(viewModel.podcastTitle)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer()

                // Progress bar with time labels
                VStack(spacing: 8) {
                    // Time labels
                    HStack {
                        Text(viewModel.currentTimeString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()

                        Spacer()

                        Text(viewModel.remainingTimeString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 20)

                    // Seek slider
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Track background
                            Capsule()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 4)

                            // Progress
                            Capsule()
                                .fill(Color.blue)
                                .frame(
                                    width: geometry.size.width * CGFloat(viewModel.progress),
                                    height: 4
                                )
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let progress = value.location.x / geometry.size.width
                                    viewModel.seekToProgress(min(max(0, progress), 1))
                                }
                        )
                    }
                    .frame(height: 4)
                    .padding(.horizontal, 20)
                }

                Spacer()

                // Playback controls
                HStack(spacing: 40) {
                    // Skip backward 15s
                    Button(action: {
                        viewModel.skipBackward()
                    }) {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 32))
                            .foregroundColor(.primary)
                    }

                    // Play/Pause
                    Button(action: {
                        viewModel.togglePlayPause()
                    }) {
                        Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.blue)
                    }

                    // Skip forward 15s
                    Button(action: {
                        viewModel.skipForward()
                    }) {
                        Image(systemName: "goforward.15")
                            .font(.system(size: 32))
                            .foregroundColor(.primary)
                    }
                }
                .padding(.vertical, 20)

                Spacer()

                // Bottom actions
                HStack {
                    // Playback speed - using button + confirmationDialog instead of Menu
                    Button(action: {
                        showSpeedPicker = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "gauge.with.dots.needle.33percent")
                            Text("\(viewModel.playbackSpeed, specifier: "%.2g")x")
                        }
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    }

                    Spacer()

                    // Detail button - navigates to full episode detail
                    Button(action: {
                        showEpisodeDetail = true
                    }) {
                        HStack(spacing: 4) {
                            Text("Detail")
                            Image(systemName: "chevron.right")
                        }
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .confirmationDialog("Playback Speed", isPresented: $showSpeedPicker, titleVisibility: .visible) {
                ForEach(playbackSpeeds, id: \.self) { speed in
                    Button(action: {
                        viewModel.setPlaybackSpeed(speed)
                    }) {
                        if abs(viewModel.playbackSpeed - speed) < 0.01 {
                            Text("\(speed, specifier: "%.2g")x ✓")
                        } else {
                            Text("\(speed, specifier: "%.2g")x")
                        }
                    }
                }
                Button("Cancel", role: .cancel) { }
            }
            .navigationDestination(isPresented: $showEpisodeDetail) {
                if let episode = viewModel.currentEpisode {
                    EpisodeDetailView(
                        episode: PodcastEpisodeInfo(
                            title: episode.title,
                            podcastEpisodeDescription: nil,
                            pubDate: nil,
                            audioURL: episode.audioURL,
                            imageURL: episode.imageURL
                        ),
                        podcastTitle: episode.podcastTitle,
                        fallbackImageURL: episode.imageURL
                    )
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ExpandedPlayerView()
}
