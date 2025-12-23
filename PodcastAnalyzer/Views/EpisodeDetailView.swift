//
//  EpisodeDetailView.swift
//  PodcastAnalyzer
//
//  Fixed: Added Regenerate option to live view and fixed state visibility
//

import Combine
import Foundation
import SwiftData
import SwiftUI

struct EpisodeDetailView: View {
    @State private var viewModel: EpisodeDetailViewModel
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab = 0
    @State private var showCopySuccess = false
    @State private var showDeleteConfirmation = false

    // Timer to refresh transcript highlighting during playback
    @State private var refreshTrigger = false
    let playbackTimer = Timer.publish(every: 0.5, on: .main, in: .common)
        .autoconnect()

    init(
        episode: PodcastEpisodeInfo,
        podcastTitle: String,
        fallbackImageURL: String?,
        podcastLanguage: String = "en"
    ) {
        _viewModel = State(
            initialValue: EpisodeDetailViewModel(
                episode: episode,
                podcastTitle: podcastTitle,
                fallbackImageURL: fallbackImageURL,
                podcastLanguage: podcastLanguage
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            tabSelector
            Divider()

            TabView(selection: $selectedTab) {
                summaryTab.tag(0)
                transcriptTab.tag(1)
                keywordsTab.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button(action: { viewModel.translateDescription() }) {
                        Image(systemName: "character.bubble")
                    }
                    Menu {
                        EpisodeMenuActions(
                            isStarred: viewModel.isStarred,
                            isCompleted: viewModel.isCompleted,
                            hasLocalAudio: viewModel.hasLocalAudio,
                            downloadState: viewModel.downloadState,
                            audioURL: viewModel.audioURL,
                            onToggleStar: { viewModel.toggleStar() },
                            onTogglePlayed: { viewModel.togglePlayed() },
                            onDownload: { viewModel.startDownload() },
                            onCancelDownload: { viewModel.cancelDownload() },
                            onDeleteDownload: { showDeleteConfirmation = true },
                            onShare: { viewModel.shareEpisode() },
                            onPlayNext: { viewModel.addToPlayNext() }
                        )

                        Divider()

                        Button(action: { viewModel.reportIssue() }) {
                            Label(
                                "Report Issue",
                                systemImage: "exclamationmark.triangle"
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .alert("Copied", isPresented: $showCopySuccess) {
            Button("OK", role: .cancel) {}
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
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Are you sure you want to delete this downloaded episode? You can download it again later."
            )
        }
        .onAppear {
            viewModel.setModelContext(modelContext)
            viewModel.checkTranscriptStatus()
        }
    }

    // MARK: - Header Section (Updated)
    private var headerSection: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                // Artwork
                if let url = URL(string: viewModel.imageURLString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                        case .failure: Color.gray
                        case .empty: ProgressView()
                        @unknown default: Color.gray
                        }
                    }
                    .frame(width: 80, height: 80)
                    .cornerRadius(10)
                    .shadow(radius: 2)
                } else {
                    Color.gray.frame(width: 80, height: 80).cornerRadius(10)
                }

                VStack(alignment: .leading, spacing: 6) {
                    // FULL TITLE – no lineLimit, multiline, selectable
                    Text(viewModel.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)  // Can select and copy
                        .fixedSize(horizontal: false, vertical: true)  // Allows wrapping

                    HStack(spacing: 4) {
                        if viewModel.isStarred {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.yellow)
                        }
                        Text(viewModel.podcastTitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .textSelection(.enabled)

                    if let dateString = viewModel.pubDateString {
                        Text(dateString)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    // NEW: Status indicators (like badges in a web UI)
                    HStack(spacing: 12) {
                        // Downloaded status
                        HStack(spacing: 4) {
                            Image(
                                systemName: viewModel.hasLocalAudio
                                    ? "checkmark.circle.fill" : "circle"
                            )
                            .foregroundColor(
                                viewModel.hasLocalAudio ? .green : .secondary
                            )
                            Text(
                                viewModel.hasLocalAudio
                                    ? "Downloaded" : "Not Downloaded"
                            )
                            .font(.caption2)
                        }

                        // Transcript status
                        HStack(spacing: 4) {
                            switch viewModel.transcriptState {
                            case .idle, .error:
                                Image(
                                    systemName: viewModel.hasTranscript
                                        ? "checkmark.circle.fill" : "circle"
                                )
                                .foregroundColor(
                                    viewModel.hasTranscript
                                        ? .green : .secondary
                                )
                                Text(
                                    viewModel.hasTranscript
                                        ? "Transcript Ready" : "No Transcript"
                                )
                                .font(.caption2)
                            case .downloadingModel:
                                ProgressView().scaleEffect(0.8)
                                Text("Downloading Model...")
                                    .font(.caption2)
                            case .transcribing:
                                ProgressView().scaleEffect(0.8)
                                Text("Transcribing...")
                                    .font(.caption2)
                            case .completed:
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Transcript Ready")
                                    .font(.caption2)
                            }
                        }
                    }
                    .foregroundColor(.secondary)

                    // Playback progress (unchanged)
                    if viewModel.playbackProgress > 0
                        && viewModel.playbackProgress < 1
                    {
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

            // Play + Download buttons (unchanged)
            HStack(spacing: 8) {
                Button(action: { viewModel.playAction() }) {
                    HStack(spacing: 4) {
                        Image(
                            systemName: viewModel.isPlayingThisEpisode
                                && viewModel.audioManager.isPlaying
                                ? "pause.fill" : "play.fill"
                        )
                        .font(.system(size: 12))
                        Text(
                            viewModel.isPlayingThisEpisode
                                && viewModel.audioManager.isPlaying
                                ? "Pause" : "Play"
                        )
                        .font(.caption)
                        .fontWeight(.medium)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isPlayDisabled)

                downloadButton
                Spacer()
            }

            if !viewModel.hasLocalAudio && viewModel.audioURL != nil {
                HStack(spacing: 4) {
                    Image(systemName: "wifi")
                    Text("Streaming")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
    // MARK: - Download Button
    @ViewBuilder
    private var downloadButton: some View {
        switch viewModel.downloadState {
        case .notDownloaded:
            Button(action: { viewModel.startDownload() }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle").font(
                        .system(size: 12)
                    )
                    Text("Download").font(.caption).fontWeight(.medium)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
        case .downloading(let progress):
            Button(action: { viewModel.cancelDownload() }) {
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.6)
                    Text("\(Int(progress * 100))%").font(.caption).fontWeight(
                        .medium
                    )
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .buttonStyle(.bordered).tint(.orange)
        case .finishing:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.6)
                Text("Saving...").font(.caption).fontWeight(.medium)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
            )
        case .downloaded:
            Button(action: { showDeleteConfirmation = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").font(
                        .system(size: 12)
                    )
                    Text("Downloaded").font(.caption).fontWeight(.medium)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .buttonStyle(.bordered).tint(.green)
        case .failed:
            Button(action: { viewModel.startDownload() }) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle").font(
                        .system(size: 12)
                    )
                    Text("Retry").font(.caption).fontWeight(.medium)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .buttonStyle(.bordered).tint(.red)
        }
    }

    // MARK: - Tab Selector
    private var tabSelector: some View {
        HStack(spacing: 0) {
            TabButton(title: "Summary", isSelected: selectedTab == 0) {
                withAnimation { selectedTab = 0 }
            }
            TabButton(title: "Transcript", isSelected: selectedTab == 1) {
                withAnimation { selectedTab = 1 }
            }
            TabButton(title: "Keywords", isSelected: selectedTab == 2) {
                withAnimation { selectedTab = 2 }
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Summary Tab
    private var summaryTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                viewModel.descriptionView
                    .textSelection(.enabled)
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }

    // MARK: - Transcript Tab (FIXED)
    private var transcriptTab: some View {
        VStack(spacing: 0) {
            if viewModel.isTranscriptProcessing {
                // Case 1: Active Processing (Always show this if happening)
                transcriptStatusSection
            } else if viewModel.hasTranscript {
                // Case 2: Transcript exists and we are idle
                liveCaptionsView
            } else {
                // Case 3: No transcript, idle or error
                ScrollView {
                    transcriptStatusSection
                        .padding(.vertical)
                }
            }
        }
        .onReceive(playbackTimer) { _ in
            if viewModel.isPlayingThisEpisode { refreshTrigger.toggle() }
        }
    }

    // MARK: - Live Captions View (FIXED)
    private var liveCaptionsView: some View {
        VStack(spacing: 0) {
            // Header with search and Options
            VStack(spacing: 12) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(
                        .secondary
                    )
                    TextField(
                        "Search transcript...",
                        text: $viewModel.transcriptSearchQuery
                    )
                    .textFieldStyle(.plain)
                    if !viewModel.transcriptSearchQuery.isEmpty {
                        Button(action: { viewModel.transcriptSearchQuery = "" })
                        {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)

                // Stats and actions row
                HStack {
                    Text(
                        "\(viewModel.filteredTranscriptSegments.count) segments"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)

                    Spacer()

                    // FIXED: Replaced single "Copy" button with a Menu including Regenerate
                    Menu {
                        Button(action: {
                            viewModel.copyTranscriptToClipboard()
                            showCopySuccess = true
                        }) {
                            Label("Copy All", systemImage: "doc.on.doc")
                        }

                        Divider()

                        Button(
                            role: .destructive,
                            action: {
                                viewModel.generateTranscript()
                            }
                        ) {
                            Label(
                                "Regenerate Transcript",
                                systemImage: "arrow.clockwise"
                            )
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Options")
                            Image(systemName: "chevron.down")
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)

            Divider().padding(.top, 12)

            // Scrollable transcript segments
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.filteredTranscriptSegments) {
                            segment in
                            TranscriptSegmentRow(
                                segment: segment,
                                isCurrentSegment: viewModel.currentSegmentId
                                    == segment.id,
                                searchQuery: viewModel.transcriptSearchQuery,
                                onTap: { viewModel.seekToSegment(segment) }
                            )
                            .id(segment.id)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: viewModel.currentSegmentId) { _, newId in
                    if let id = newId, viewModel.transcriptSearchQuery.isEmpty {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Transcript Status Section
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
                        Text("Ready to Generate Transcript").font(.headline)
                        if !viewModel.isModelReady {
                            Text(
                                "Speech recognition model will be downloaded on first use"
                            )
                            .font(.caption).foregroundColor(.secondary)
                            .multilineTextAlignment(
                                .center
                            )
                        }
                        Button(action: { viewModel.generateTranscript() }) {
                            Label(
                                "Generate Transcript",
                                systemImage: "text.bubble"
                            )
                            .font(.subheadline)
                            .padding(.horizontal, 20).padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "text.bubble").font(.system(size: 48))
                            .foregroundColor(
                                .secondary
                            )
                        Text("No transcript available").font(.headline)
                        Text("Download the episode to generate a transcript.")
                            .font(.subheadline).foregroundColor(.secondary)
                            .multilineTextAlignment(
                                .center
                            )
                    }
                }

            case .downloadingModel(let progress):
                VStack(spacing: 12) {
                    ProgressView(value: progress).frame(width: 200)
                    Text("Downloading Speech Model").font(.headline)
                    Text("\(Int(progress * 100))%").font(.caption)
                        .foregroundColor(.secondary)
                }

            case .transcribing(let progress):
                VStack(spacing: 12) {
                    // Show progress bar with percentage
                    ProgressView(value: progress)
                        .frame(width: 200)
                        .tint(.blue)

                    Text("Generating Transcript...").font(.headline)

                    Text("\(Int(progress * 100))%")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)

                    Text("Processing audio...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            case .completed:
                // This state is briefly visible or used if transcript is empty
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill").font(
                        .system(size: 50)
                    )
                    .foregroundColor(.green)
                    Text("Transcript Generated").font(.headline)
                    Button(action: { viewModel.generateTranscript() }) {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }

            case .error(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").font(
                        .system(size: 50)
                    )
                    .foregroundColor(.red)
                    Text("Error").font(.headline)
                    Text(message).font(.caption).foregroundColor(.secondary)
                        .multilineTextAlignment(
                            .center
                        )
                    Button(action: { viewModel.generateTranscript() }) {
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
                Image(systemName: "tag").font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("Keywords").font(.headline)
                Text("Keyword extraction coming soon.")
                    .font(.subheadline).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
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

// MARK: - Transcript Segment Row Component

struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment
    let isCurrentSegment: Bool
    let searchQuery: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                // Timestamp
                Text(segment.formattedStartTime)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isCurrentSegment ? .white : .blue)
                    .frame(width: 50, alignment: .leading)

                // Text content with highlighted search terms
                highlightedText
                    .font(.body)
                    .foregroundColor(isCurrentSegment ? .white : .primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                // Play indicator for current segment
                if isCurrentSegment {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isCurrentSegment ? Color.blue : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var highlightedText: some View {
        if searchQuery.isEmpty {
            Text(segment.text)
        } else {
            highlightMatches(in: segment.text, query: searchQuery)
        }
    }

    private func highlightMatches(in text: String, query: String) -> Text {
        let lowercasedText = text.lowercased()
        let lowercasedQuery = query.lowercased()

        guard let range = lowercasedText.range(of: lowercasedQuery) else {
            return Text(text)
        }

        let startIndex = text.distance(
            from: text.startIndex,
            to: range.lowerBound
        )
        let endIndex = text.distance(
            from: text.startIndex,
            to: range.upperBound
        )

        let before = String(text.prefix(startIndex))
        let match = String(
            text[
                text.index(
                    text.startIndex,
                    offsetBy: startIndex
                )..<text.index(
                    text.startIndex,
                    offsetBy: endIndex
                )
            ]
        )
        let after = String(text.suffix(text.count - endIndex))

        // Use AttributedString for highlighting instead of Text concatenation
        var attributedString = AttributedString(before)

        var matchAttributed = AttributedString(match)
        // Apply explicit attributes to avoid type ambiguity
        var attrs = AttributeContainer()
        attrs.foregroundColor = .yellow
        attrs.font = .system(.body, design: .default).bold()
        matchAttributed.mergeAttributes(attrs)
        attributedString.append(matchAttributed)

        // Recursively highlight remaining matches in the "after" portion
        let afterAttributed = highlightMatchesAttributed(
            in: after,
            query: query
        )
        attributedString.append(afterAttributed)

        return Text(attributedString)
    }

    private func highlightMatchesAttributed(in text: String, query: String)
        -> AttributedString
    {
        let lowercasedText = text.lowercased()
        let lowercasedQuery = query.lowercased()

        guard let range = lowercasedText.range(of: lowercasedQuery) else {
            return AttributedString(text)
        }

        let startIndex = text.distance(
            from: text.startIndex,
            to: range.lowerBound
        )
        let endIndex = text.distance(
            from: text.startIndex,
            to: range.upperBound
        )

        let before = String(text.prefix(startIndex))
        let match = String(
            text[
                text.index(
                    text.startIndex,
                    offsetBy: startIndex
                )..<text.index(
                    text.startIndex,
                    offsetBy: endIndex
                )
            ]
        )
        let after = String(text.suffix(text.count - endIndex))

        var attributedString = AttributedString(before)

        var matchAttributed = AttributedString(match)
        var attrs = AttributeContainer()
        attrs.foregroundColor = .yellow
        attrs.font = .system(.body, design: .default).bold()
        matchAttributed.mergeAttributes(attrs)
        attributedString.append(matchAttributed)

        // Recursively highlight remaining matches
        let afterAttributed = highlightMatchesAttributed(
            in: after,
            query: query
        )
        attributedString.append(afterAttributed)

        return attributedString
    }
}

// (Existing Helper Components: TabButton, TranscriptSegmentRow remain unchanged)
