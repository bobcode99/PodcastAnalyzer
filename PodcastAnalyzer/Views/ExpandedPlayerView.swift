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

  // Speed options matching Apple Podcasts
  private let playbackSpeeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
  // Quick access speeds shown in the popup
  private let quickSpeeds: [Float] = [0.8, 1.0, 1.3, 1.5, 1.8, 2.0]

  var body: some View {
    NavigationStack {
      ZStack {
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
            // Playback speed button
            Button(action: {
              withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showSpeedPicker = true
              }
            }) {
              HStack(spacing: 4) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                Text(formatSpeed(viewModel.playbackSpeed))
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
        .blur(radius: showSpeedPicker ? 3 : 0)

        // Speed picker overlay
        if showSpeedPicker {
          SpeedPickerOverlay(
            currentSpeed: viewModel.playbackSpeed,
            quickSpeeds: quickSpeeds,
            allSpeeds: playbackSpeeds,
            onSelectSpeed: { speed in
              viewModel.setPlaybackSpeed(speed)
              withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showSpeedPicker = false
              }
            },
            onDismiss: {
              withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showSpeedPicker = false
              }
            }
          )
          .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
      }
      .navigationDestination(isPresented: $showEpisodeDetail) {
        if let episode = viewModel.currentEpisode {
          EpisodeDetailView(
            episode: PodcastEpisodeInfo(
              title: episode.title,
              podcastEpisodeDescription: nil,
              pubDate: nil,
              audioURL: episode.audioURL,
              imageURL: episode.imageURL,
              duration: nil
            ),
            podcastTitle: episode.podcastTitle,
            fallbackImageURL: episode.imageURL
          )
        }
      }
    }
  }

  private func formatSpeed(_ speed: Float) -> String {
    if speed == 1.0 {
      return "1x"
    } else if speed.truncatingRemainder(dividingBy: 1) == 0 {
      return "\(Int(speed))x"
    } else {
      return String(format: "%.2gx", speed)
    }
  }
}

// MARK: - Speed Picker Overlay (Apple Podcasts Style)
struct SpeedPickerOverlay: View {
  let currentSpeed: Float
  let quickSpeeds: [Float]
  let allSpeeds: [Float]
  let onSelectSpeed: (Float) -> Void
  let onDismiss: () -> Void

  @State private var showAllSpeeds = false

  var body: some View {
    ZStack {
      // Dimmed background
      Color.black.opacity(0.4)
        .ignoresSafeArea()
        .onTapGesture {
          onDismiss()
        }

      // Speed picker card
      VStack(spacing: 0) {
        // Header
        HStack {
          Image(systemName: "waveform")
            .foregroundColor(.secondary)
          Text("Playback Speed")
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(.primary)
          Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)

        Divider()
          .padding(.horizontal, 12)

        // Quick speed buttons
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(showAllSpeeds ? allSpeeds : quickSpeeds, id: \.self) { speed in
              SpeedButton(
                speed: speed,
                isSelected: abs(currentSpeed - speed) < 0.01,
                onTap: {
                  onSelectSpeed(speed)
                }
              )
            }
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 16)
        }

        // "More Speeds" hint
        Button(action: {
          withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showAllSpeeds.toggle()
          }
        }) {
          HStack(spacing: 4) {
            Text(showAllSpeeds ? "Show Less" : "More Speeds")
              .font(.caption)
              .foregroundColor(.secondary)
            Image(systemName: showAllSpeeds ? "chevron.up" : "chevron.down")
              .font(.caption2)
              .foregroundColor(.secondary)
          }
        }
        .padding(.bottom, 16)
      }
      .background(
        RoundedRectangle(cornerRadius: 16)
          .fill(Color(.systemBackground))
          .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
      )
      .padding(.horizontal, 24)
    }
  }
}

// MARK: - Speed Button
struct SpeedButton: View {
  let speed: Float
  let isSelected: Bool
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      Text(formatSpeed(speed))
        .font(.subheadline)
        .fontWeight(isSelected ? .bold : .medium)
        .foregroundColor(isSelected ? .white : .primary)
        .frame(minWidth: 44, minHeight: 36)
        .padding(.horizontal, 12)
        .background(
          Capsule()
            .fill(isSelected ? Color.blue : Color(.systemGray5))
        )
    }
    .buttonStyle(.plain)
  }

  private func formatSpeed(_ speed: Float) -> String {
    if speed == 1.0 {
      return "1x"
    } else if speed.truncatingRemainder(dividingBy: 1) == 0 {
      return "\(Int(speed))x"
    } else {
      return String(format: "%.2gx", speed)
    }
  }
}

// MARK: - Preview

#Preview {
  ExpandedPlayerView()
}
