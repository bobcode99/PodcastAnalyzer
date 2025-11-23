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
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Add RSS Feed")
                    .font(.headline)
                
                HStack(spacing: 10) {
                    TextField("Paste RSS feed URL", text: $viewModel.rssUrlInput)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .textCase(nil)
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
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Your RSS Feeds")
                    .font(.headline)
                
                if viewModel.podcastFeeds.isEmpty {
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
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.podcastFeeds, id: \.id) { feed in
                            HStack(spacing: 12) {
                                if let urlString = feed.imageUrl, let url = URL(string: urlString), !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .empty:
                                            // Placeholder while loading
                                            ZStack {
                                                Color.clear
                                                ProgressView()
                                            }
                                            .frame(width: 48, height: 48)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 48, height: 48)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                        case .failure:
                                            Image(systemName: "apple.podcasts.pages.fill")
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 48, height: 48)
                                                .foregroundColor(.purple)
                                        @unknown default:
                                            Image(systemName: "apple.podcasts.pages.fill")
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 48, height: 48)
                                                .foregroundColor(.purple)
                                        }
                                    }.onAppear {
                                        print("Image loading from URL: \(urlString)")
                                    }
                                } else {
                                    // No URL available: show fallback immediately
                                    Image(systemName: "apple.podcasts.pages.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 48, height: 48)
                                        .foregroundColor(.purple)
                                }
                                                               
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(feed.title ?? "Untitled Feed")
                                        .font(.body)
                                        .fontWeight(.semibold)
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
                                .help("Delete feed")
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
#if os(macOS)
                            .background(Color(nsColor: NSColor.controlBackgroundColor))
#else
                            .background(Color(uiColor: UIColor.secondarySystemBackground))
#endif
                            .cornerRadius(6)
                        }
                    }
                    .padding(.vertical, 8)
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

#Preview {
    SettingsView()
}
