//
//  MiniPlayerBar.swift
//  PodcastAnalyzer
//
//  Compact mini player bar that shows at bottom of TabView
//

import SwiftUI

struct MiniPlayerBar: View {
  @Environment(\.tabViewBottomAccessoryPlacement) var placement
  @State private var audioManager = EnhancedAudioManager.shared
  @State private var showExpandedPlayer = false

  private var progress: Double {
    guard audioManager.duration > 0 else { return 0 }
    return audioManager.currentTime / audioManager.duration
  }

  var body: some View {
    VStack(spacing: 0) {
      // Progress bar (hidden or 0 if not playing)
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(height: 3)

          Rectangle()
            .fill(Color.blue)
            .frame(
              width: geometry.size.width * CGFloat(progress),
              height: 3
            )
        }
      }
      .frame(height: 3)
      .opacity(audioManager.currentEpisode == nil ? 0 : 1)

      // Main content
      HStack(spacing: 12) {
        // Artwork or Placeholder
        Group {
          if let urlString = audioManager.currentEpisode?.imageURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
              if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
              } else {
                Color.gray
              }
            }
          } else {
            RoundedRectangle(cornerRadius: 8)
              .fill(Color.gray.opacity(0.3))
              .overlay(Image(systemName: "music.note").foregroundColor(.secondary))
          }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 8))

        // Episode info
        VStack(alignment: .leading, spacing: 2) {
          Text(audioManager.currentEpisode?.title ?? "Not Playing")
            .font(.subheadline)
            .fontWeight(.medium)
            .lineLimit(1)

          Text(audioManager.currentEpisode?.podcastTitle ?? "Select an episode to play")
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }

        Spacer()

        // Play/Pause button
        Button(action: {
          if let _ = audioManager.currentEpisode {
            if audioManager.isPlaying {
              audioManager.pause()
            } else {
              audioManager.resume()
            }
          } else {
            // Logic to play last library item
            audioManager.restoreLastEpisode()
            // Small delay to allow restoration before playing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                audioManager.resume()
            }
          }
        }) {
          Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
            .font(.title2)
            .frame(width: 32)
            .foregroundColor(.primary)
        }

        // Forward 30s button
        Button(action: {
          audioManager.skipForward(seconds: 30)
        }) {
          Image(systemName: "goforward.30")
            .font(.title3)
            .foregroundColor(.primary)
        }
        .padding(.trailing, 4)
        .disabled(audioManager.currentEpisode == nil)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(Color.platformSecondaryBackground)
      .contentShape(Rectangle())
      .onTapGesture {
        if audioManager.currentEpisode != nil {
          showExpandedPlayer = true
        }
      }
    }
    .sheet(isPresented: $showExpandedPlayer) {
      ExpandedPlayerView()
    }
  }
}
// MARK: - Preview

#Preview {
  MiniPlayerBar()
}
