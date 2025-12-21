//
//  MiniPlayerBar.swift
//  PodcastAnalyzer
//
//  Compact mini player bar that shows at bottom of TabView
//

import Combine
import SwiftUI

struct MiniPlayerBar: View {
  @Environment(\.tabViewBottomAccessoryPlacement)
  var placement

  @State private var audioManager = EnhancedAudioManager.shared
  @State private var showExpandedPlayer = false

  private var progress: Double {
    guard audioManager.duration > 0 else { return 0 }
    return audioManager.currentTime / audioManager.duration
  }

  private var imageURL: URL? {
    guard let urlString = audioManager.currentEpisode?.imageURL else { return nil }
    return URL(string: urlString)
  }

  var body: some View {
    VStack(spacing: 0) {
      // Progress bar
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

      // Main content
      HStack(spacing: 12) {
        // Artwork
        if let imageURL = imageURL {
          AsyncImage(url: imageURL) { phase in
            if let image = phase.image {
              image
                .resizable()
                .aspectRatio(contentMode: .fill)
            } else {
              Color.gray
            }
          }
          .frame(width: 48, height: 48)
          .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
          RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.3))
            .frame(width: 48, height: 48)
            .overlay(
              Image(systemName: "music.note")
                .foregroundColor(.white)
            )
        }

        // Episode info
        VStack(alignment: .leading, spacing: 2) {
          Text(audioManager.currentEpisode?.title ?? "")
            .font(.subheadline)
            .fontWeight(.medium)
            .lineLimit(1)

          Text(audioManager.currentEpisode?.podcastTitle ?? "")
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }

        Spacer()

        // Play/Pause button
        Button(action: {
          if audioManager.isPlaying {
            audioManager.pause()
          } else {
            audioManager.resume()
          }
        }) {
          Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
            .font(.title2)
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
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(
        Color(uiColor: .secondarySystemBackground)
      )
      .contentShape(Rectangle())
      .onTapGesture {
        showExpandedPlayer = true
      }
    }
    .sheet(isPresented: $showExpandedPlayer) {
      ExpandedPlayerView()
        .presentationDetents([.height(300), .large])
        .presentationDragIndicator(.visible)
    }
  }
}

// MARK: - Preview

#Preview {
  MiniPlayerBar()
}
