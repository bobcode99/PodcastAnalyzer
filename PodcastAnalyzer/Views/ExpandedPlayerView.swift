//
//  ExpandedPlayerView.swift
//  PodcastAnalyzer
//
//  Redesigned to look like Apple Podcasts player
//

import SwiftUI

struct ExpandedPlayerView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel = ExpandedPlayerViewModel()
  @State private var showEpisodeDetail = false
  @State private var showSpeedPicker = false
  @State private var showQueue = false
  @State private var showEllipsisMenu = false

  // Speed options matching Apple Podcasts
  private let playbackSpeeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
  private let quickSpeeds: [Float] = [0.8, 1.0, 1.3, 1.5, 1.8, 2.0]

  var body: some View {
    NavigationStack {
      ZStack {
        // Background gradient based on artwork (simulated)
        LinearGradient(
          colors: [Color.gray.opacity(0.3), Color(.systemBackground)],
          startPoint: .top,
          endPoint: .center
        )
        .ignoresSafeArea()

        VStack(spacing: 0) {
          // Large artwork
          artworkSection
            .padding(.top, 20)

          // Episode info
          episodeInfoSection
            .padding(.top, 24)

          Spacer()

          // Progress bar
          progressSection
            .padding(.horizontal, 24)

          // Playback controls
          controlsSection
            .padding(.top, 24)

          // Bottom actions
          bottomActionsSection
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .blur(radius: showSpeedPicker || showQueue ? 3 : 0)

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

        // Queue overlay
        if showQueue {
          QueueOverlay(
            queue: viewModel.queue,
            onPlayItem: { index in
              viewModel.skipToQueueItem(at: index)
              withAnimation { showQueue = false }
            },
            onRemoveItem: { index in
              viewModel.removeFromQueue(at: index)
            },
            onMoveItems: { source, destination in
              viewModel.moveInQueue(from: source, to: destination)
            },
            onDismiss: {
              withAnimation { showQueue = false }
            }
          )
          .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
      }
      .navigationDestination(isPresented: $showEpisodeDetail) {
        if let episode = viewModel.currentEpisode {
          EpisodeDetailView(
            episode: PodcastEpisodeInfo(
              title: episode.title,
              podcastEpisodeDescription: episode.episodeDescription,
              pubDate: episode.pubDate,
              audioURL: episode.audioURL,
              imageURL: episode.imageURL,
              duration: episode.duration
            ),
            podcastTitle: episode.podcastTitle,
            fallbackImageURL: episode.imageURL
          )
        }
      }
    }
  }

  // MARK: - Artwork Section
  private var artworkSection: some View {
    Group {
      if let imageURL = viewModel.imageURL {
        AsyncImage(url: imageURL) { phase in
          if let image = phase.image {
            image
              .resizable()
              .aspectRatio(contentMode: .fill)
          } else {
            artworkPlaceholder
          }
        }
        .frame(width: 280, height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
      } else {
        artworkPlaceholder
          .frame(width: 280, height: 280)
          .clipShape(RoundedRectangle(cornerRadius: 16))
      }
    }
  }

  private var artworkPlaceholder: some View {
    RoundedRectangle(cornerRadius: 16)
      .fill(Color.gray.opacity(0.3))
      .overlay(
        Image(systemName: "music.note")
          .font(.system(size: 60))
          .foregroundColor(.white.opacity(0.5))
      )
  }

  // MARK: - Episode Info Section
  private var episodeInfoSection: some View {
    VStack(spacing: 8) {
      // Date
      if let date = viewModel.episodeDate {
        Text(date.formatted(date: .abbreviated, time: .omitted))
          .font(.caption)
          .foregroundColor(.secondary)
      }

      // Episode title with ellipsis menu
      HStack(alignment: .top) {
        Text(viewModel.episodeTitle)
          .font(.title3)
          .fontWeight(.semibold)
          .lineLimit(2)
          .multilineTextAlignment(.center)

        Menu {
          ellipsisMenuContent
        } label: {
          Image(systemName: "ellipsis")
            .font(.title3)
            .foregroundColor(.secondary)
            .padding(8)
        }
      }
      .padding(.horizontal, 24)

      // Podcast name
      Text(viewModel.podcastTitle)
        .font(.subheadline)
        .foregroundColor(.secondary)
        .lineLimit(1)
    }
  }

  // MARK: - Ellipsis Menu Content (Apple Podcasts Style)
  @ViewBuilder
  private var ellipsisMenuContent: some View {
    // Download/Save/Share row would be icons in Apple Podcasts
    // but we'll use standard menu items
    Button(action: {}) {
      Label("Download", systemImage: "arrow.down.circle")
    }

    Button(action: { viewModel.toggleStar() }) {
      Label(
        viewModel.isStarred ? "Unsave" : "Save",
        systemImage: viewModel.isStarred ? "bookmark.fill" : "bookmark"
      )
    }

    Button(action: { viewModel.shareEpisode() }) {
      Label("Share", systemImage: "square.and.arrow.up")
    }

    Divider()

    Button(action: { viewModel.playNextCurrentEpisode() }) {
      Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
    }

    Button(action: { viewModel.togglePlayed() }) {
      Label(
        viewModel.isCompleted ? "Mark as Unplayed" : "Mark as Played",
        systemImage: viewModel.isCompleted ? "arrow.counterclockwise" : "checkmark.circle"
      )
    }

    Divider()

    Button(action: { showEpisodeDetail = true }) {
      Label("Go to Episode", systemImage: "info.circle")
    }

    Button(action: {}) {
      Label("Go to Show", systemImage: "square.stack")
    }

    Divider()

    Button(action: {}) {
      Label("Report a Concern", systemImage: "exclamationmark.bubble")
    }
  }

  // MARK: - Progress Section
  private var progressSection: some View {
    VStack(spacing: 8) {
      // Seek slider
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          // Track background
          Capsule()
            .fill(Color.gray.opacity(0.3))
            .frame(height: 6)

          // Progress
          Capsule()
            .fill(Color.primary)
            .frame(
              width: geometry.size.width * CGFloat(viewModel.progress),
              height: 6
            )

          // Thumb (optional, for visual feedback)
          Circle()
            .fill(Color.primary)
            .frame(width: 14, height: 14)
            .offset(
              x: max(
                0, min(geometry.size.width * CGFloat(viewModel.progress) - 7, geometry.size.width - 14))
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
      .frame(height: 14)

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
    }
  }

  // MARK: - Controls Section
  private var controlsSection: some View {
    HStack(spacing: 0) {
      // Speed button
      Button(action: {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
          showSpeedPicker = true
        }
      }) {
        Text(formatSpeed(viewModel.playbackSpeed))
          .font(.system(size: 16, weight: .medium))
          .foregroundColor(.primary)
          .frame(width: 44, height: 44)
          .background(Color.gray.opacity(0.2))
          .clipShape(Circle())
      }

      Spacer()

      // Skip backward 15s
      Button(action: { viewModel.skipBackward() }) {
        Image(systemName: "gobackward.15")
          .font(.system(size: 32))
          .foregroundColor(.primary)
      }
      .frame(width: 60)

      // Play/Pause
      Button(action: { viewModel.togglePlayPause() }) {
        Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
          .font(.system(size: 72))
          .foregroundColor(.primary)
      }
      .frame(width: 80)

      // Skip forward 30s
      Button(action: { viewModel.skipForward() }) {
        Image(systemName: "goforward.30")
          .font(.system(size: 32))
          .foregroundColor(.primary)
      }
      .frame(width: 60)

      Spacer()

      // Sleep timer button
      Button(action: {}) {
        Image(systemName: "moon.zzz")
          .font(.system(size: 20))
          .foregroundColor(.primary)
          .frame(width: 44, height: 44)
          .background(Color.gray.opacity(0.2))
          .clipShape(Circle())
      }
    }
    .padding(.horizontal, 24)
  }

  // MARK: - Bottom Actions Section
  private var bottomActionsSection: some View {
    HStack {
      // AirPlay button (placeholder)
      Button(action: {}) {
        Image(systemName: "airplayaudio")
          .font(.title3)
          .foregroundColor(.secondary)
      }

      Spacer()

      // Transcript button - go to episode detail
      Button(action: { showEpisodeDetail = true }) {
        HStack(spacing: 4) {
          Image(systemName: "text.bubble")
          Text("Detail")
        }
        .font(.subheadline)
        .foregroundColor(.blue)
      }

      Spacer()

      // Queue button
      Button(action: {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
          showQueue = true
        }
      }) {
        HStack(spacing: 4) {
          Image(systemName: "list.bullet")
          if !viewModel.queue.isEmpty {
            Text("\(viewModel.queue.count)")
              .font(.caption)
              .fontWeight(.medium)
          }
        }
        .font(.title3)
        .foregroundColor(.secondary)
      }
    }
    .padding(.horizontal, 40)
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

// MARK: - Queue Overlay

struct QueueOverlay: View {
  let queue: [PlaybackEpisode]
  let onPlayItem: (Int) -> Void
  let onRemoveItem: (Int) -> Void
  let onMoveItems: (IndexSet, Int) -> Void
  let onDismiss: () -> Void

  var body: some View {
    ZStack {
      // Dimmed background
      Color.black.opacity(0.4)
        .ignoresSafeArea()
        .onTapGesture { onDismiss() }

      // Queue card
      VStack(spacing: 0) {
        // Header
        HStack {
          Text("Up Next")
            .font(.headline)
          Spacer()
          Button(action: onDismiss) {
            Image(systemName: "xmark.circle.fill")
              .font(.title2)
              .foregroundColor(.secondary)
          }
        }
        .padding()

        Divider()

        if queue.isEmpty {
          VStack(spacing: 12) {
            Image(systemName: "list.bullet")
              .font(.system(size: 40))
              .foregroundColor(.secondary)
            Text("Queue is empty")
              .font(.subheadline)
              .foregroundColor(.secondary)
            Text("Add episodes using 'Play Next'")
              .font(.caption)
              .foregroundColor(.secondary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding()
        } else {
          List {
            ForEach(Array(queue.enumerated()), id: \.element.id) { index, episode in
              HStack(spacing: 12) {
                // Episode info
                VStack(alignment: .leading, spacing: 2) {
                  Text(episode.title)
                    .font(.subheadline)
                    .lineLimit(1)
                  Text(episode.podcastTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                }

                Spacer()

                // Play button
                Button(action: { onPlayItem(index) }) {
                  Image(systemName: "play.circle")
                    .font(.title2)
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
              }
              .padding(.vertical, 4)
              .swipeActions(edge: .trailing) {
                Button(role: .destructive, action: { onRemoveItem(index) }) {
                  Label("Remove", systemImage: "trash")
                }
              }
            }
            .onMove(perform: onMoveItems)
          }
          .listStyle(.plain)
          .environment(\.editMode, .constant(.active))
        }
      }
      .frame(maxHeight: 400)
      .background(
        RoundedRectangle(cornerRadius: 16)
          .fill(Color(.systemBackground))
          .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
      )
      .padding(.horizontal, 16)
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
        .onTapGesture { onDismiss() }

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
                onTap: { onSelectSpeed(speed) }
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
