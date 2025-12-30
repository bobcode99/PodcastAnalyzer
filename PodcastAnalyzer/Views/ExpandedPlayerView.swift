//
//  ExpandedPlayerView.swift
//  PodcastAnalyzer
//
//  Redesigned to look like Apple Podcasts player
//

import SwiftData
import SwiftUI

struct ExpandedPlayerView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @StateObject private var viewModel = ExpandedPlayerViewModel()
  @State private var showEpisodeDetail = false
  @State private var showPodcastEpisodeList = false
  @State private var showSpeedPicker = false
  @State private var showQueue = false
  @State private var showEllipsisMenu = false
  @State private var showFullTranscript = false

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

        ScrollView {
          VStack(spacing: 0) {
            // Large artwork
            artworkSection
              .padding(.top, 20)

            // Episode info
            episodeInfoSection
              .padding(.top, 24)

            // Progress bar
            progressSection
              .padding(.horizontal, 24)
              .padding(.top, 32)

            // Playback controls
            controlsSection
              .padding(.top, 24)

            // Bottom actions
            bottomActionsSection
              .padding(.top, 24)

            // Transcript preview section (if available)
            if viewModel.hasTranscript {
              transcriptPreviewSection
                .padding(.top, 24)
            }

            Spacer(minLength: 40)
          }
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
              duration: episode.duration,
              guid: episode.guid
            ),
            podcastTitle: episode.podcastTitle,
            fallbackImageURL: episode.imageURL
          )
        }
      }
      .navigationDestination(isPresented: $showPodcastEpisodeList) {
        if let podcastModel = viewModel.podcastModel {
          EpisodeListView(podcastModel: podcastModel)
        }
      }
      .onAppear {
        viewModel.setModelContext(modelContext)
      }
      .sheet(isPresented: $showFullTranscript) {
        TranscriptFullScreenView(viewModel: viewModel)
      }
    }
  }

  // MARK: - Transcript Preview Section
  private var transcriptPreviewSection: some View {
    VStack(spacing: 12) {
      // Header
      HStack {
        HStack(spacing: 6) {
          Image(systemName: "captions.bubble.fill")
            .foregroundColor(.purple)
          Text("Transcript")
            .font(.headline)
        }

        Spacer()

        Button(action: { showFullTranscript = true }) {
          HStack(spacing: 4) {
            Text("Expand")
              .font(.subheadline)
            Image(systemName: "arrow.up.left.and.arrow.down.right")
              .font(.caption)
          }
          .foregroundColor(.blue)
        }
      }
      .padding(.horizontal, 20)

      // Current segment highlight
      if let currentText = viewModel.currentSegmentText {
        Text(currentText)
          .font(.body)
          .foregroundColor(.primary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 20)
          .padding(.vertical, 12)
          .frame(maxWidth: .infinity)
          .background(Color.blue.opacity(0.1))
          .cornerRadius(12)
          .padding(.horizontal, 16)
      }

      // Preview of segments (show 3 upcoming)
      VStack(spacing: 0) {
        ForEach(getPreviewSegments(), id: \.id) { segment in
          Button(action: { viewModel.seekToSegment(segment) }) {
            HStack(alignment: .top, spacing: 10) {
              Text(segment.formattedStartTime)
                .font(.caption)
                .foregroundColor(.blue)
                .frame(width: 50, alignment: .leading)

              Text(segment.text)
                .font(.subheadline)
                .foregroundColor(viewModel.currentSegmentId == segment.id ? .primary : .secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
              viewModel.currentSegmentId == segment.id
                ? Color.blue.opacity(0.15)
                : Color.clear
            )
          }
          .buttonStyle(.plain)
        }
      }
      .background(Color(.systemGray6))
      .cornerRadius(12)
      .padding(.horizontal, 16)
    }
  }

  private func getPreviewSegments() -> [TranscriptSegment] {
    let segments = viewModel.transcriptSegments
    guard !segments.isEmpty else { return [] }

    let currentId = viewModel.currentSegmentId ?? 0
    let startIndex = max(0, currentId - 1)
    let endIndex = min(segments.count, startIndex + 4)

    return Array(segments[startIndex..<endIndex])
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
    VStack(spacing: 12) {
      // 1. Fixed height container for Title and Ellipsis
      HStack(alignment: .center, spacing: 16) {
        // Spacer to keep title centered if you want,
        // but usually, it's better to let title take space and fix the button.
        VStack(alignment: .center, spacing: 4) {
          Text(viewModel.episodeTitle)
            .font(.title3)
            .fontWeight(.bold)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .foregroundColor(.primary)

          // Podcast name button
          Button(action: { showPodcastEpisodeList = true }) {
            Text(viewModel.podcastTitle)
              .font(.subheadline)
              .fontWeight(.medium)
              .foregroundColor(.blue)
          }
        }
        .frame(maxWidth: .infinity)
        // This ensures the title doesn't overlap the button
        .padding(.leading, 44)

        // 2. Enhanced Ellipsis Button
        Menu {
          ellipsisMenuContent
        } label: {
          Image(systemName: "ellipsis.circle.fill")
            .font(.system(size: 24))
            .foregroundColor(.secondary.opacity(0.5))
            .frame(width: 44, height: 44)  // Large touch target
            .contentShape(Rectangle())  // Makes the whole 44x44 area tappable
        }
      }
      .padding(.horizontal, 20)

      // Date Label
      if let date = viewModel.episodeDate {
        Text(date.formatted(date: .abbreviated, time: .omitted))
          .font(.caption2)
          .fontWeight(.bold)
          .foregroundColor(.secondary)
          .textCase(.uppercase)
      }
    }
  }

  // MARK: - Ellipsis Menu Content (Apple Podcasts Style)
  @ViewBuilder
  private var ellipsisMenuContent: some View {
    // SECTION 1: Immediate Actions
    Section {
      Button(action: { viewModel.playNextCurrentEpisode() }) {
        Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
      }

      Button(action: { viewModel.shareEpisode() }) {
        Label("Share Episode...", systemImage: "square.and.arrow.up")
      }
    }

    // SECTION 2: Library Management
    Section {
      Button(action: { viewModel.toggleStar() }) {
        Label(
          viewModel.isStarred ? "Unstar Episode" : "Star Episode",
          systemImage: viewModel.isStarred ? "star.fill" : "star"
        )
      }

      if viewModel.hasLocalAudio {
        Button(role: .destructive, action: { viewModel.deleteDownload() }) {
          Label("Remove Download", systemImage: "minus.circle")
        }
      } else {
        Button(action: { viewModel.startDownload() }) {
          Label("Download Episode", systemImage: "arrow.down.circle")
        }
      }
    }

    // SECTION 3: Navigation & Info
    Section {
      Button(action: { showEpisodeDetail = true }) {
        Label("View Episode Description", systemImage: "doc.text")
      }

      Button(action: { showPodcastEpisodeList = true }) {
        Label("Go to Show", systemImage: "square.stack")
      }
    }

    // SECTION 4: Feedback
    Section {
      Button(role: .destructive, action: { viewModel.reportConcern() }) {
        Label("Report a Concern", systemImage: "exclamationmark.bubble")
      }
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
                0,
                min(geometry.size.width * CGFloat(viewModel.progress) - 7, geometry.size.width - 14)
              )
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

// MARK: - Transcript Full Screen View

struct TranscriptFullScreenView: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var viewModel: ExpandedPlayerViewModel

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        // Search bar
        HStack {
          Image(systemName: "magnifyingglass")
            .foregroundColor(.secondary)
            .font(.system(size: 14))
          TextField(
            "Search transcript...",
            text: $viewModel.transcriptSearchQuery
          )
          .textFieldStyle(.plain)
          .font(.subheadline)
          if !viewModel.transcriptSearchQuery.isEmpty {
            Button(action: { viewModel.transcriptSearchQuery = "" }) {
              Image(systemName: "xmark.circle.fill")
                .foregroundColor(.secondary)
                .font(.system(size: 14))
            }
          }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)

        // Mini player bar
        miniPlayerBar
          .padding(.horizontal, 16)
          .padding(.bottom, 8)

        Divider()

        // Transcript segments
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(spacing: 0) {
              ForEach(viewModel.filteredTranscriptSegments, id: \.id) { segment in
                TranscriptSegmentRow(
                  segment: segment,
                  isCurrentSegment: viewModel.currentSegmentId == segment.id,
                  searchQuery: viewModel.transcriptSearchQuery,
                  showTimestamp: true,
                  onTap: { viewModel.seekToSegment(segment) }
                )
                .id(segment.id)
              }
            }
            .padding(.vertical, 8)
          }
          .onChange(of: viewModel.currentSegmentId) { _, newId in
            if let id = newId, viewModel.transcriptSearchQuery.isEmpty {
              withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(id, anchor: .center)
              }
            }
          }
        }
      }
      .navigationTitle("Transcript")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") {
            dismiss()
          }
        }
      }
    }
  }

  // Mini player bar inside transcript sheet
  private var miniPlayerBar: some View {
    HStack(spacing: 12) {
      // Small artwork
      if let imageURL = viewModel.imageURL {
        AsyncImage(url: imageURL) { phase in
          if let image = phase.image {
            image.resizable().aspectRatio(contentMode: .fill)
          } else {
            Color.gray.opacity(0.3)
          }
        }
        .frame(width: 44, height: 44)
        .cornerRadius(6)
      }

      // Episode info
      VStack(alignment: .leading, spacing: 2) {
        Text(viewModel.episodeTitle)
          .font(.subheadline)
          .fontWeight(.medium)
          .lineLimit(1)
        Text(viewModel.currentTimeString)
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Spacer()

      // Playback controls
      HStack(spacing: 16) {
        Button(action: { viewModel.skipBackward() }) {
          Image(systemName: "gobackward.15")
            .font(.system(size: 20))
            .foregroundColor(.primary)
        }

        Button(action: { viewModel.togglePlayPause() }) {
          Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 24))
            .foregroundColor(.primary)
        }

        Button(action: { viewModel.skipForward() }) {
          Image(systemName: "goforward.30")
            .font(.system(size: 20))
            .foregroundColor(.primary)
        }
      }
    }
    .padding(12)
    .background(Color(.systemGray6))
    .cornerRadius(12)
  }
}

// MARK: - Preview

#Preview {
  ExpandedPlayerView()
}
