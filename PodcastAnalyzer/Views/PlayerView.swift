//
//  PlayerView.swift
//  PodcastAnalyzer
//
//  DEPRECATED: This full-screen player has been replaced by ExpandedPlayerView
//  This file is kept for reference but should not be used in new code
//

import SwiftUI

@available(*, deprecated, message: "Use ExpandedPlayerView instead")

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PlayerViewModel

    init(episode: PodcastEpisodeInfo, podcastTitle: String, audioURL: String, imageURL: String?) {
        _viewModel = StateObject(
            wrappedValue: PlayerViewModel(
                episode: episode,
                podcastTitle: podcastTitle,
                audioURL: audioURL,
                imageURL: imageURL
            ))
    }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.black, Color.gray.opacity(0.3)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Top Bar
                topBar
                    .padding(.top)  // Respect safe area for notch

                ScrollView {
                    VStack(spacing: 32) {
                        // MARK: - Artwork
                        artworkSection
                            .padding(.top, 20)

                        // MARK: - Episode Info
                        episodeInfoSection

                        // MARK: - Progress Slider
                        progressSection

                        // MARK: - Playback Controls
                        playbackControlsSection

                        // MARK: - Speed & Additional Controls
                        additionalControlsSection

                        // MARK: - Live Captions
                        if !viewModel.currentCaption.isEmpty {
                            captionsSection
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
        }
        .preferredColorScheme(.dark)  // Force dark mode for player
        .onAppear {
            viewModel.startPlayback()
        }
        // Don't pause on disappear - let mini player continue playing
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button(action: {
                dismiss()
            }) {
                Image(systemName: "chevron.down")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding()
            }

            Spacer()

            Menu {
                Button(action: {
                    viewModel.shareEpisode()
                }) {
                    Label("Share Episode", systemImage: "square.and.arrow.up")
                }

                Button(action: {
                    viewModel.addToPlaylist()
                }) {
                    Label("Add to Playlist", systemImage: "plus")
                }

                Button(action: {
                    viewModel.showEpisodeNotes()
                }) {
                    Label("Episode Notes", systemImage: "doc.text")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding()
            }
        }
    }

    // MARK: - Artwork Section

    private var artworkSection: some View {
        ZStack {
            if let url = viewModel.imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)  // Changed from .fill to .fit
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    case .failure:
                        placeholderArtwork
                    case .empty:
                        ProgressView()
                            .tint(.white)
                    @unknown default:
                        placeholderArtwork
                    }
                }
            } else {
                placeholderArtwork
            }
        }
        .frame(width: 300, height: 300)
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
    }

    private var placeholderArtwork: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.gray.opacity(0.3))
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 80))
                    .foregroundColor(.white.opacity(0.5))
            )
    }

    // MARK: - Episode Info Section

    private var episodeInfoSection: some View {
        VStack(spacing: 8) {
            Text(viewModel.episodeTitle)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(viewModel.podcastTitle)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(spacing: 12) {
            // Custom Slider
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track background
                    Capsule()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 4)

                    // Progress
                    Capsule()
                        .fill(Color.white)
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

            // Time labels
            HStack {
                Text(viewModel.currentTimeString)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .monospacedDigit()

                Spacer()

                Text(viewModel.remainingTimeString)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Playback Controls Section

    private var playbackControlsSection: some View {
        HStack(spacing: 60) {
            // Skip backward
            Button(action: {
                viewModel.skipBackward()
            }) {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 36))
                    .foregroundColor(.white)
            }

            // Play/Pause
            Button(action: {
                viewModel.togglePlayPause()
            }) {
                Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
            }

            // Skip forward
            Button(action: {
                viewModel.skipForward()
            }) {
                Image(systemName: "goforward.15")
                    .font(.system(size: 36))
                    .foregroundColor(.white)
            }
        }
        .padding(.vertical, 20)
    }

    // MARK: - Additional Controls Section

    private var additionalControlsSection: some View {
        HStack(spacing: 40) {
            // Playback speed
            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { speed in
                    Button(action: {
                        viewModel.setPlaybackSpeed(Float(speed))
                    }) {
                        HStack {
                            Text("\(speed, specifier: "%.2f")x")
                            if abs(viewModel.playbackSpeed - Float(speed)) < 0.01 {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(.title3)
                    Text("\(viewModel.playbackSpeed, specifier: "%.2f")x")
                        .font(.caption)
                }
                .foregroundColor(.white)
            }

            Spacer()

            // Sleep timer (placeholder)
            Button(action: {
                viewModel.showSleepTimer()
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "moon.zzz")
                        .font(.title3)
                    Text("Sleep")
                        .font(.caption)
                }
                .foregroundColor(.white)
            }

            Spacer()

            // AirPlay
            Button(action: {
                viewModel.showAirPlay()
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "airplayaudio")
                        .font(.title3)
                    Text("AirPlay")
                        .font(.caption)
                }
                .foregroundColor(.white)
            }

            Spacer()

            // Queue/Playlist
            Button(action: {
                viewModel.showQueue()
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                        .font(.title3)
                    Text("Queue")
                        .font(.caption)
                }
                .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Captions Section

    private var captionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "captions.bubble")
                    .foregroundColor(.blue)
                Text("Live Captions")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }

            ScrollView {
                Text(viewModel.currentCaption)
                    .font(.body)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

