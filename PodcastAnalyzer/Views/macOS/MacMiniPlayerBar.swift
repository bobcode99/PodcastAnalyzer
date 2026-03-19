//
//  MacMiniPlayerBar.swift
//  PodcastAnalyzer
//
//  macOS floating mini player bar — Apple Podcasts style with glass background
//

#if os(macOS)
import SwiftUI

struct MacMiniPlayerBar: View {
  @Binding var showExpandedPlayer: Bool
  private var audioManager: EnhancedAudioManager { .shared }
  @State private var isHoveringProgress = false
  @State private var isDraggingProgress = false

  private var progressPercentage: Double {
    guard audioManager.duration > 0 else { return 0 }
    return audioManager.currentTime / audioManager.duration
  }

  var body: some View {
    let content = VStack(spacing: 0) {
      // Interactive progress bar
      progressBar
        .frame(height: isHoveringProgress || isDraggingProgress ? 6 : 3)
        .animation(.easeInOut(duration: 0.15), value: isHoveringProgress)
        .onHover { hovering in
          isHoveringProgress = hovering
        }

      // Player controls
      HStack(spacing: 16) {
        // Left: Artwork and episode info (clickable to expand)
        Button(action: { showExpandedPlayer = true }) {
          HStack(spacing: 12) {
            if let episode = audioManager.currentEpisode {
              CachedArtworkImage(urlString: episode.imageURL, size: 48, cornerRadius: 6)

              VStack(alignment: .leading, spacing: 2) {
                Text(episode.title)
                  .font(.subheadline)
                  .fontWeight(.medium)
                  .lineLimit(1)
                  .foregroundStyle(.primary)

                Text(episode.podcastTitle)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
              .frame(maxWidth: 320, alignment: .leading)
            }
          }
        }
        .buttonStyle(.plain)
        .help("Show full player")

        Spacer()

        // Center: Playback controls
        centerControls

        Spacer()

        // Right: Time, speed, and expand
        HStack(spacing: 12) {
          Text("\(Formatters.formatPlaybackTime(audioManager.currentTime)) / \(Formatters.formatPlaybackTime(audioManager.duration))")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .frame(width: 90, alignment: .trailing)

          // Playback speed button
          Menu {
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { speed in
              Button(action: { audioManager.setPlaybackRate(Float(speed)) }) {
                HStack {
                  Text(Formatters.formatSpeed(Float(speed)))
                  if abs(audioManager.playbackRate - Float(speed)) < 0.01 {
                    Image(systemName: "checkmark")
                  }
                }
              }
            }
          } label: {
            Text(Formatters.formatSpeed(audioManager.playbackRate))
              .font(.system(size: 11, weight: .medium))
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(.ultraThinMaterial, in: .rect(cornerRadius: 4))
          }
          .menuStyle(.borderlessButton)
          .frame(width: 44)
          .help("Playback speed")

          // Expand button
          Button(action: { showExpandedPlayer = true }) {
            Image(systemName: "chevron.up.2")
              .font(.system(size: 12))
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
          .help("Expand player")
        }
        .frame(width: 220, alignment: .trailing)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
    }
    if #available(macOS 26, *) {
      content
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    } else {
      content
        .clipShape(.rect(cornerRadius: 14))
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
    }
  }

  // MARK: - Center Controls

  @ViewBuilder
  private var centerControls: some View {
    if #available(macOS 26, *) {
      GlassEffectContainer(spacing: 24) {
        HStack(spacing: 24) {
          Button("Skip back 15 seconds", systemImage: "gobackward.15", action: { audioManager.skipBackward(seconds: 15) })
            .buttonStyle(.glass)
            .help("Skip back 15 seconds")

          Button(audioManager.isPlaying ? "Pause" : "Play", systemImage: audioManager.isPlaying ? "pause.fill" : "play.fill", action: togglePlayback)
            .buttonStyle(.glassProminent)
            .help(audioManager.isPlaying ? "Pause" : "Play")
            .keyboardShortcut(.space, modifiers: [])

          Button("Skip forward 30 seconds", systemImage: "goforward.30", action: { audioManager.skipForward(seconds: 30) })
            .buttonStyle(.glass)
            .help("Skip forward 30 seconds")
        }
      }
    } else {
      HStack(spacing: 24) {
        Button(action: { audioManager.skipBackward(seconds: 15) }) {
          Image(systemName: "gobackward.15")
            .font(.system(size: 18))
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .help("Skip back 15 seconds")

        Button(action: togglePlayback) {
          Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 24))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(audioManager.isPlaying ? "Pause" : "Play")
        .keyboardShortcut(.space, modifiers: [])

        Button(action: { audioManager.skipForward(seconds: 30) }) {
          Image(systemName: "goforward.30")
            .font(.system(size: 18))
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .help("Skip forward 30 seconds")
      }
    }
  }

  // MARK: - Actions

  private func togglePlayback() {
    if audioManager.isPlaying {
      audioManager.pause()
    } else {
      audioManager.resume()
    }
  }

  // MARK: - Progress Bar

  @ViewBuilder
  private var progressBar: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Rectangle()
          .fill(Color.gray.opacity(0.2))

        Rectangle()
          .fill(Color.accentColor)
          .frame(width: geometry.size.width * progressPercentage)
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            isDraggingProgress = true
            let progress = max(0, min(1, value.location.x / geometry.size.width))
            let newTime = progress * audioManager.duration
            audioManager.seek(to: newTime)
          }
          .onEnded { _ in
            isDraggingProgress = false
          }
      )
    }
  }
}

#Preview {
  MacMiniPlayerBar(showExpandedPlayer: .constant(false))
    .frame(width: 800)
}

#endif
