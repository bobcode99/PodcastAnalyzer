//
//  QueueOverlay.swift
//  PodcastAnalyzer
//
//  Queue overlay for the expanded player using closure/callback pattern.
//

import SwiftUI

struct QueueOverlay: View {
  let queue: [PlaybackEpisode]
  let onPlayItem: (Int) -> Void
  let onRemoveItem: (Int) -> Void
  let onMoveItems: (IndexSet, Int) -> Void
  let onDismiss: () -> Void

  var body: some View {
    ZStack {
      Color.black.opacity(0.4)
        .ignoresSafeArea()
        .onTapGesture { onDismiss() }

      VStack(spacing: 0) {
        // Header
        HStack {
          Text("Up Next")
            .font(.headline)
          Spacer()
          Button(action: onDismiss) {
            Image(systemName: "xmark.circle.fill")
              .font(.title2)
              .foregroundStyle(.secondary)
          }
        }
        .padding()

        Divider()

        if queue.isEmpty {
          VStack(spacing: 12) {
            Image(systemName: "list.bullet")
              .font(.system(size: 40))
              .foregroundStyle(.secondary)
            Text("Queue is empty")
              .font(.subheadline)
              .foregroundStyle(.secondary)
            Text("Add episodes using 'Play Next'")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding()
        } else {
          List {
            ForEach(Array(queue.enumerated()), id: \.element.id) { index, episode in
              HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                  Text(episode.title)
                    .font(.subheadline)
                    .lineLimit(1)
                  Text(episode.podcastTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer()

                Button(action: { onPlayItem(index) }) {
                  Image(systemName: "play.circle")
                    .font(.title2)
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
              }
              .padding(.vertical, 4)
              .swipeActions(edge: .trailing) {
                Button(role: .destructive, action: { onRemoveItem(index) }) {
                  Label("Remove", systemImage: "trash")
                }
              }
            }
            .onMove(perform: onMoveItems)
          }
          .listStyle(.plain)
          #if os(iOS)
          .environment(\.editMode, .constant(.active))
          #endif
        }
      }
      .frame(maxHeight: 400)
      .glassEffect(Glass.regular, in: .rect(cornerRadius: 16))
      .padding(.horizontal, 16)
    }
  }
}
