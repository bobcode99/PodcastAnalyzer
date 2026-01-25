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
      VStack(alignment: .leading, spacing: 8) {
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
                  .font(.title)
                  .foregroundColor(.blue)
              )
          }
        }
        .frame(width: 60, height: 60)
        .cornerRadius(8)

        // Title
        Text(data.episodeTitle)
          .font(.caption)
          .fontWeight(.semibold)
          .lineLimit(2)
          .foregroundColor(.primary)

        // Progress indicator
        HStack(spacing: 4) {
          Image(systemName: data.isPlaying ? "play.fill" : "pause.fill")
            .font(.caption2)
            .foregroundColor(.blue)
          Text(data.formattedRemainingTime)
            .font(.caption2)
            .foregroundColor(.secondary)
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .widgetURL(URL(string: "podcastanalyzer://nowplaying"))
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
        .frame(width: 100, height: 100)
        .cornerRadius(12)

        VStack(alignment: .leading, spacing: 6) {
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

          // Progress bar
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

            // Time labels
            HStack {
              Text(data.formattedCurrentTime)
                .font(.caption2)
                .foregroundColor(.secondary)
              Spacer()
              Text(data.formattedRemainingTime)
                .font(.caption2)
                .foregroundColor(.secondary)
            }
          }

          // Play state
          HStack(spacing: 4) {
            Image(systemName: data.isPlaying ? "play.fill" : "pause.fill")
              .font(.caption)
              .foregroundColor(.blue)
            Text(data.isPlaying ? "Playing" : "Paused")
              .font(.caption)
              .foregroundColor(.blue)
          }
        }
        .padding(.vertical, 4)
      }
      .padding(12)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .widgetURL(URL(string: "podcastanalyzer://nowplaying"))
    } else {
      EmptyWidgetView()
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
    .description("Shows the currently playing podcast episode.")
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
