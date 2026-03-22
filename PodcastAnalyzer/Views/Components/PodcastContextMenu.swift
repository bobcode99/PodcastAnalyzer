//
//  PodcastContextMenu.swift
//  PodcastAnalyzer
//
//  Reusable context menu for podcast grid cells (Library, Downloads, etc.).
//

import SwiftData
import SwiftUI

struct PodcastContextMenu: ViewModifier {
  let podcast: PodcastInfoModel
  let modelContext: ModelContext
  var onError: ((String) -> Void)?
  var onUnsubscribed: (() -> Void)?

  @State private var showUnsubscribeConfirmation = false

  func body(content: Content) -> some View {
    content
      .contextMenu {
        NavigationLink(destination: EpisodeListView(podcastModel: podcast)) {
          Label("View Episodes", systemImage: "list.bullet")
        }

        Divider()

        Button {
          Task {
            await refreshPodcast()
          }
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }

        Button {
          PlatformClipboard.string = podcast.podcastInfo.rssUrl
        } label: {
          Label("Copy RSS URL", systemImage: "doc.on.doc")
        }

        Divider()

        Button(role: .destructive) {
          showUnsubscribeConfirmation = true
        } label: {
          Label("Unsubscribe", systemImage: "minus.circle")
        }
      }
      .confirmationDialog(
        "Unsubscribe from Podcast",
        isPresented: $showUnsubscribeConfirmation,
        titleVisibility: .visible
      ) {
        Button("Unsubscribe", role: .destructive) {
          unsubscribePodcast()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Are you sure you want to unsubscribe from \"\(podcast.podcastInfo.title)\"? Downloaded episodes will remain available.")
      }
  }

  private func refreshPodcast() async {
    let rssService = PodcastRssService()
    do {
      let updatedPodcast = try await rssService.fetchPodcast(from: podcast.podcastInfo.rssUrl)
      podcast.podcastInfo = updatedPodcast
      podcast.lastUpdated = Date()
      try modelContext.save()
    } catch {
      onError?("Failed to refresh: \(error.localizedDescription)")
    }
  }

  private func unsubscribePodcast() {
    podcast.isSubscribed = false
    do {
      try modelContext.save()
      onUnsubscribed?()
    } catch {
      onError?("Failed to unsubscribe: \(error.localizedDescription)")
    }
  }
}

extension View {
  func podcastContextMenu(
    podcast: PodcastInfoModel,
    modelContext: ModelContext,
    onError: ((String) -> Void)? = nil,
    onUnsubscribed: (() -> Void)? = nil
  ) -> some View {
    modifier(PodcastContextMenu(
      podcast: podcast,
      modelContext: modelContext,
      onError: onError,
      onUnsubscribed: onUnsubscribed
    ))
  }
}
