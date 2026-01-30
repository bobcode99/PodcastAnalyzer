//
//  NowPlayingWidget.swift
//  PodcastAnalyzerWidget
//
//  Now Playing widget showing current episode with artwork and progress
//

import SwiftUI
import WidgetKit

// MARK: - Widget Entry

struct NowPlayingEntry: TimelineEntry {
  let date: Date
  let playbackData: WidgetPlaybackData?

  static var placeholder: NowPlayingEntry {
    NowPlayingEntry(
      date: Date(),
      playbackData: WidgetPlaybackData(
        episodeTitle: "Episode Title",
        podcastTitle: "Podcast Name",
        imageURL: nil,
        audioURL: nil,
        currentTime: 300,
        duration: 1800,
        isPlaying: true,
        lastUpdated: Date()
      )
    )
  }

  static var empty: NowPlayingEntry {
    NowPlayingEntry(date: Date(), playbackData: nil)
  }
}

// MARK: - Timeline Provider

struct NowPlayingProvider: TimelineProvider {
  func placeholder(in context: Context) -> NowPlayingEntry {
    .placeholder
  }

  func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
    if context.isPreview {
      completion(.placeholder)
    } else {
      let entry = createEntry()
      completion(entry)
    }
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
    let entry = createEntry()

    // Refresh every 60 seconds when playing, every 5 minutes when paused
    let refreshInterval: TimeInterval
    if let data = entry.playbackData, data.isPlaying {
      refreshInterval = 60
    } else {
      refreshInterval = 300
    }

    let nextUpdate = Date().addingTimeInterval(refreshInterval)
    let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
    completion(timeline)
  }

  private func createEntry() -> NowPlayingEntry {
    let playbackData = WidgetDataManager.readPlaybackData()

    // Check if data is stale
    if let data = playbackData, WidgetDataManager.isDataStale(data) {
      return .empty
    }

    return NowPlayingEntry(date: Date(), playbackData: playbackData)
  }
}

// MARK: - Widget Views

struct NowPlayingWidgetEntryView: View {
  var entry: NowPlayingEntry
  @Environment(\.widgetFamily) var family

  var body: some View {
    switch family {
    case .systemSmall:
      SmallWidgetView(entry: entry)
    case .systemMedium:
      MediumWidgetView(entry: entry)
    default:
      SmallWidgetView(entry: entry)
    }
  }
}

// MARK: - Small Widget View

struct SmallWidgetView: View {
  let entry: NowPlayingEntry

  var body: some View {
    if let data = entry.playbackData {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          // Artwork
          AsyncImage(url: URL(string: data.imageURL ?? "")) { phase in
            switch phase {
            case .success(let image):
              image
                .resizable()
                .aspectRatio(contentMode: .fill)
            default:
              Rectangle()
                .fill(Color.blue.opacity(0.3))
                .overlay(
                  Image(systemName: "music.note")
                    .font(.title2)
                    .foregroundColor(.blue)
                )
            }
          }
          .frame(width: 50, height: 50)
          .cornerRadius(8)

          // Play button with progress
          WidgetPlayButton(progress: data.progress, isPlaying: data.isPlaying)
        }

        // Title
        Text(data.episodeTitle)
          .font(.caption)
          .fontWeight(.semibold)
          .lineLimit(2)
          .foregroundColor(.primary)

        // Duration: current / total
        Text("\(data.formattedCurrentTime) / \(data.formattedDuration)")
          .font(.caption2)
          .foregroundColor(.secondary)
      }
      .padding(12)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .widgetURL(data.deepLinkURL)
    } else {
      EmptyWidgetView()
    }
  }
}

// MARK: - Medium Widget View

struct MediumWidgetView: View {
  let entry: NowPlayingEntry

  var body: some View {
    if let data = entry.playbackData {
      HStack(spacing: 12) {
        // Artwork
        AsyncImage(url: URL(string: data.imageURL ?? "")) { phase in
          switch phase {
          case .success(let image):
            image
              .resizable()
              .aspectRatio(contentMode: .fill)
          default:
            Rectangle()
              .fill(Color.blue.opacity(0.3))
              .overlay(
                Image(systemName: "music.note")
                  .font(.largeTitle)
                  .foregroundColor(.blue)
              )
          }
        }
        .frame(width: 90, height: 90)
        .cornerRadius(12)

        VStack(alignment: .leading, spacing: 4) {
          // Episode title
          Text(data.episodeTitle)
            .font(.subheadline)
            .fontWeight(.semibold)
            .lineLimit(2)
            .foregroundColor(.primary)

          // Podcast name
          Text(data.podcastTitle)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)

          Spacer()

          // Progress bar with times
          VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
              ZStack(alignment: .leading) {
                Capsule()
                  .fill(Color.blue.opacity(0.2))
                  .frame(height: 4)
                Capsule()
                  .fill(Color.blue)
                  .frame(width: geo.size.width * data.progress, height: 4)
              }
            }
            .frame(height: 4)

            // Time labels: current / total
            HStack {
              Text("\(data.formattedCurrentTime) / \(data.formattedDuration)")
                .font(.caption2)
                .foregroundColor(.secondary)
              Spacer()
            }
          }

          // Play button row
          HStack(spacing: 8) {
            WidgetPlayButton(progress: data.progress, isPlaying: data.isPlaying)

            Text(data.isPlaying ? "Playing" : "Paused")
              .font(.caption)
              .foregroundColor(.blue)

            Spacer()

            Text(data.formattedRemainingTime)
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
        .padding(.vertical, 4)
      }
      .padding(12)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .widgetURL(data.deepLinkURL)
    } else {
      EmptyWidgetView()
    }
  }
}

// MARK: - Widget Play Button with Progress

struct WidgetPlayButton: View {
  let progress: Double
  let isPlaying: Bool

  var body: some View {
    ZStack {
      // Background circle
      Circle()
        .stroke(Color.blue.opacity(0.2), lineWidth: 3)
        .frame(width: 36, height: 36)

      // Progress arc
      Circle()
        .trim(from: 0, to: CGFloat(progress))
        .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        .frame(width: 36, height: 36)
        .rotationEffect(.degrees(-90))

      // Play/Pause icon
      Image(systemName: isPlaying ? "pause.fill" : "play.fill")
        .font(.system(size: 14, weight: .bold))
        .foregroundColor(.blue)
        .offset(x: isPlaying ? 0 : 1) // Slight offset for play icon visual balance
    }
  }
}

// MARK: - Empty Widget View

struct EmptyWidgetView: View {
  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: "headphones")
        .font(.title)
        .foregroundColor(.blue.opacity(0.6))
      Text("No Episode Playing")
        .font(.caption)
        .foregroundColor(.secondary)
      Text("Open app to start listening")
        .font(.caption2)
        .foregroundColor(.secondary.opacity(0.8))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .widgetURL(URL(string: "podcastanalyzer://library"))
  }
}

// MARK: - Widget Configuration

struct NowPlayingWidget: Widget {
  let kind: String = "NowPlayingWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: NowPlayingProvider()) { entry in
      NowPlayingWidgetEntryView(entry: entry)
        .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Now Playing")
    .description("Shows the currently playing podcast episode with progress.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
  NowPlayingWidget()
} timeline: {
  NowPlayingEntry.placeholder
  NowPlayingEntry.empty
}

#Preview("Medium", as: .systemMedium) {
  NowPlayingWidget()
} timeline: {
  NowPlayingEntry.placeholder
  NowPlayingEntry.empty
}
