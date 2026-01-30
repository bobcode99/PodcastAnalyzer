//
//  ExpandedPlayerView.swift
//  PodcastAnalyzer
//
//  Redesigned to look like Apple Podcasts player
//

import SwiftData
import SwiftUI

#if os(iOS)
import UIKit
#endif

struct ExpandedPlayerView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @State private var viewModel = ExpandedPlayerViewModel()
  @State private var showSpeedPicker = false
  @State private var showQueue = false
  @State private var showEllipsisMenu = false
  @State private var showFullTranscript = false
  @State private var showSleepTimerPicker = false

  // Scrubbing state for smooth slider interaction
  @State private var isScrubbing = false
  @State private var scrubbingProgress: Double = 0

  // Speed options matching Apple Podcasts
  private let playbackSpeeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
  private let quickSpeeds: [Float] = [0.8, 1.0, 1.3, 1.5, 1.8, 2.0]

  // Navigation callbacks - dismiss sheet first, then navigate in parent
  var onNavigateToEpisodeDetail: ((PodcastEpisodeInfo, String, String?) -> Void)?
  var onNavigateToPodcast: ((PodcastInfoModel) -> Void)?

  var body: some View {
    NavigationStack {
      ZStack {
        // Background gradient
        LinearGradient(
            colors: [Color.gray.opacity(0.3), Color.platformBackground],
            startPoint: .top,
            endPoint: .center
        )
        .ignoresSafeArea()

        GeometryReader { geometry in
            ScrollView {
                // This container ensures content spans at least the full screen height
                VStack(spacing: 0) {
                    
                    // 1. Artwork & Info Group
                    VStack(spacing: 0) {
                        artworkSection
                            .padding(.top, geometry.size.height * 0.02)
                        
                        episodeInfoSection
                            .padding(.top, 24)
                    }
                    
                    Spacer(minLength: 20) // Flexible space

                    // 2. Playback Group (Progress + Controls)
                    VStack(spacing: 24) {
                        progressSection
                            .padding(.horizontal, 24)
                        
                        controlsSection
                    }

                    Spacer(minLength: 20) // Flexible space

                    // 3. Bottom Actions
                    bottomActionsSection
                        .padding(.bottom, (viewModel.hasTranscript && !viewModel.transcriptSegments.isEmpty) ? 20 : 40)

                    // 4. Transcript - ONLY renders if data exists
                    if viewModel.hasTranscript && !viewModel.transcriptSegments.isEmpty {
                        transcriptPreviewSection
                            .padding(.top, 10)
                            .padding(.bottom, 40)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(minHeight: geometry.size.height) // Forces the Spacers to work
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
      .onAppear {
        viewModel.setModelContext(modelContext)
      }
      .onDisappear {
        viewModel.cleanup()
      }
      .sheet(isPresented: $showFullTranscript) {
        TranscriptFullScreenView(viewModel: viewModel)
      }
    }
  }

  // MARK: - Transcript Preview Section
  private var transcriptPreviewSection: some View {
    TranscriptPreviewView(
      segments: viewModel.transcriptSegments,
      currentSegmentId: viewModel.currentSegmentId,
      currentTime: viewModel.currentTime,
      onSegmentTap: { segment in
        viewModel.seekToSegment(segment)
      },
      onExpandTap: { showFullTranscript = true },
      previewCount: 4
    )
  }

  // MARK: - Artwork Section
  private var artworkSection: some View {
    let baseSize: CGFloat = 280
    let playingScale: CGFloat = 1.08
    let isPlaying = viewModel.isPlaying

    return Group {
      if let imageURL = viewModel.imageURL {
        // Use CachedAsyncImage for better memory management
        CachedAsyncImage(url: imageURL) { image in
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
        } placeholder: {
          artworkPlaceholder
        }
        .frame(width: baseSize, height: baseSize)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(isPlaying ? 0.4 : 0.25), radius: isPlaying ? 25 : 15, x: 0, y: isPlaying ? 12 : 8)
        .scaleEffect(isPlaying ? playingScale : 1.0)
        .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0), value: isPlaying)
      } else {
        artworkPlaceholder
          .frame(width: baseSize, height: baseSize)
          .clipShape(RoundedRectangle(cornerRadius: 16))
          .scaleEffect(isPlaying ? playingScale : 1.0)
          .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0), value: isPlaying)
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

          // Podcast name button - navigates to show's episode list
          Button(action: { navigateToPodcast() }) {
            Text(viewModel.podcastTitle)
              .font(.subheadline)
              .fontWeight(.medium)
              .foregroundColor(.blue)
          }
        }
        .frame(maxWidth: .infinity)
        // This ensures the title doesn't overlap the button
        .padding(.leading, 44)

        // 2. Enhanced Ellipsis Button - larger touch target
        Menu {
          ellipsisMenuContent
        } label: {
          Image(systemName: "ellipsis.circle.fill")
            .font(.system(size: 28))
            .symbolRenderingMode(.hierarchical)
            .foregroundColor(.secondary)
        }
        .frame(width: 48, height: 48)
        .contentShape(Rectangle())
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
      Button(action: { navigateToEpisodeDetail() }) {
        Label("View Episode Description", systemImage: "doc.text")
      }

      Button(action: { navigateToPodcast() }) {
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
    // Use scrubbing progress when user is dragging, otherwise use actual progress
    let displayProgress = isScrubbing ? scrubbingProgress : viewModel.progress
    let displayCurrentTime = isScrubbing ? scrubbingProgress * viewModel.duration : viewModel.currentTime
    let displayRemainingTime = viewModel.duration - displayCurrentTime

    return VStack(spacing: 8) {
      // Seek slider
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          // Track background
          Capsule()
            .fill(Color.gray.opacity(0.3))
            .frame(height: 6)

          // Progress - smooth animation when not scrubbing
          Capsule()
            .fill(Color.primary)
            .frame(
              width: geometry.size.width * CGFloat(displayProgress),
              height: 6
            )
            .animation(isScrubbing ? nil : .linear(duration: 0.1), value: displayProgress)

          // Thumb - slightly larger when scrubbing for better feedback
          Circle()
            .fill(Color.primary)
            .frame(width: isScrubbing ? 18 : 14, height: isScrubbing ? 18 : 14)
            .offset(
              x: max(
                0,
                min(geometry.size.width * CGFloat(displayProgress) - (isScrubbing ? 9 : 7), geometry.size.width - (isScrubbing ? 18 : 14))
              )
            )
            .animation(isScrubbing ? nil : .easeOut(duration: 0.15), value: displayProgress)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isScrubbing)
        }
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              // Only allow scrubbing if duration is available
              guard !viewModel.isDurationLoading else { return }
              // Start scrubbing - only update visual progress, don't seek yet
              if !isScrubbing {
                withAnimation(.easeOut(duration: 0.1)) {
                  isScrubbing = true
                }
                scrubbingProgress = viewModel.progress
              }
              let progress = value.location.x / geometry.size.width
              scrubbingProgress = min(max(0, progress), 1)
            }
            .onEnded { value in
              // Only seek if duration is available
              guard !viewModel.isDurationLoading else { return }
              // End scrubbing - perform the actual seek
              let progress = value.location.x / geometry.size.width
              let finalProgress = min(max(0, progress), 1)

              // First seek to the position
              viewModel.seekToProgress(finalProgress)

              // Then smoothly transition out of scrubbing mode
              // Keep scrubbing progress at final value briefly to prevent snap-back
              withAnimation(.easeOut(duration: 0.2)) {
                isScrubbing = false
              }
            }
        )
        .opacity(viewModel.isDurationLoading ? 0.5 : 1.0)
      }
      .frame(height: 18) // Slightly taller for better touch target

      // Time labels - show scrubbing time when dragging
      HStack {
        Text(formatTime(displayCurrentTime))
          .font(.caption)
          .foregroundColor(isScrubbing ? .primary : .secondary)
          .monospacedDigit()
          .animation(.easeOut(duration: 0.15), value: isScrubbing)

        Spacer()

        Text("-" + formatTime(displayRemainingTime))
          .font(.caption)
          .foregroundColor(isScrubbing ? .primary : .secondary)
          .monospacedDigit()
          .animation(.easeOut(duration: 0.15), value: isScrubbing)
      }
    }
  }

  private func formatTime(_ time: TimeInterval) -> String {
    guard time.isFinite && time >= 0 else { return "0:00" }

    let hours = Int(time) / 3600
    let minutes = Int(time) / 60 % 60
    let seconds = Int(time) % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
      return String(format: "%d:%02d", minutes, seconds)
    }
  }

  // MARK: - Controls Section
  private var controlsSection: some View {
    HStack(spacing: 0) {
      // Speed button - larger touch target
      Button(action: {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
          showSpeedPicker = true
        }
      }) {
        Text(formatSpeed(viewModel.playbackSpeed))
          .font(.system(size: 16, weight: .medium))
          .foregroundColor(.primary)
          .frame(width: 48, height: 48)
          .background(Color.gray.opacity(0.2))
          .clipShape(Circle())
      }
      .frame(width: 56, height: 56)
      .contentShape(Rectangle())

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

      // Sleep timer button - larger touch target
      Menu {
        ForEach(SleepTimerOption.allCases, id: \.self) { option in
          Button(action: { viewModel.setSleepTimer(option) }) {
            HStack {
              Label(option.displayName, systemImage: option.systemImage)
              if viewModel.sleepTimerOption == option {
                Spacer()
                Image(systemName: "checkmark")
              }
            }
          }
        }
      } label: {
        ZStack {
          Circle()
            .fill(viewModel.isSleepTimerActive ? Color.blue : Color.gray.opacity(0.2))
            .frame(width: 48, height: 48)

          if viewModel.isSleepTimerActive {
            if viewModel.sleepTimerOption == .endOfEpisode {
              Image(systemName: "stop.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(.white)
            } else {
              Text(viewModel.sleepTimerRemainingFormatted)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .minimumScaleFactor(0.5)
            }
          } else {
            Image(systemName: "moon.zzz")
              .font(.system(size: 22))
              .foregroundColor(.primary)
          }
        }
        .frame(width: 56, height: 56) // Larger touch target
        .contentShape(Rectangle())
      }
    }
    .padding(.horizontal, 24)
  }

  // MARK: - Bottom Actions Section
  private var bottomActionsSection: some View {
    HStack {
      // AirPlay button (placeholder)
      AirPlayButton()
        .frame(width: 44, height: 44)

      Spacer()

      // Transcript button - go to episode detail
      Button(action: { navigateToEpisodeDetail() }) {
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

  // MARK: - Navigation Helpers

  /// Navigate to episode detail - dismisses sheet first, then triggers callback
  private func navigateToEpisodeDetail() {
    guard let episode = viewModel.currentEpisode else { return }
    let episodeInfo = PodcastEpisodeInfo(
      title: episode.title,
      podcastEpisodeDescription: episode.episodeDescription,
      pubDate: episode.pubDate,
      audioURL: episode.audioURL,
      imageURL: episode.imageURL,
      duration: episode.duration,
      guid: episode.guid
    )
    dismiss()
    onNavigateToEpisodeDetail?(episodeInfo, episode.podcastTitle, episode.imageURL)
  }

  /// Navigate to podcast episode list - dismisses sheet first, then triggers callback
  private func navigateToPodcast() {
    guard let podcastModel = viewModel.podcastModel else { return }
    dismiss()
    onNavigateToPodcast?(podcastModel)
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
          #if os(iOS)
          .environment(\.editMode, .constant(.active))
          #endif
        }
      }
      .frame(maxHeight: 400)
      .background(
        RoundedRectangle(cornerRadius: 16)
          .fill(Color.platformBackground)
          .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
      )
      .padding(.horizontal, 16)
    }
  }
}

// MARK: - Speed Picker Overlay (Apple Podcasts Style with Slider)

struct SpeedPickerOverlay: View {
  let currentSpeed: Float
  let quickSpeeds: [Float]
  let allSpeeds: [Float]
  let onSelectSpeed: (Float) -> Void
  let onDismiss: () -> Void

  @State private var showAllSpeeds = false
  @State private var sliderValue: Float
  @State private var lastHapticSpeed: Float = 0

  // Speed stops for haptic feedback
  private let speedStops: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

  init(currentSpeed: Float, quickSpeeds: [Float], allSpeeds: [Float], onSelectSpeed: @escaping (Float) -> Void, onDismiss: @escaping () -> Void) {
    self.currentSpeed = currentSpeed
    self.quickSpeeds = quickSpeeds
    self.allSpeeds = allSpeeds
    self.onSelectSpeed = onSelectSpeed
    self.onDismiss = onDismiss
    self._sliderValue = State(initialValue: currentSpeed)
    self._lastHapticSpeed = State(initialValue: currentSpeed)
  }

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

          // Current speed display
          Text(formatSpeed(sliderValue))
            .font(.title2)
            .fontWeight(.bold)
            .foregroundColor(.blue)
            .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)

        Divider()
          .padding(.horizontal, 12)

        // Speed slider
        VStack(spacing: 8) {
          Slider(
            value: $sliderValue,
            in: 0.5...2.0,
            step: 0.05
          ) {
            Text("Speed")
          } minimumValueLabel: {
            Text("0.5x")
              .font(.caption2)
              .foregroundColor(.secondary)
          } maximumValueLabel: {
            Text("2x")
              .font(.caption2)
              .foregroundColor(.secondary)
          }
          .tint(.blue)
          .onChange(of: sliderValue) { oldValue, newValue in
            // Check if we crossed a speed stop for haptic feedback
            for stop in speedStops {
              let crossedForward = oldValue < stop && newValue >= stop
              let crossedBackward = oldValue > stop && newValue <= stop
              if crossedForward || crossedBackward {
                triggerHaptic()
                break
              }
            }
          }

          // Speed stop markers
          HStack {
            ForEach(speedStops, id: \.self) { stop in
              if stop == speedStops.first {
                Circle()
                  .fill(sliderValue >= stop ? Color.blue : Color.gray.opacity(0.3))
                  .frame(width: 6, height: 6)
              } else if stop == speedStops.last {
                Spacer()
                Circle()
                  .fill(sliderValue >= stop ? Color.blue : Color.gray.opacity(0.3))
                  .frame(width: 6, height: 6)
              } else {
                Spacer()
                Circle()
                  .fill(sliderValue >= stop ? Color.blue : Color.gray.opacity(0.3))
                  .frame(width: 6, height: 6)
              }
            }
          }
          .padding(.horizontal, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)

        Divider()
          .padding(.horizontal, 12)

        // Quick speed buttons
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(showAllSpeeds ? allSpeeds : quickSpeeds, id: \.self) { speed in
              SpeedButton(
                speed: speed,
                isSelected: abs(sliderValue - speed) < 0.03,
                onTap: {
                  withAnimation(.easeInOut(duration: 0.2)) {
                    sliderValue = speed
                  }
                  triggerHaptic()
                  onSelectSpeed(speed)
                }
              )
            }
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
        }

        // "More Speeds" hint and Apply button
        HStack {
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

          Spacer()

          Button("Apply") {
            onSelectSpeed(sliderValue)
          }
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundColor(.white)
          .padding(.horizontal, 20)
          .padding(.vertical, 8)
          .background(Color.blue)
          .cornerRadius(20)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
      }
      .background(
        RoundedRectangle(cornerRadius: 16)
          .fill(Color.platformBackground)
          .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
      )
      .padding(.horizontal, 24)
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

  private func triggerHaptic() {
    #if os(iOS)
    let generator = UIImpactFeedbackGenerator(style: .light)
    generator.impactOccurred()
    #endif
    // macOS doesn't have haptic feedback on most devices
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
            .fill(isSelected ? Color.blue : Color.platformSystemGray5)
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
  @Bindable var viewModel: ExpandedPlayerViewModel

  private var toolbarPlacement: ToolbarItemPlacement {
    #if os(iOS)
    return .topBarTrailing
    #else
    return .confirmationAction
    #endif
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        // Mini player bar
        miniPlayerBar
          .padding(.horizontal, 16)
          .padding(.top, 10)
          .padding(.bottom, 8)

        Divider()

        // Transcript content with search and flowing view
        FullTranscriptContent(
          segments: viewModel.transcriptSegments,
          currentSegmentId: viewModel.currentSegmentId,
          currentTime: viewModel.isPlaying ? viewModel.currentTime : nil,
          searchQuery: $viewModel.transcriptSearchQuery,
          filteredSegments: viewModel.filteredTranscriptSegments,
          onSegmentTap: { segment in
            viewModel.seekToSegment(segment)
          }
        )
      }
      .navigationTitle("Transcript")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: toolbarPlacement) {
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
      // Small artwork - use CachedAsyncImage for better memory management
      if let imageURL = viewModel.imageURL {
        CachedAsyncImage(url: imageURL) { image in
          image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
          Color.gray.opacity(0.3)
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
    .background(Color.platformSystemGray6)
    .cornerRadius(12)
  }
}

// MARK: - Preview

#Preview {
  ExpandedPlayerView()
}
