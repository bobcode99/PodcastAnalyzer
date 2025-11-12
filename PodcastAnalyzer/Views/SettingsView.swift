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
                    
                    Button("Add Feed") {
                        viewModel.addRssLink(modelContext: modelContext)
                    }
                    .buttonStyle(.borderedProminent)
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
                    Text("No feeds added yet")
                        .foregroundColor(.gray)
                        .font(.caption)
                } else {
                    List {
                        ForEach(viewModel.podcastFeeds) { feed in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(feed.title ?? feed.rssUrl)
                                        .font(.body)
                                    Text(feed.rssUrl)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    viewModel.removePodcastFeed(feed, modelContext: modelContext)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 300)
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
