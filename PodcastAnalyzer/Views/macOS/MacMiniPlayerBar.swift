//
//  MacMiniPlayerBar.swift
//  PodcastAnalyzer
//
//  macOS-specific mini player bar at bottom of window
//

#if os(macOS)
import SwiftUI

struct MacMiniPlayerBar: View {
  @State private var audioManager = EnhancedAudioManager.shared
  @State private var showExpandedPlayer = false

  private var progressPercentage: Double {
    guard audioManager.duration > 0 else { return 0 }
    return audioManager.currentTime / audioManager.duration
  }

  var body: some View {
    VStack(spacing: 0) {
      // Progress bar
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          Rectangle()
            .fill(Color.gray.opacity(0.2))

          Rectangle()
            .fill(Color.accentColor)
            .frame(width: geometry.size.width * progressPercentage)
        }
      }
      .frame(height: 3)

      // Player controls
      HStack(spacing: 16) {
        // Artwork and info
        HStack(spacing: 12) {
          if let episode = audioManager.currentEpisode {
            CachedArtworkImage(urlString: episode.imageURL, size: 44, cornerRadius: 6)

            VStack(alignment: .leading, spacing: 2) {
              Text(episode.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)

              Text(episode.podcastTitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
            .frame(maxWidth: 250, alignment: .leading)
          }
        }

        Spacer()

        // Playback controls
        HStack(spacing: 20) {
          // Skip backward
          Button(action: { audioManager.skipBackward(seconds: 15) }) {
            Image(systemName: "gobackward.15")
              .font(.title3)
          }
          .buttonStyle(.plain)
          .help("Skip back 15 seconds")

          // Play/Pause
          Button(action: {
            if audioManager.isPlaying {
              audioManager.pause()
            } else {
              audioManager.resume()
            }
          }) {
            Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
              .font(.title2)
          }
          .buttonStyle(.plain)
          .help(audioManager.isPlaying ? "Pause" : "Play")
          .keyboardShortcut(.space, modifiers: [])

          // Skip forward
          Button(action: { audioManager.skipForward(seconds: 30) }) {
            Image(systemName: "goforward.30")
              .font(.title3)
          }
          .buttonStyle(.plain)
          .help("Skip forward 30 seconds")
        }

        Spacer()

        // Time and additional controls
        HStack(spacing: 16) {
          // Current time / Duration
          Text("\(formatTime(audioManager.currentTime)) / \(formatTime(audioManager.duration))")
            .font(.caption)
            .foregroundColor(.secondary)
            .monospacedDigit()

          // Playback speed
          Menu {
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { speed in
              Button(formatSpeed(Float(speed))) {
                audioManager.setPlaybackRate(Float(speed))
              }
            }
          } label: {
            Text(formatSpeed(audioManager.playbackRate))
              .font(.caption)
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(Color.gray.opacity(0.15))
              .cornerRadius(4)
          }
          .menuStyle(.borderlessButton)
          .frame(width: 50)
          .help("Playback speed")

          // Expand button
          Button(action: { showExpandedPlayer = true }) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
              .font(.caption)
          }
          .buttonStyle(.plain)
          .help("Expand player")
        }
        .frame(width: 250, alignment: .trailing)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(Color.platformSecondaryBackground)
    }
    .sheet(isPresented: $showExpandedPlayer) {
      MacExpandedPlayerView()
    }
  }

  private func formatTime(_ time: TimeInterval) -> String {
    guard time.isFinite && time >= 0 else { return "0:00" }
    let minutes = Int(time) / 60
    let seconds = Int(time) % 60
    return String(format: "%d:%02d", minutes, seconds)
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

// MARK: - macOS Expanded Player View

struct MacExpandedPlayerView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var audioManager = EnhancedAudioManager.shared

  private var progressPercentage: Double {
    guard audioManager.duration > 0 else { return 0 }
    return audioManager.currentTime / audioManager.duration
  }

  var body: some View {
    VStack(spacing: 32) {
      // Artwork
      if let episode = audioManager.currentEpisode {
        CachedArtworkImage(urlString: episode.imageURL, size: 300, cornerRadius: 16)
          .shadow(radius: 20)
      }

      // Episode info
      VStack(spacing: 8) {
        if let episode = audioManager.currentEpisode {
          Text(episode.title)
            .font(.title2)
            .fontWeight(.bold)
            .multilineTextAlignment(.center)
            .lineLimit(2)

          Text(episode.podcastTitle)
            .font(.title3)
            .foregroundColor(.secondary)
        }
      }
      .padding(.horizontal, 40)

      // Progress slider
      VStack(spacing: 8) {
        Slider(
          value: Binding(
            get: { audioManager.currentTime },
            set: { audioManager.seek(to: $0) }
          ),
          in: 0...max(audioManager.duration, 1)
        )
        .tint(.accentColor)

        HStack {
          Text(formatTime(audioManager.currentTime))
            .font(.caption)
            .foregroundColor(.secondary)
            .monospacedDigit()

          Spacer()

          Text("-\(formatTime(audioManager.duration - audioManager.currentTime))")
            .font(.caption)
            .foregroundColor(.secondary)
            .monospacedDigit()
        }
      }
      .padding(.horizontal, 40)

      // Playback controls
      HStack(spacing: 40) {
        Button(action: { audioManager.skipBackward(seconds: 15) }) {
          Image(systemName: "gobackward.15")
            .font(.title)
        }
        .buttonStyle(.plain)

        Button(action: {
          if audioManager.isPlaying {
            audioManager.pause()
          } else {
            audioManager.resume()
          }
        }) {
          Image(systemName: audioManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
            .font(.system(size: 64))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])

        Button(action: { audioManager.skipForward(seconds: 30) }) {
          Image(systemName: "goforward.30")
            .font(.title)
        }
        .buttonStyle(.plain)
      }

      // Speed control
      HStack {
        Text("Speed")
          .font(.caption)
          .foregroundColor(.secondary)

        Picker("Speed", selection: Binding(
          get: { Double(audioManager.playbackRate) },
          set: { audioManager.setPlaybackRate(Float($0)) }
        )) {
          ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { speed in
            Text(formatSpeed(Float(speed))).tag(speed)
          }
        }
        .pickerStyle(.segmented)
        .frame(width: 400)
      }
    }
    .padding(40)
    .frame(minWidth: 500, minHeight: 600)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Close") {
          dismiss()
        }
        .keyboardShortcut(.escape, modifiers: [])
      }
    }
  }

  private func formatTime(_ time: TimeInterval) -> String {
    guard time.isFinite && time >= 0 else { return "0:00" }
    let hours = Int(time) / 3600
    let minutes = (Int(time) % 3600) / 60
    let seconds = Int(time) % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
      return String(format: "%d:%02d", minutes, seconds)
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

#Preview {
  MacMiniPlayerBar()
    .frame(width: 800)
}

#endif
