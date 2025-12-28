import SwiftData
import SwiftUI
import ZMarkupParser

struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel
    @Environment(\.modelContext) private var modelContext

    init() {
        _viewModel = StateObject(wrappedValue: HomeViewModel(modelContext: nil))
    }

    var body: some View {
        NavigationStack {
            VStack {
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                } else if let error = viewModel.error {
                    VStack {
                        Image(systemName: "exclamationmark.circle")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text("Error")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                } else if viewModel.podcastInfoModelList.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "apple.podcasts.pages.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("Welcome to Podcast Analyzer")
                            .font(.headline)
                        Text("Add RSS feeds in Settings to get started")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                } else {
                    List(viewModel.podcastInfoModelList) { model in
                        NavigationLink(destination: EpisodeListView(podcastModel: model)) {
                            PodcastRowView(podcast: model.podcastInfo)
                        }
                    }
                }

                Spacer()
            }
            .navigationTitle("Podcasts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        Task {
                            await viewModel.refreshAllPodcasts()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .toolbarTitleDisplayMode(.inlineLarge)
            .refreshable {
                await viewModel.refreshAllPodcasts()
            }

        }
        .onAppear {
            viewModel.setModelContext(modelContext)
            viewModel.loadPodcasts()
        }
    }
}

// MARK: - Podcast Row View with HTML Description

struct PodcastRowView: View {
    let podcast: PodcastInfo
    @State private var descriptionView: AnyView?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(podcast.title)
                .font(.headline)

            if let view = descriptionView {
                view
                    .lineLimit(2)
            } else if let description = podcast.podcastInfoDescription {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(2)
            }

            Text("\(podcast.episodes.count) episodes")
                .font(.caption2)
                .foregroundColor(.blue)
        }
        .padding(.vertical, 4)
        .onAppear {
            parseDescription()
        }
    }

    private func parseDescription() {
        guard let html = podcast.podcastInfoDescription, !html.isEmpty else { return }

        let rootStyle = MarkupStyle(
            font: MarkupStyleFont(size: 12),
            foregroundColor: MarkupStyleColor(color: UIColor.secondaryLabel)
        )

        let parser = ZHTMLParserBuilder.initWithDefault()
            .set(rootStyle: rootStyle)
            .build()

        Task {
            let attributedString = parser.render(html)

            await MainActor.run {
                descriptionView = AnyView(
                    HTMLTextView(attributedString: attributedString)
                )
            }
        }
    }
}

#Preview {
    HomeView()
}
