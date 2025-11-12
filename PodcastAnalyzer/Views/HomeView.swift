import SwiftUI
import SwiftData


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
                } else if viewModel.podcastFeeds.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "podcast")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("Welcome to Podcast Analyzer")
                            .font(.headline)
                        Text("Add RSS feeds in Settings to get started")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                } else {
                    List(viewModel.podcastFeeds, id: \.id) { feed in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(feed.title ?? "Podcast Feed")
                                .font(.headline)
                            Text(feed.rssUrl)
                                .font(.caption)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                }
                
                Spacer()
            }
            .navigationTitle("Podcasts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        viewModel.loadPodcasts()
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .onAppear {
            viewModel.setModelContext(modelContext)
            viewModel.loadPodcasts()
        }
    }
}
