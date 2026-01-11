//
//  EpisodeDetailView.swift
//  PodcastAnalyzer
//
//  Fixed: Added Regenerate option to live view and fixed state visibility
//  Fixed: Memory leaks from static timer and proper cleanup on macOS
//

import Combine
import Foundation
import SwiftData
import SwiftUI

#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct EpisodeDetailView: View {
    private var toolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarTrailing
        #else
        return .primaryAction
        #endif
    }
    @State private var viewModel: EpisodeDetailViewModel
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab = 0
    @State private var showCopySuccess = false
    @State private var showDeleteConfirmation = false

    // Timer subscription for transcript highlighting during playback
    @State private var playbackTimerCancellable: AnyCancellable?

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

    /// Destination view for navigating to the podcast's episode list
    @ViewBuilder
    private var podcastDestination: some View {
        // Try to find the podcast model in SwiftData
        let title = viewModel.podcastTitle
        let descriptor = FetchDescriptor<PodcastInfoModel>(
            predicate: #Predicate { $0.podcastInfo.title == title }
        )
        if let podcastModel = try? modelContext.fetch(descriptor).first {
            EpisodeListView(podcastModel: podcastModel)
        } else {
            // Fallback: show an error or navigate with browse mode
            ContentUnavailableView(
                "Podcast Not Found",
                systemImage: "exclamationmark.triangle",
                description: Text("This podcast is not in your library")
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            tabSelector
            Divider()

            #if os(iOS)
            TabView(selection: $selectedTab) {
                summaryTab.tag(0)
                transcriptTab.tag(1)
                keywordsTab.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            #else
            // macOS: Use simple view switching to avoid default tab bar
            Group {
                switch selectedTab {
                case 0: summaryTab
                case 1: transcriptTab
                case 2: keywordsTab
                default: summaryTab
                }
            }
            #endif
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: toolbarPlacement) {
                HStack(spacing: 16) {
                    Button(action: { viewModel.translateDescription() }) {
                        Image(systemName: "translate")
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
        .onDisappear {
            // Clean up timer and subscriptions to prevent memory leaks
            stopPlaybackTimer()
            viewModel.cleanup()
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

                    // Tappable podcast title - navigates to show
                    NavigationLink(destination: podcastDestination) {
                        HStack(spacing: 4) {
                            Text(viewModel.podcastTitle)
                                .font(.caption)
                                .foregroundColor(.blue)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8))
                                .foregroundColor(.blue)
                        }
                    }
                    .buttonStyle(.plain)

                    // Date and status icons row
                    HStack(spacing: 8) {
                        if let dateString = viewModel.pubDateString {
                            Text(dateString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Status icons (same as EpisodeRowView)
                        HStack(spacing: 6) {
                            if viewModel.isStarred {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.yellow)
                            }

                            if viewModel.hasLocalAudio {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.green)
                            }

                            // Transcript status
                            switch viewModel.transcriptState {
                            case .idle, .error:
                                if viewModel.hasTranscript {
                                    Image(systemName: "captions.bubble.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.purple)
                                }
                            case .downloadingModel, .transcribing:
                                HStack(spacing: 2) {
                                    ProgressView().scaleEffect(0.5)
                                }
                            case .completed:
                                Image(systemName: "captions.bubble.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.purple)
                            }

                            // AI Analysis available
                            if viewModel.hasAIAnalysis {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 12))
                                    .foregroundColor(.orange)
                            }

                            if viewModel.isCompleted {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.green)
                            }
                        }
                    }

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

            // Play + Download + AI Analysis buttons
            HStack(spacing: 8) {
                // Play button with progress (using reusable component)
                EpisodePlayButton(
                    isPlaying: viewModel.audioManager.isPlaying,
                    isPlayingThisEpisode: viewModel.isPlayingThisEpisode,
                    isCompleted: viewModel.isCompleted,
                    playbackProgress: viewModel.playbackProgress,
                    duration: viewModel.savedDuration,
                    lastPlaybackPosition: viewModel.lastPlaybackPosition,
                    formattedDuration: viewModel.formattedDuration,
                    isDisabled: viewModel.isPlayDisabled,
                    style: .standard,
                    action: { viewModel.playAction() }
                )

                downloadButton

                // AI Analysis button (iOS 26+)
                if #available(iOS 26.0, macOS 26.0, *) {
                    NavigationLink(
                        destination: EpisodeAIAnalysisView(viewModel: viewModel)
                    ) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12))
                            Text("AI")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .tint(.purple)
                    .disabled(!viewModel.hasTranscript)
                }

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
        .background(Color.platformBackground)
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
            if viewModel.hasTranscript && !viewModel.isTranscriptProcessing {
                // Case 1: Transcript exists and we are idle - show live captions
                liveCaptionsView
            } else {
                // Case 2: Processing or no transcript - wrap in ScrollView for consistent layout
                ScrollView {
                    transcriptStatusSection
                        .padding(.vertical)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            startPlaybackTimer()
        }
        .onDisappear {
            stopPlaybackTimer()
        }
    }

    // MARK: - Timer Management (Instance-level, properly managed)

    private func startPlaybackTimer() {
        // Only start if not already running
        guard playbackTimerCancellable == nil else { return }

        playbackTimerCancellable = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak viewModel] _ in
                // This closure captures viewModel weakly to prevent retain cycle
                guard let vm = viewModel, vm.isPlayingThisEpisode else { return }
                // The view will update automatically via @Observable
            }
    }

    private func stopPlaybackTimer() {
        playbackTimerCancellable?.cancel()
        playbackTimerCancellable = nil
    }

    // MARK: - Live Captions View (Redesigned - Clean Full Page)
    private var liveCaptionsView: some View {
        VStack(spacing: 0) {
            // Compact header with search and menu
            HStack(spacing: 12) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                    TextField(
                        "Search transcript...",
                        text: $viewModel.transcriptSearchQuery
                    )
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    if !viewModel.transcriptSearchQuery.isEmpty {
                        Button(action: { viewModel.transcriptSearchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 14))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.platformSystemGray6)
                .cornerRadius(10)

                // Options menu
                Menu {
                    // Info section
                    Section {
                        if let date = viewModel.cachedTranscriptDate {
                            Label(
                                "Generated \(date.formatted(date: .abbreviated, time: .shortened))",
                                systemImage: "clock"
                            )
                        }
                        Label(
                            "\(viewModel.filteredTranscriptSegments.count) segments",
                            systemImage: "text.alignleft"
                        )
                    }

                    Divider()

                    Button(action: {
                        viewModel.copyTranscriptToClipboard()
                        showCopySuccess = true
                    }) {
                        Label("Copy All", systemImage: "doc.on.doc")
                    }

                    Button(
                        role: .destructive,
                        action: {
                            viewModel.generateTranscript()
                        }
                    ) {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 22))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Full page transcript segments
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(viewModel.filteredTranscriptSegments) { segment in
                            TranscriptSegmentRow(
                                segment: segment,
                                isCurrentSegment: viewModel.currentSegmentId == segment.id,
                                searchQuery: viewModel.transcriptSearchQuery,
                                showTimestamp: true,
                                onTap: { viewModel.seekToSegment(segment) }
                            )
                            .id(segment.id)
                        }
                    }
                    .padding(.vertical, 4)
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
            VStack(alignment: .leading, spacing: 16) {
                // On-device AI availability check
                if #available(iOS 26.0, macOS 26.0, *) {
                    onDeviceKeywordsContent
                } else {
                    // Fallback for older iOS versions
                    VStack(spacing: 12) {
                        Image(systemName: "apple.intelligence")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Requires iOS 26+")
                            .font(.headline)
                        Text(
                            "On-device AI keywords require iOS 26 or later with Apple Intelligence."
                        )
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            }
            .padding()
        }
        .onAppear {
            viewModel.checkOnDeviceAIAvailability()
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    @ViewBuilder
    private var onDeviceKeywordsContent: some View {
        // Header
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "apple.intelligence")
                    .foregroundColor(.blue)
                Text("Quick Tags")
                    .font(.title2)
                    .bold()
            }
            Text("AI-generated tags from episode metadata (on-device, private)")
                .font(.caption)
                .foregroundColor(.secondary)
        }

        // Availability banner if not available
        if !viewModel.onDeviceAIAvailability.isAvailable {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(
                    viewModel.onDeviceAIAvailability.message
                        ?? "On-device AI unavailable"
                )
                .font(.caption)
                .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        }

        // Quick tags content
        if let tags = viewModel.quickTagsCache.tags {
            // Tags card
            VStack(alignment: .leading, spacing: 12) {
                // Category
                HStack {
                    categoryBadge(tags.primaryCategory, isPrimary: true)
                    if let secondary = tags.secondaryCategory {
                        categoryBadge(secondary, isPrimary: false)
                    }
                }

                Divider()

                // Tags as chips
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tags")
                        .font(.headline)
                    FlowLayout(spacing: 8) {
                        ForEach(tags.tags, id: \.self) { tag in
                            tagChip(tag)
                        }
                    }
                }

                Divider()

                // Content type and difficulty
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Content Type")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(tags.contentType.capitalized)
                            .font(.subheadline)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Difficulty")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        difficultyBadge(tags.difficulty)
                    }
                }

                // Regenerate button
                Button(action: {
                    viewModel.quickTagsCache.tags = nil
                    viewModel.generateQuickTags()
                }) {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color.platformSystemGray6)
            .cornerRadius(12)
        } else {
            // Generate button
            Button(action: { viewModel.generateQuickTags() }) {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Generate Quick Tags")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    viewModel.onDeviceAIAvailability.isAvailable
                        ? Color.blue : Color.gray
                )
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(!viewModel.onDeviceAIAvailability.isAvailable)
        }

        // Analysis state feedback
        keywordsAnalysisStateView
    }

    @ViewBuilder
    private var keywordsAnalysisStateView: some View {
        switch viewModel.quickTagsState {
        case .idle, .completed:
            EmptyView()

        case .analyzing(let progress, let message):
            VStack(spacing: 12) {
                if progress < 0 {
                    ProgressView()
                        .scaleEffect(1.2)
                } else {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                }

                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.blue)
                    Text(message)
                        .font(.subheadline)
                }

                if progress >= 0 {
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.blue.opacity(0.05))
            .cornerRadius(12)

        case .error(let message):
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            .padding()
            .background(Color.red.opacity(0.1))
            .cornerRadius(8)
        }
    }

    // MARK: - Helper Views for Keywords Tab

    private func categoryBadge(_ category: String, isPrimary: Bool) -> some View
    {
        Text(category)
            .font(.caption)
            .fontWeight(isPrimary ? .bold : .regular)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                isPrimary ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1)
            )
            .foregroundColor(isPrimary ? .blue : .secondary)
            .cornerRadius(8)
    }

    private func tagChip(_ tag: String) -> some View {
        Text("#\(tag)")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(6)
    }

    private func difficultyBadge(_ level: String) -> some View {
        Text(level.capitalized)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(difficultyColor(level).opacity(0.2))
            .foregroundColor(difficultyColor(level))
            .cornerRadius(8)
    }

    private func difficultyColor(_ level: String) -> Color {
        switch level.lowercased() {
        case "beginner": return .green
        case "intermediate": return .orange
        case "advanced": return .red
        default: return .gray
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
    let showTimestamp: Bool
    let onTap: () -> Void

    init(
        segment: TranscriptSegment,
        isCurrentSegment: Bool,
        searchQuery: String,
        showTimestamp: Bool = false,
        onTap: @escaping () -> Void
    ) {
        self.segment = segment
        self.isCurrentSegment = isCurrentSegment
        self.searchQuery = searchQuery
        self.showTimestamp = showTimestamp
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: showTimestamp ? 12 : 0) {
                // Timestamp (optional)
                if showTimestamp {
                    Text(segment.formattedStartTime)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(isCurrentSegment ? .white : .blue)
                        .frame(width: 50, alignment: .leading)
                }

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
            .padding(.vertical, 10)
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
