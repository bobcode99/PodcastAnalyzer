//
//  EpoisodeView.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/11/23.
//

import SwiftUI
import SwiftData

struct EpisodeListView: View {
    let podcastModel: PodcastInfoModel
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var downloadManager = DownloadManager.shared
    private var audioManager: EnhancedAudioManager { EnhancedAudioManager.shared }
    @State private var episodeModels: [String: EpisodeDownloadModel] = [:]
    @State private var episodeToDelete: PodcastEpisodeInfo?
    @State private var showDeleteConfirmation = false
    @State private var isRefreshing = false
    @State private var isDescriptionExpanded = false

    private let rssService = PodcastRssService()

    var body: some View {
        List {
            // MARK: - Header Section
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    // Podcast Image
                    if let url = URL(string: podcastModel.podcastInfo.imageURL) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFit()
                            } else if phase.error != nil {
                                Color.gray
                            } else {
                                ProgressView()
                            }
                        }
                        .frame(width: 100, height: 100)
                        .cornerRadius(8)
                    } else {
                        Color.gray.frame(width: 100, height: 100).cornerRadius(8)
                    }

                    // Title and Summary with expandable description
                    VStack(alignment: .leading, spacing: 4) {
                        Text(podcastModel.podcastInfo.title)
                            .font(.headline)

                        if let summary = podcastModel.podcastInfo.podcastInfoDescription {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(summary)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(isDescriptionExpanded ? nil : 3)

                                Button(action: {
                                    withAnimation {
                                        isDescriptionExpanded.toggle()
                                    }
                                }) {
                                    Text(isDescriptionExpanded ? "Show less" : "More")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .listRowSeparator(.hidden)
            .padding(.bottom, 10)

            // MARK: - Episodes List
            Section(header: Text("Episodes (\(podcastModel.podcastInfo.episodes.count))")) {
                ForEach(podcastModel.podcastInfo.episodes, id: \.title) { episode in
                    EpisodeRowView(
                        episode: episode,
                        podcastTitle: podcastModel.podcastInfo.title,
                        fallbackImageURL: podcastModel.podcastInfo.imageURL,
                        downloadManager: downloadManager,
                        episodeModel: episodeModels[makeEpisodeKey(episode)],
                        onToggleStar: { toggleStar(for: episode) },
                        onDownload: { downloadEpisode(episode) },
                        onDeleteRequested: {
                            episodeToDelete = episode
                            showDeleteConfirmation = true
                        }
                    )
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(podcastModel.podcastInfo.title)
        .iosNavigationBarTitleDisplayModeInline()
        .onAppear {
            loadEpisodeModels()
        }
        .refreshable {
            await refreshPodcast()
        }
        .confirmationDialog(
            "Delete Download",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let episode = episodeToDelete {
                    deleteDownload(episode)
                }
                episodeToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                episodeToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete this downloaded episode? You can download it again later.")
        }
    }

    // MARK: - Helper Methods

    private func makeEpisodeKey(_ episode: PodcastEpisodeInfo) -> String {
        "\(podcastModel.podcastInfo.title)|\(episode.title)"
    }

    private func loadEpisodeModels() {
        let podcastTitle = podcastModel.podcastInfo.title
        let descriptor = FetchDescriptor<EpisodeDownloadModel>(
            predicate: #Predicate { $0.podcastTitle == podcastTitle }
        )

        do {
            let results = try modelContext.fetch(descriptor)
            var models: [String: EpisodeDownloadModel] = [:]
            for model in results {
                models[model.id] = model
            }
            episodeModels = models
        } catch {
            print("Failed to load episode models: \(error)")
        }
    }

    private func refreshPodcast() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let updatedPodcast = try await rssService.fetchPodcast(from: podcastModel.podcastInfo.rssUrl)
            await MainActor.run {
                podcastModel.podcastInfo = updatedPodcast
                try? modelContext.save()
            }
        } catch {
            print("Failed to refresh podcast: \(error)")
        }
    }

    private func toggleStar(for episode: PodcastEpisodeInfo) {
        let key = makeEpisodeKey(episode)
        if let model = episodeModels[key] {
            model.isStarred.toggle()
            try? modelContext.save()
        } else {
            guard let audioURL = episode.audioURL else { return }
            let model = EpisodeDownloadModel(
                episodeTitle: episode.title,
                podcastTitle: podcastModel.podcastInfo.title,
                audioURL: audioURL,
                imageURL: episode.imageURL ?? podcastModel.podcastInfo.imageURL,
                pubDate: episode.pubDate
            )
            model.isStarred = true
            modelContext.insert(model)
            try? modelContext.save()
            episodeModels[key] = model
        }
    }

    private func downloadEpisode(_ episode: PodcastEpisodeInfo) {
        downloadManager.downloadEpisode(episode: episode, podcastTitle: podcastModel.podcastInfo.title)
    }

    private func deleteDownload(_ episode: PodcastEpisodeInfo) {
        downloadManager.deleteDownload(episodeTitle: episode.title, podcastTitle: podcastModel.podcastInfo.title)
    }
}

// MARK: - Episode Row View

struct EpisodeRowView: View {
    let episode: PodcastEpisodeInfo
    let podcastTitle: String
    let fallbackImageURL: String?
    @ObservedObject var downloadManager: DownloadManager
    let episodeModel: EpisodeDownloadModel?
    let onToggleStar: () -> Void
    let onDownload: () -> Void
    let onDeleteRequested: () -> Void

    private var audioManager: EnhancedAudioManager { EnhancedAudioManager.shared }

    private var downloadState: DownloadState {
        downloadManager.getDownloadState(episodeTitle: episode.title, podcastTitle: podcastTitle)
    }

    private var isDownloaded: Bool {
        if case .downloaded = downloadState {
            return true
        }
        return false
    }

    private var isStarred: Bool {
        episodeModel?.isStarred ?? false
    }

    private var isCompleted: Bool {
        episodeModel?.isCompleted ?? false
    }

    private var playbackProgress: Double {
        episodeModel?.progress ?? 0
    }

    private var isPlayingThisEpisode: Bool {
        guard let currentEpisode = audioManager.currentEpisode else { return false }
        return currentEpisode.title == episode.title && currentEpisode.podcastTitle == podcastTitle
    }

    private var playbackURL: String {
        if case .downloaded(let path) = downloadState {
            return "file://" + path
        }
        return episode.audioURL ?? ""
    }

    /// Duration text - show remaining time if partially played, otherwise full duration
    private var durationText: String? {
        if let model = episodeModel, model.duration > 0 && model.progress > 0 && model.progress < 1 {
            // Show remaining time
            let remaining = model.duration - model.lastPlaybackPosition
            return formatDuration(Int(remaining))
        }
        // Show full duration from episode
        return episode.formattedDuration
    }

    private var episodeImageURL: String {
        episode.imageURL ?? fallbackImageURL ?? ""
    }

    /// Get plain text description (strip HTML tags)
    private var plainDescription: String? {
        guard let desc = episode.podcastEpisodeDescription else { return nil }
        // Simple HTML tag removal
        let stripped = desc.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    var body: some View {
        NavigationLink(destination: EpisodeDetailView(
            episode: episode,
            podcastTitle: podcastTitle,
            fallbackImageURL: fallbackImageURL
        )) {
            HStack(alignment: .top, spacing: 12) {
                // Episode thumbnail
                if let url = URL(string: episodeImageURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            Color.gray
                        case .empty:
                            Color.gray.opacity(0.3)
                        @unknown default:
                            Color.gray
                        }
                    }
                    .frame(width: 80, height: 80)
                    .cornerRadius(8)
                    .clipped()
                } else {
                    Color.gray
                        .frame(width: 80, height: 80)
                        .cornerRadius(8)
                }

                // Episode info
                VStack(alignment: .leading, spacing: 4) {
                    // Date and indicators row
                    HStack(spacing: 4) {
                        if let date = episode.pubDate {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        if isStarred {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.yellow)
                        }

                        if isDownloaded {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.green)
                        }
                    }

                    // Title
                    Text(episode.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .foregroundColor(.primary)

                    // Description
                    if let description = plainDescription {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    // Play button with duration badge
                    HStack(spacing: 8) {
                        // Duration badge with play button
                        Button(action: playAction) {
                            HStack(spacing: 4) {
                                // Play/Pause/Completed icon
                                if isCompleted {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                } else if isPlayingThisEpisode && audioManager.isPlaying {
                                    Image(systemName: "pause.fill")
                                        .font(.system(size: 10))
                                } else {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 10))
                                }

                                // Progress bar (if partially played)
                                if playbackProgress > 0 && playbackProgress < 1 {
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule()
                                                .fill(Color.gray.opacity(0.3))
                                                .frame(height: 3)
                                            Capsule()
                                                .fill(Color.blue)
                                                .frame(width: geo.size.width * playbackProgress, height: 3)
                                        }
                                    }
                                    .frame(width: 30, height: 3)
                                }

                                // Duration text
                                if let duration = durationText {
                                    Text(duration)
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                }
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.15))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.borderless)
                        .disabled(episode.audioURL == nil)

                        // Download progress indicator
                        if case .downloading(let progress) = downloadState {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.5)
                                Text("\(Int(progress * 100))%")
                                    .font(.caption2)
                            }
                            .foregroundColor(.orange)
                        }

                        Spacer()
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .contextMenu {
            Button(action: onToggleStar) {
                Label(
                    isStarred ? "Unstar" : "Star",
                    systemImage: isStarred ? "star.fill" : "star"
                )
            }

            Divider()

            if isDownloaded {
                Button(role: .destructive, action: onDeleteRequested) {
                    Label("Delete Download", systemImage: "trash")
                }
            } else if case .downloading = downloadState {
                Button(action: {
                    downloadManager.cancelDownload(episodeTitle: episode.title, podcastTitle: podcastTitle)
                }) {
                    Label("Cancel Download", systemImage: "xmark.circle")
                }
            } else {
                Button(action: onDownload) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .disabled(episode.audioURL == nil)
            }

            if let audioURL = episode.audioURL, let url = URL(string: audioURL) {
                Divider()
                Button(action: {
                    let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootVC = windowScene.windows.first?.rootViewController {
                        rootVC.present(activityVC, animated: true)
                    }
                }) {
                    Label("Share Episode", systemImage: "square.and.arrow.up")
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if isDownloaded {
                Button(role: .destructive, action: onDeleteRequested) {
                    Label("Delete", systemImage: "trash")
                }
            } else if case .downloading = downloadState {
                Button(action: {
                    downloadManager.cancelDownload(episodeTitle: episode.title, podcastTitle: podcastTitle)
                }) {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .tint(.orange)
            } else if episode.audioURL != nil {
                Button(action: onDownload) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .tint(.blue)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: onToggleStar) {
                Label(isStarred ? "Unstar" : "Star", systemImage: isStarred ? "star.slash" : "star.fill")
            }
            .tint(.yellow)
        }
    }

    private func playAction() {
        guard episode.audioURL != nil else { return }

        let imageURL = episode.imageURL ?? fallbackImageURL ?? ""

        let playbackEpisode = PlaybackEpisode(
            id: "\(podcastTitle)|\(episode.title)",
            title: episode.title,
            podcastTitle: podcastTitle,
            audioURL: playbackURL,
            imageURL: imageURL
        )

        let startTime = episodeModel?.lastPlaybackPosition ?? 0
        let useDefaultSpeed = startTime == 0

        audioManager.play(
            episode: playbackEpisode,
            audioURL: playbackURL,
            startTime: startTime,
            imageURL: imageURL,
            useDefaultSpeed: useDefaultSpeed
        )
    }
}

//#Preview {
//    EpisodeListView(podcastModel: new PodcastInfoModel)
//}
