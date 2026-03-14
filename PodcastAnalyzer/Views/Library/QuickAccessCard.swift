//
//  QuickAccessCard.swift
//  PodcastAnalyzer
//
//  Quick access card and podcast grid cell for the Library tab.
//

import SwiftUI

// MARK: - Quick Access Card

struct QuickAccessCard: View {
  let icon: String
  let iconColor: Color
  let title: String
  let count: Int
  var isLoading: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: icon)
          .font(.system(size: 20))
          .foregroundStyle(iconColor)

        Spacer()

        if isLoading {
          ProgressView()
            .scaleEffect(0.6)
        } else {
          Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Spacer()

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundStyle(.primary)

        Text("\(count) episodes")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, minHeight: 90)
    .glassEffect(Glass.regular, in: .rect(cornerRadius: 12))
  }
}

// MARK: - Podcast Grid Cell

struct PodcastGridCell: View {
  let podcast: PodcastInfoModel

  private static let relativeDateFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter
  }()

  private var latestEpisodeDate: String? {
    guard let date = podcast.podcastInfo.episodes.first?.pubDate else { return nil }
    return Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      CachedAsyncImage(url: URL(string: podcast.podcastInfo.imageURL)) { image in
        image.resizable().aspectRatio(contentMode: .fill)
      } placeholder: {
        Color.gray.opacity(0.2)
          .overlay(ProgressView().scaleEffect(0.5))
      }
      .aspectRatio(1, contentMode: .fit)
      .clipShape(.rect(cornerRadius: 10))
      .clipped()

      Text(podcast.podcastInfo.title)
        .font(.caption)
        .fontWeight(.medium)
        .lineLimit(2)
        .foregroundStyle(.primary)

      if let dateStr = latestEpisodeDate {
        Text(dateStr)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
  }
}
