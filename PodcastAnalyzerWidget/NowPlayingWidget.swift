//
//  NowPlayingWidget.swift
//  PodcastAnalyzerWidget
//
//  Now Playing widget showing current episode with artwork and playback control.
//  Uses Link for background navigation and Button(intent:) for play/pause isolation.
//

import AppIntents
import SwiftUI
import UIKit
import WidgetKit

// MARK: - Widget Entry

struct NowPlayingEntry: TimelineEntry {
  let date: Date
  let playbackData: WidgetPlaybackData?
  /// Artwork image data loaded from shared container at timeline creation time
  let artworkData: Data?

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
      ),
      artworkData: nil
    )
  }

  static var empty: NowPlayingEntry {
    NowPlayingEntry(date: Date(), playbackData: nil, artworkData: nil)
  }
}

// MARK: - Configuration Intent (required by AppIntentTimelineProvider)

struct NowPlayingConfiguration: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "Now Playing"
  static let description: IntentDescription = "Shows the currently playing podcast episode."
}

// MARK: - Timeline Provider (iOS 17+ async)

struct NowPlayingProvider: AppIntentTimelineProvider {
  typealias Entry = NowPlayingEntry
  typealias Intent = NowPlayingConfiguration

  func placeholder(in context: Context) -> NowPlayingEntry {
    .placeholder
  }

  func snapshot(for configuration: NowPlayingConfiguration, in context: Context) async -> NowPlayingEntry {
    if context.isPreview {
      return .placeholder
    }
    return createEntry()
  }

  func timeline(for configuration: NowPlayingConfiguration, in context: Context) async -> Timeline<NowPlayingEntry> {
    let entry = createEntry()

    let refreshInterval: TimeInterval = if let data = entry.playbackData, data.isPlaying {
      60
    } else {
      300
    }

    let nextUpdate = Date().addingTimeInterval(refreshInterval)
    return Timeline(entries: [entry], policy: .after(nextUpdate))
  }

  private func createEntry() -> NowPlayingEntry {
    guard let data = WidgetDataManager.readPlaybackData(),
          !WidgetDataManager.isDataStale(data) else {
      return .empty
    }
    let artworkData = WidgetDataManager.readArtworkData()
    return NowPlayingEntry(date: Date(), playbackData: data, artworkData: artworkData)
  }
}

// MARK: - Artwork View

struct WidgetArtworkView: View {
  let artworkData: Data?
  let size: CGFloat
  let cornerRadius: CGFloat

  private var artworkImage: Image? {
    guard let artworkData, let uiImage = UIImage(data: artworkData) else {
      return nil
    }
    return Image(uiImage: uiImage)
  }

  var body: some View {
    Group {
      if let image = artworkImage {
        image.resizable().aspectRatio(contentMode: .fill)
      } else {
        Rectangle()
          .fill(Color.blue.opacity(0.3))
          .overlay {
            Image(systemName: "music.note")
              .font(size > 60 ? .largeTitle : .title2)
              .foregroundStyle(.blue)
          }
      }
    }
    .frame(width: size, height: size)
    .clipShape(.rect(cornerRadius: cornerRadius))
  }
}

// MARK: - Widget Play Button with Progress Ring

struct WidgetPlayButton: View {
  let progress: Double
  let isPlaying: Bool
  let size: CGFloat

  init(progress: Double, isPlaying: Bool, size: CGFloat = 36) {
    self.progress = progress
    self.isPlaying = isPlaying
    self.size = size
  }

  var body: some View {
    ZStack {
      Circle()
        .stroke(Color.blue.opacity(0.2), lineWidth: 3)

      Circle()
        .trim(from: 0, to: CGFloat(progress))
        .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        .rotationEffect(.degrees(-90))

      Image(systemName: isPlaying ? "pause.fill" : "play.fill")
        .font(.system(size: size * 0.38, weight: .bold))
        .foregroundStyle(.blue)
        .offset(x: isPlaying ? 0 : 1)
    }
    .frame(width: size, height: size)
  }
}

// MARK: - Entry View Router

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
      VStack(alignment: .leading, spacing: 0) {
        // Top row: artwork + play button
        HStack(alignment: .top) {
          WidgetArtworkView(artworkData: entry.artworkData, size: 44, cornerRadius: 8)
          Spacer()
          Button(intent: TogglePlaybackIntent()) {
            WidgetPlayButton(progress: data.progress, isPlaying: data.isPlaying, size: 28)
              .frame(width: 44, height: 44)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(data.isPlaying ? "Pause" : "Play")
        }

        Spacer(minLength: 4)

        // Episode title
        Text(data.episodeTitle)
          .font(.caption)
          .fontWeight(.semibold)
          .lineLimit(2)
          .foregroundStyle(.primary)

        // Podcast name
        Text(data.podcastTitle)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .padding(.top, 1)

        Spacer(minLength: 2)

        // Remaining time badge
//        WidgetRemainingBadge(data: data)
      }
      .padding(12)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .widgetURL(data.episodeDetailURL)
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
        WidgetArtworkView(artworkData: entry.artworkData, size: 80, cornerRadius: 10)

        VStack(alignment: .leading, spacing: 3) {
          // Episode title
          Text(data.episodeTitle)
            .font(.subheadline)
            .fontWeight(.semibold)
            .lineLimit(2)
            .foregroundStyle(.primary)

          // Podcast name
          Text(data.podcastTitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

          Spacer(minLength: 0)

          // Progress bar
          GeometryReader { geo in
            ZStack(alignment: .leading) {
              Capsule()
                .fill(Color.blue.opacity(0.2))
                .frame(height: 3)
              Capsule()
                .fill(Color.blue)
                .frame(width: max(geo.size.width * data.progress, 0), height: 3)
            }
          }
          .frame(height: 3)

          // Bottom row: remaining badge + play button
          HStack(alignment: .center) {
            WidgetRemainingBadge(data: data)
            Spacer()
            Button(intent: TogglePlaybackIntent()) {
              WidgetPlayButton(progress: data.progress, isPlaying: data.isPlaying, size: 28)
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(data.isPlaying ? "Pause" : "Play")
          }
        }
      }
      .padding(.leading, 12)
      .padding(.trailing, 8)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .widgetURL(data.episodeDetailURL)
    } else {
      EmptyWidgetView()
    }
  }
}

// MARK: - Remaining Time Badge (visual, not plain text)

struct WidgetRemainingBadge: View {
  let data: WidgetPlaybackData

  private var remainingSeconds: TimeInterval {
    max(0, data.duration - data.currentTime)
  }

  private var remainingText: String {
    let total = Int(remainingSeconds)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    if hours > 0 {
      return "\(hours)h \(minutes)m left"
    } else if minutes > 0 {
      return "\(minutes)m left"
    } else {
      return "<1m left"
    }
  }

  var body: some View {
    HStack(spacing: 4) {
      // Mini progress ring
      ZStack {
        Circle()
          .stroke(Color.blue.opacity(0.2), lineWidth: 2)
        Circle()
          .trim(from: 0, to: data.progress)
          .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
          .rotationEffect(.degrees(-90))
      }
      .frame(width: 14, height: 14)

//      Text(remainingText)
//        .font(.caption2)
//        .foregroundStyle(.secondary)
    }
  }
}

// MARK: - Empty Widget View

struct EmptyWidgetView: View {
  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: "headphones")
        .font(.title)
        .foregroundStyle(.blue.opacity(0.6))
      Text("No Episode Playing")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text("Open app to start listening")
        .font(.caption2)
        .foregroundStyle(.secondary.opacity(0.8))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .widgetURL(URL(string: "podcastanalyzer://library"))
  }
}

// MARK: - Widget Configuration

struct NowPlayingWidget: Widget {
  let kind: String = "NowPlayingWidget"

  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: kind, intent: NowPlayingConfiguration.self, provider: NowPlayingProvider()) { entry in
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
