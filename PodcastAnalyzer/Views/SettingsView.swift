import SwiftUI
import SwiftData

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @Environment(\.modelContext) var modelContext
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title2)
                .fontWeight(.bold)
            
            // MARK: - Add Feed Section
            VStack(alignment: .leading, spacing: 10) {
                Text("Add RSS Feed")
                    .font(.headline)
                
                HStack(spacing: 10) {
                    TextField("Paste RSS feed URL", text: $viewModel.rssUrlInput)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .disabled(viewModel.isValidating)
                    
                    if viewModel.isValidating {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Button("Add Feed") {
                            viewModel.addRssLink(modelContext: modelContext)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.rssUrlInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                
                if !viewModel.successMessage.isEmpty {
                    Text(viewModel.successMessage)
                        .foregroundColor(.green)
                        .font(.caption)
                }
                
                if !viewModel.errorMessage.isEmpty {
                    Text(viewModel.errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            
            // MARK: - List Feeds Section
            VStack(alignment: .leading, spacing: 10) {
                Text("Your RSS Feeds")
                    .font(.headline)
                
                if viewModel.podcastInfoModelList.isEmpty {
                    VStack(alignment: .center, spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 30))
                            .foregroundColor(.gray)
                        Text("No feeds added yet")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            // 1. FIXED: Removed 'id: \.self'
                            ForEach(viewModel.podcastInfoModelList) { feed in
                                FeedRowView(feed: feed, viewModel: viewModel, modelContext: modelContext)
                            }
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .onAppear {
            viewModel.loadFeeds(modelContext: modelContext)
        }
    }
}

// MARK: - Subview for cleaner code
// Extracting this view fixes type inference issues and makes debugging easier
struct FeedRowView: View {
    let feed: PodcastInfoModel
    @ObservedObject var viewModel: SettingsViewModel
    var modelContext: ModelContext

    var body: some View {
        HStack(spacing: 12) {
            // 2. FIXED: Accessing 'feed.podcastInfo.imageURL'
            if let urlString = feed.podcastInfo.imageURL.isEmpty ? nil : feed.podcastInfo.imageURL,
               let url = URL(string: urlString) {
                
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            Color.gray.opacity(0.2)
                            ProgressView().scaleEffect(0.5)
                        }
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Image(systemName: "apple.podcasts.pages.fill")
                            .resizable().foregroundColor(.purple)
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
            } else {
                // Fallback Image
                Image(systemName: "apple.podcasts.pages.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .foregroundColor(.purple)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                // 3. FIXED: Accessing 'feed.podcastInfo.title'
                Text(feed.podcastInfo.title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                
                // 4. FIXED: Accessing 'feed.podcastInfo.rssUrl'
                Text(feed.podcastInfo.rssUrl)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(action: {
                viewModel.removePodcastFeed(feed, modelContext: modelContext)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(6)
    }
}

#Preview {
    SettingsView()
}
