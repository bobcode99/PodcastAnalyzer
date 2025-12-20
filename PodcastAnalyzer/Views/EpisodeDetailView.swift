//
//  EpisodeDetailView.swift
//  PodcastAnalyzer
//
//  Redesigned with tabs (Summary, Transcript, Keywords) and action buttons
//

import SwiftUI
import SwiftData

struct EpisodeDetailView: View {
    @State private var viewModel: EpisodeDetailViewModel
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab = 0
    @State private var showCopySuccess = false
    @State private var showDeleteConfirmation = false

    init(episode: PodcastEpisodeInfo, podcastTitle: String, fallbackImageURL: String?) {
        _viewModel = State(initialValue: EpisodeDetailViewModel(
            episode: episode,
            podcastTitle: podcastTitle,
            fallbackImageURL: fallbackImageURL
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header with Episode Info
            headerSection

            Divider()

            // MARK: - Tab Selector
            tabSelector

            Divider()

            // MARK: - Tab Content
            TabView(selection: $selectedTab) {
                summaryTab
                    .tag(0)

                transcriptTab
                    .tag(1)

                keywordsTab
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationTitle("Episode Detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    // Share button
                    Button(action: {
                        viewModel.shareEpisode()
                    }) {
                        Image(systemName: "square.and.arrow.up")
                    }

                    // Translate button (placeholder)
                    Button(action: {
                        viewModel.translateDescription()
                    }) {
                        Image(systemName: "character.bubble")
                    }

                    // More menu
                    Menu {
                        Button(action: {
                            viewModel.toggleStar()
                        }) {
                            Label(
                                viewModel.isStarred ? "Unstar" : "Star",
                                systemImage: viewModel.isStarred ? "star.fill" : "star"
                            )
                        }

                        Button(action: {
                            viewModel.addToList()
                        }) {
                            Label("Add to List", systemImage: "plus")
                        }

                        if !viewModel.hasLocalAudio {
                            Button(action: {
                                viewModel.downloadAudio()
                            }) {
                                Label("Download Audio", systemImage: "arrow.down.circle")
                            }
                        }

                        Button(action: {
                            viewModel.reportIssue()
                        }) {
                            Label("Report Issue", systemImage: "exclamationmark.triangle")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        .alert("Copied", isPresented: $showCopySuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Transcript copied to clipboard")
        }
        .confirmationDialog(
            "Delete Download",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                viewModel.deleteDownload()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this downloaded episode? You can download it again later.")
        }
        .onAppear {
            viewModel.setModelContext(modelContext)
            viewModel.checkTranscriptStatus()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                // Artwork (no play overlay)
                if let url = URL(string: viewModel.imageURLString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                        case .failure:
                            Color.gray
                        case .empty:
                            ProgressView()
                        @unknown default:
                            Color.gray
                        }
                    }
                    .frame(width: 80, height: 80)
                    .cornerRadius(10)
                    .shadow(radius: 2)
                } else {
                    Color.gray.frame(width: 80, height: 80).cornerRadius(10)
                }

                // Episode info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(viewModel.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(2)

                        if viewModel.isStarred {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.yellow)
                        }
                    }

                    Text(viewModel.podcastTitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    if let dateString = viewModel.pubDateString {
                        Text(dateString)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    // Progress indicator
                    if viewModel.playbackProgress > 0 && viewModel.playbackProgress < 1 {
                        VStack(alignment: .leading, spacing: 2) {
                            ProgressView(value: viewModel.playbackProgress)
                                .tint(.blue)
                            if let remaining = viewModel.remainingTimeString {
                                Text(remaining)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Spacer()
            }

            // Action buttons row (Play + Download) - compact
            HStack(spacing: 8) {
                // Play button (compact)
                Button(action: {
                    viewModel.playAction()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.isPlayingThisEpisode && viewModel.audioManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12))
                        Text(viewModel.isPlayingThisEpisode && viewModel.audioManager.isPlaying ? "Pause" : "Play")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isPlayDisabled)

                // Download button (compact)
                downloadButton

                Spacer()
            }

            // Playback mode indicator
            if !viewModel.hasLocalAudio && viewModel.audioURL != nil {
                HStack(spacing: 4) {
                    Image(systemName: "wifi")
                        .font(.caption2)
                    Text("Streaming")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Download Button (compact)

    @ViewBuilder
    private var downloadButton: some View {
        switch viewModel.downloadState {
        case .notDownloaded:
            Button(action: {
                viewModel.startDownload()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 12))
                    Text("Download")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)

        case .downloading(let progress):
            Button(action: {
                viewModel.cancelDownload()
            }) {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(.orange)

        case .downloaded:
            Button(action: {
                showDeleteConfirmation = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                    Text("Downloaded")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(.green)

        case .failed:
            Button(action: {
                viewModel.startDownload()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 12))
                    Text("Retry")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 0) {
            TabButton(title: "Summary", isSelected: selectedTab == 0) {
                withAnimation {
                    selectedTab = 0
                }
            }

            TabButton(title: "Transcript", isSelected: selectedTab == 1) {
                withAnimation {
                    selectedTab = 1
                }
            }

            TabButton(title: "Keywords", isSelected: selectedTab == 2) {
                withAnimation {
                    selectedTab = 2
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Summary Tab

    private var summaryTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Episode description
                viewModel.descriptionView
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }

    // MARK: - Transcript Tab

    private var transcriptTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Status section
                transcriptStatusSection

                // Transcript content
                if viewModel.hasTranscript {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Transcript")
                                .font(.headline)
                            Spacer()

                            Button(action: {
                                viewModel.copyTranscriptToClipboard()
                                showCopySuccess = true
                            }) {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }

                        Text(viewModel.cleanTranscriptText)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    @ViewBuilder
    private var transcriptStatusSection: some View {
        VStack(spacing: 16) {
            switch viewModel.transcriptState {
            case .idle:
                if viewModel.hasLocalAudio {
                    VStack(spacing: 12) {
                        Image(systemName: "waveform")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)

                        Text("Ready to Generate Transcript")
                            .font(.headline)

                        if !viewModel.isModelReady {
                            Text("Speech recognition model will be downloaded on first use")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        Button(action: {
                            viewModel.generateTranscript()
                        }) {
                            Label("Generate Transcript", systemImage: "text.bubble")
                                .font(.subheadline)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("No transcript available")
                            .font(.headline)

                        Text("Download the episode to generate a transcript.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

            case .downloadingModel(let progress):
                VStack(spacing: 12) {
                    ProgressView(value: progress)
                        .frame(width: 200)

                    Text("Downloading Speech Model")
                        .font(.headline)

                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            case .transcribing(let progress):
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.5)

                    Text("Generating Transcript...")
                        .font(.headline)

                    if progress > 0 {
                        Text("Processing audio...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

            case .completed:
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.green)

                    Text("Transcript Generated")
                        .font(.headline)

                    Button(action: {
                        viewModel.generateTranscript()
                    }) {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }

            case .error(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.red)

                    Text("Error")
                        .font(.headline)

                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button(action: {
                        viewModel.generateTranscript()
                    }) {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Keywords Tab

    private var keywordsTab: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "tag")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)

                Text("Keywords")
                    .font(.headline)

                Text("Keyword extraction coming soon.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }

    // MARK: - Download Status Badge

    @ViewBuilder
    private var downloadStatusBadge: some View {
        switch viewModel.downloadState {
        case .downloaded:
            Label("Downloaded", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
        case .downloading(let progress):
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("\(Int(progress * 100))%")
            }
            .font(.caption)
            .foregroundColor(.blue)
        default:
            EmptyView()
        }
    }
}

// MARK: - Tab Button Component

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? .blue : .secondary)

                Rectangle()
                    .fill(isSelected ? Color.blue : Color.clear)
                    .frame(height: 2)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
