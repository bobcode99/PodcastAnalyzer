//
//  MiniPlayerBar.swift
//  PodcastAnalyzer
//
//  Compact mini player bar that shows at bottom of TabView
//

import SwiftData
import SwiftUI

/// Navigation state for expanded player -> main nav transitions
enum ExpandedPlayerNavigation: Equatable {
  case none
  case episodeDetail(PodcastEpisodeInfo, podcastTitle: String, imageURL: String?)
  case podcastEpisodeList(PodcastInfoModel)

  static func == (lhs: ExpandedPlayerNavigation, rhs: ExpandedPlayerNavigation) -> Bool {
    switch (lhs, rhs) {
    case (.none, .none):
      return true
    case let (.episodeDetail(e1, t1, i1), .episodeDetail(e2, t2, i2)):
      return e1.title == e2.title && t1 == t2 && i1 == i2
    case let (.podcastEpisodeList(p1), .podcastEpisodeList(p2)):
      return p1.id == p2.id
    default:
      return false
    }
  }
}

struct MiniPlayerBar: View {
  @Environment(\.tabViewBottomAccessoryPlacement) var placement
  @Environment(\.modelContext) private var modelContext
  @State private var audioManager = EnhancedAudioManager.shared
  @State private var showExpandedPlayer = false

  // Pending navigation after expanded player dismisses
  @Binding var pendingNavigation: ExpandedPlayerNavigation

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

            CachedAsyncImage(url: url) { image in
              image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
              Color.gray
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
          handlePlayPauseAction()
        }) {
          Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
            .font(.title2)
            .frame(width: 32)
            .foregroundColor(.primary)
        }

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
      ExpandedPlayerView(
        onNavigateToEpisodeDetail: { episode, podcastTitle, imageURL in
          pendingNavigation = .episodeDetail(episode, podcastTitle: podcastTitle, imageURL: imageURL)
        },
        onNavigateToPodcast: { podcast in
          pendingNavigation = .podcastEpisodeList(podcast)
        }
      )
    }
  }

  // MARK: - Play/Pause Action

  private func handlePlayPauseAction() {
    // Case 1: Currently playing - just pause
    if audioManager.isPlaying {
      audioManager.pause()
      return
    }

    // Case 2: Has current episode - resume
    if audioManager.currentEpisode != nil {
      audioManager.resume()
      return
    }

    // Case 3: No current episode - try to restore last played
    audioManager.restoreLastEpisode()
    if audioManager.currentEpisode != nil {
      // Successfully restored - start playing
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        audioManager.resume()
      }
      return
    }

    // Case 4: No last episode - find one from SwiftData
    if let episode = findEpisodeToPlay() {
      audioManager.play(
        episode: episode,
        audioURL: episode.audioURL,
        startTime: 0,
        imageURL: episode.imageURL,
        useDefaultSpeed: true
      )
    }
  }

  /// Finds an episode to play when there's no previous playback history
  /// Priority: 1. Most recently played (if any), 2. Random episode from subscribed podcasts
  private func findEpisodeToPlay() -> PlaybackEpisode? {
    // First try to find the most recently played episode from SwiftData
    let recentDescriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.lastPlayedDate != nil },
      sortBy: [SortDescriptor(\.lastPlayedDate, order: .reverse)]
    )

    if let recentModel = try? modelContext.fetch(recentDescriptor).first {
      return PlaybackEpisode(
        id: recentModel.id,
        title: recentModel.episodeTitle,
        podcastTitle: recentModel.podcastTitle,
        audioURL: recentModel.audioURL,
        imageURL: recentModel.imageURL,
        pubDate: recentModel.pubDate
      )
    }

    // No recently played - get a random episode from subscribed podcasts
    let podcastDescriptor = FetchDescriptor<PodcastInfoModel>()
    guard let podcasts = try? modelContext.fetch(podcastDescriptor),
          !podcasts.isEmpty else {
      return nil
    }

    // Collect all playable episodes (those with audio URLs) from all podcasts
    var playableEpisodes: [(episode: PodcastEpisodeInfo, audioURL: String, podcastTitle: String, podcastImageURL: String)] = []
    for podcast in podcasts {
      let podcastTitle = podcast.podcastInfo.title
      let podcastImageURL = podcast.podcastInfo.imageURL
      for episode in podcast.podcastInfo.episodes {
        // Only include episodes with valid audio URLs
        if let audioURL = episode.audioURL, !audioURL.isEmpty {
          playableEpisodes.append((episode, audioURL, podcastTitle, podcastImageURL))
        }
      }
    }

    guard !playableEpisodes.isEmpty else { return nil }

    // Pick a random episode
    let randomIndex = Int.random(in: 0..<playableEpisodes.count)
    let selected = playableEpisodes[randomIndex]

    return PlaybackEpisode(
      id: "\(selected.podcastTitle)\u{1F}\(selected.episode.title)",
      title: selected.episode.title,
      podcastTitle: selected.podcastTitle,
      audioURL: selected.audioURL,
      imageURL: selected.episode.imageURL ?? selected.podcastImageURL,
      episodeDescription: selected.episode.podcastEpisodeDescription,
      pubDate: selected.episode.pubDate,
      duration: selected.episode.duration,
      guid: selected.episode.guid
    )
  }
}
// MARK: - Preview

#Preview {
  MiniPlayerBar(pendingNavigation: .constant(.none))
}
