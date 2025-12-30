//
//  BrowsePodcastView.swift
//  PodcastAnalyzer
//
//  View for browsing podcast episodes without subscribing.
//  Fetches RSS feed and allows playing episodes directly.
//

import Combine
import SwiftData
import SwiftUI

struct BrowsePodcastView: View {
    let podcastName: String
    let podcastArtwork: String
    let artistName: String
    let collectionId: String
    let applePodcastUrl: String?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = BrowsePodcastViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.error {
                errorView(error)
            } else if let podcastInfo = viewModel.podcastInfo {
                episodeListView(podcastInfo)
            } else {
                loadingView
            }
        }
        .navigationTitle(podcastName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let url = applePodcastUrl, let appleURL = URL(string: url) {
                        Link(destination: appleURL) {
                            Label("View on Apple Podcasts", systemImage: "link")
                        }
                    }

                    Divider()

                    Button(action: { viewModel.subscribe(modelContext: modelContext) }) {
                        Label(
                            viewModel.isSubscribed ? "Subscribed" : "Subscribe",
                            systemImage: viewModel.isSubscribed ? "checkmark.circle.fill" : "plus.circle"
                        )
                    }
                    .disabled(viewModel.isSubscribed)

                    Button(action: { Task { await viewModel.refresh() } }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            await viewModel.loadPodcast(
                collectionId: collectionId,
                podcastName: podcastName,
                modelContext: modelContext
            )
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 20) {
            // Artwork preview
            AsyncImage(url: URL(string: podcastArtwork.replacingOccurrences(of: "100x100", with: "300x300"))) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    Color.gray
                }
            }
            .frame(width: 150, height: 150)
            .cornerRadius(12)

            Text(podcastName)
                .font(.headline)

            ProgressView("Loading episodes...")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)

            Text("Unable to load podcast")
                .font(.headline)

            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Try Again") {
                Task {
                    await viewModel.loadPodcast(
                        collectionId: collectionId,
                        podcastName: podcastName,
                        modelContext: modelContext
                    )
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Episode List View

    private func episodeListView(_ podcastInfo: PodcastInfo) -> some View {
        List {
            // Header Section
            Section {
                headerSection(podcastInfo)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            // Episodes Section
            Section {
                ForEach(podcastInfo.episodes) { episode in
                    BrowseEpisodeRow(
                        episode: episode,
                        podcastTitle: podcastInfo.title,
                        podcastImageURL: podcastInfo.imageURL,
                        podcastLanguage: podcastInfo.language
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }
            } header: {
                Text("Episodes (\(podcastInfo.episodes.count))")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Header Section

    private func headerSection(_ podcastInfo: PodcastInfo) -> some View {
        VStack(spacing: 16) {
            // Artwork
            AsyncImage(url: URL(string: podcastInfo.imageURL)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    Color.gray
                }
            }
            .frame(width: 180, height: 180)
            .cornerRadius(16)
            .shadow(radius: 8)

            // Title and Artist
            VStack(spacing: 4) {
                Text(podcastInfo.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(artistName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Subscribe Button
            Button(action: { viewModel.subscribe(modelContext: modelContext) }) {
                HStack {
                    Image(systemName: viewModel.isSubscribed ? "checkmark.circle.fill" : "plus.circle.fill")
                    Text(viewModel.isSubscribed ? "Subscribed" : "Subscribe")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(viewModel.isSubscribed ? Color.green : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(viewModel.isSubscribed)
            .padding(.horizontal, 40)

            // View on Apple Podcasts
            if let url = applePodcastUrl, let appleURL = URL(string: url) {
                Link(destination: appleURL) {
                    Label("View on Apple Podcasts", systemImage: "link")
                        .font(.subheadline)
                }
            }
        }
        .padding()
    }
}

// MARK: - Browse Episode Row

struct BrowseEpisodeRow: View {
    let episode: PodcastEpisodeInfo
    let podcastTitle: String
    let podcastImageURL: String
    let podcastLanguage: String

    private var audioManager: EnhancedAudioManager { EnhancedAudioManager.shared }

    private var isCurrentlyPlaying: Bool {
        audioManager.currentEpisode?.audioURL == episode.audioURL && audioManager.isPlaying
    }

    var body: some View {
        NavigationLink(destination: EpisodeDetailView(
            episode: episode,
            podcastTitle: podcastTitle,
            fallbackImageURL: podcastImageURL,
            podcastLanguage: podcastLanguage
        )) {
            HStack(spacing: 12) {
                // Play indicator or artwork
                ZStack {
                    if let imageURL = episode.imageURL ?? podcastImageURL as String?,
                       let url = URL(string: imageURL) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Color.gray
                            }
                        }
                        .frame(width: 56, height: 56)
                        .cornerRadius(8)
                    }

                    if isCurrentlyPlaying {
                        Color.black.opacity(0.4)
                            .frame(width: 56, height: 56)
                            .cornerRadius(8)
                        Image(systemName: "waveform")
                            .foregroundColor(.white)
                            .font(.title3)
                    }
                }

                // Episode info
                VStack(alignment: .leading, spacing: 4) {
                    Text(episode.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .foregroundColor(isCurrentlyPlaying ? .blue : .primary)

                    HStack(spacing: 8) {
                        if let date = episode.pubDate {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let duration = episode.formattedDuration {
                            Text(duration)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // Play button
                Button(action: playEpisode) {
                    Image(systemName: isCurrentlyPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private func playEpisode() {
        guard let audioURL = episode.audioURL else { return }

        if isCurrentlyPlaying {
            audioManager.pause()
        } else {
            let playbackEpisode = PlaybackEpisode(
                id: "\(podcastTitle)\u{1F}\(episode.title)",
                title: episode.title,
                podcastTitle: podcastTitle,
                audioURL: audioURL,
                imageURL: episode.imageURL ?? podcastImageURL,
                episodeDescription: episode.podcastEpisodeDescription,
                pubDate: episode.pubDate,
                duration: episode.duration,
                guid: episode.guid
            )

            audioManager.play(
                episode: playbackEpisode,
                audioURL: audioURL,
                startTime: 0,
                imageURL: episode.imageURL ?? podcastImageURL,
                useDefaultSpeed: true
            )
        }
    }
}

// MARK: - View Model

@MainActor
class BrowsePodcastViewModel: ObservableObject {
    @Published var podcastInfo: PodcastInfo?
    @Published var isLoading = false
    @Published var error: String?
    @Published var isSubscribed = false

    private let applePodcastService = ApplePodcastService()
    private var rssUrl: String?
    private var cancellables = Set<AnyCancellable>()

    func loadPodcast(collectionId: String, podcastName: String, modelContext: ModelContext) async {
        isLoading = true
        error = nil

        // Check if already subscribed
        checkSubscriptionStatus(podcastName: podcastName, modelContext: modelContext)

        // Look up RSS URL from Apple
        applePodcastService.lookupPodcast(collectionId: collectionId)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let err) = completion {
                        Task { @MainActor in
                            self?.isLoading = false
                            self?.error = err.localizedDescription
                        }
                    }
                },
                receiveValue: { [weak self] podcast in
                    guard let feedUrl = podcast?.feedUrl else {
                        Task { @MainActor in
                            self?.isLoading = false
                            self?.error = "No RSS feed available"
                        }
                        return
                    }

                    self?.rssUrl = feedUrl
                    Task {
                        await self?.fetchRSS(from: feedUrl)
                    }
                }
            )
            .store(in: &cancellables)
    }

    private func fetchRSS(from url: String) async {
        do {
            let info = try await RSSCacheService.shared.fetchPodcast(from: url)
            self.podcastInfo = info
            self.isLoading = false
        } catch {
            self.error = error.localizedDescription
            self.isLoading = false
        }
    }

    func refresh() async {
        guard let rssUrl = rssUrl else { return }

        isLoading = true
        do {
            let info = try await RSSCacheService.shared.fetchPodcast(from: rssUrl, forceRefresh: true)
            self.podcastInfo = info
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func subscribe(modelContext: ModelContext) {
        guard let podcastInfo = podcastInfo else { return }

        let model = PodcastInfoModel(podcastInfo: podcastInfo, lastUpdated: Date())
        modelContext.insert(model)

        do {
            try modelContext.save()
            isSubscribed = true
        } catch {
            self.error = "Failed to subscribe: \(error.localizedDescription)"
        }
    }

    private func checkSubscriptionStatus(podcastName: String, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<PodcastInfoModel>(
            predicate: #Predicate { $0.podcastInfo.title == podcastName }
        )

        if let _ = try? modelContext.fetch(descriptor).first {
            isSubscribed = true
        }
    }
}
