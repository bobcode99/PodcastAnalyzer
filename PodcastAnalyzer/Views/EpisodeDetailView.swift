//
//  EpisodeDetailView.swift
//  PodcastAnalyzer
//
//  Redesigned with simpler architecture: single ScrollView + sticky tabs
//

import Foundation
import NaturalLanguage
import SwiftData
import SwiftUI

#if canImport(Translation)
@preconcurrency import Translation
#endif

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
    @State private var showSubtitleSettings = false
    @State private var showTranslationLanguagePicker = false

    // Translation error alert
    @State private var showTranslationError = false
    @State private var translationErrorMessage = ""

    // Timer state for transcript highlighting during playback (managed by .task modifier)
    @State private var playbackTimerActive = false
    @State private var currentPlaybackTime: TimeInterval = 0

    // Translation configuration for .translationTask
    @State private var transcriptTranslationConfig: TranslationSession.Configuration?
    @State private var descriptionTranslationConfig: TranslationSession.Configuration?
    @State private var titleTranslationConfig: TranslationSession.Configuration?
    @State private var podcastTitleTranslationConfig: TranslationSession.Configuration?

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
            predicate: #Predicate { $0.title == title }
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
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                // Header scrolls away naturally
                headerSection
                    .padding(.bottom, 8)

                Divider()

                // Sticky tabs + content
                Section {
                    tabContentView
                        .frame(minHeight: 400)
                } header: {
                    tabSelector
                        .background(.regularMaterial)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 80)
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: toolbarPlacement) {
                HStack(spacing: 16) {
                    Button(action: { showTranslationLanguagePicker = true }) {
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
        .alert("Translation Failed", isPresented: $showTranslationError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(translationErrorMessage)
        }
        .onChange(of: viewModel.translationStatus) { _, newStatus in
            if case .failed(let error) = newStatus {
                translationErrorMessage = error
                showTranslationError = true
            }
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
        .sheet(isPresented: $showSubtitleSettings) {
            SubtitleSettingsSheet()
        }
        .sheet(isPresented: $showTranslationLanguagePicker) {
            TranslationLanguagePickerSheet(
                availableTranslations: viewModel.availableTranslationLanguages,
                translationStatus: viewModel.translationStatus,
                onSelectLanguage: { language in
                    viewModel.translateTo(language)
                }
            )
        }
        .onAppear {
            viewModel.setModelContext(modelContext)
            viewModel.checkTranscriptStatus()
            // Try to load existing translations and check available ones
            viewModel.loadExistingTranslations()
            viewModel.checkAvailableTranslations()
        }
        .onDisappear {
            // Clean up subscriptions to prevent memory leaks
            // Timer is automatically cancelled by .task modifier when view disappears
            playbackTimerActive = false
            viewModel.cleanup()
        }
        .onChange(of: viewModel.transcriptTranslationTrigger) { _, _ in
            triggerTranscriptTranslation()
        }
        .onChange(of: viewModel.descriptionTranslationTrigger) { _, _ in
            triggerDescriptionTranslation()
        }
        .onChange(of: viewModel.episodeTitleTranslationTrigger) { _, _ in
            triggerTitleTranslation()
        }
        .onChange(of: viewModel.podcastTitleTranslationTrigger) { _, _ in
            triggerPodcastTitleTranslation()
        }
        .translationTask(transcriptTranslationConfig) { session in
            await viewModel.performTranscriptTranslation(using: session)
        }
        .translationTask(descriptionTranslationConfig) { session in
            await viewModel.performDescriptionTranslation(using: session)
        }
        .translationTask(titleTranslationConfig) { session in
            await viewModel.performTitleTranslation(using: session)
        }
        .translationTask(podcastTitleTranslationConfig) { session in
            await viewModel.performPodcastTitleTranslation(using: session)
        }
    }

    // MARK: - Tab Content View

    @ViewBuilder
    private var tabContentView: some View {
        switch selectedTab {
        case 0: summaryContent
        case 1: transcriptContent
        case 2: EpisodeAIAnalysisView(viewModel: viewModel, embedsOwnScroll: false)
        default: EmptyView()
        }
    }

    // MARK: - Translation Helpers

    private func triggerTranscriptTranslation() {
        guard let targetLang = viewModel.selectedTranslationLanguage?.localeLanguage else { return }

        let sourceLang = TranslationService.shared.detectSourceLanguage(from: viewModel.podcastLanguage)
        transcriptTranslationConfig = TranslationService.shared.makeConfiguration(
            sourceLanguage: sourceLang,
            targetLanguage: targetLang
        )
    }

    private func triggerDescriptionTranslation() {
        guard let targetLang = viewModel.selectedTranslationLanguage?.localeLanguage else { return }

        let sourceLang = TranslationService.shared.detectSourceLanguage(from: viewModel.podcastLanguage)
        descriptionTranslationConfig = TranslationService.shared.makeConfiguration(
            sourceLanguage: sourceLang,
            targetLanguage: targetLang
        )
    }

    private func triggerTitleTranslation() {
        guard let targetLang = viewModel.selectedTranslationLanguage?.localeLanguage else { return }

        let sourceLang = TranslationService.shared.detectSourceLanguage(from: viewModel.podcastLanguage)
        titleTranslationConfig = TranslationService.shared.makeConfiguration(
            sourceLanguage: sourceLang,
            targetLanguage: targetLang
        )
    }

    private func triggerPodcastTitleTranslation() {
        guard let targetLang = viewModel.selectedTranslationLanguage?.localeLanguage else { return }

        let sourceLang = TranslationService.shared.detectSourceLanguage(from: viewModel.podcastLanguage)
        podcastTitleTranslationConfig = TranslationService.shared.makeConfiguration(
            sourceLanguage: sourceLang,
            targetLanguage: targetLang
        )
    }

    // MARK: - Header Section (Updated)
    private var headerSection: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                // Artwork
                if let url = URL(string: viewModel.imageURLString) {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Color.gray.overlay(ProgressView())
                    }
                    .frame(width: 80, height: 80)
                    .cornerRadius(10)
                    .shadow(radius: 2)
                } else {
                    Color.gray.frame(width: 80, height: 80).cornerRadius(10)
                }

                VStack(alignment: .leading, spacing: 6) {
                    // FULL TITLE – no lineLimit, multiline, selectable
                    // Show translated title if available, with disclosure for original
                    if let translatedTitle = viewModel.translatedEpisodeTitle {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(translatedTitle)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .multilineTextAlignment(.leading)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)

                            DisclosureGroup("Original") {
                                Text(viewModel.title)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .textSelection(.enabled)
                            }
                            .font(.caption2)
                            .foregroundColor(.blue)
                        }
                    } else {
                        Text(viewModel.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Tappable podcast title - navigates to show
                    NavigationLink(destination: podcastDestination) {
                        HStack(spacing: 4) {
                            if let translatedTitle = viewModel.translatedPodcastTitle {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(translatedTitle)
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    Text(viewModel.podcastTitle)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text(viewModel.podcastTitle)
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
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
                }
                Spacer()
            }

            // Play + Download buttons (icon-only capsules)
            HStack(spacing: 8) {
                // Play button with progress (icon-only style)
                EpisodePlayButton(
                    isPlaying: viewModel.audioManager.isPlaying,
                    isPlayingThisEpisode: viewModel.isPlayingThisEpisode,
                    isCompleted: viewModel.isCompleted,
                    playbackProgress: viewModel.playbackProgress,
                    duration: viewModel.savedDuration,
                    lastPlaybackPosition: viewModel.lastPlaybackPosition,
                    formattedDuration: viewModel.formattedDuration,
                    isDisabled: viewModel.isPlayDisabled,
                    style: .iconOnly,
                    action: { viewModel.playAction() }
                )

                downloadButtonIconOnly

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
    // MARK: - Download Button (Icon-Only Capsule)
    @ViewBuilder
    private var downloadButtonIconOnly: some View {
        switch viewModel.downloadState {
        case .notDownloaded:
            Button(action: { viewModel.startDownload() }) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.gray)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

        case .downloading(let progress):
            Button(action: { viewModel.cancelDownload() }) {
                HStack(spacing: 6) {
                    // Circular progress indicator
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                            .frame(width: 16, height: 16)
                        Circle()
                            .trim(from: 0, to: CGFloat(progress))
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .frame(width: 16, height: 16)
                            .rotationEffect(.degrees(-90))
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.orange)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

        case .finishing:
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.blue)
            .clipShape(Capsule())

        case .downloaded:
            Button(action: { showDeleteConfirmation = true }) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.green)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

        case .failed:
            Button(action: { viewModel.startDownload() }) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.red)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Tab Selector
    private var tabSelector: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TabButton(title: "Summary", isSelected: selectedTab == 0) {
                    withAnimation { selectedTab = 0 }
                }
                TabButton(title: "Transcript", isSelected: selectedTab == 1) {
                    withAnimation { selectedTab = 1 }
                }
                TabButton(title: "AI", isSelected: selectedTab == 2) {
                    withAnimation { selectedTab = 2 }
                }
            }
            Divider()
        }
    }

    // MARK: - Summary Content (no ScrollView - parent provides scrolling)
    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Show translated description if available
            if let translated = viewModel.translatedDescription {
                VStack(alignment: .leading, spacing: 12) {
                    // Translated text
                    Text(translated)
                        .font(.body)
                        .textSelection(.enabled)

                    Divider()

                    // Original description (collapsed by default)
                    DisclosureGroup("Original") {
                        viewModel.descriptionView
                            .textSelection(.enabled)
                    }
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            } else {
                // Original description only
                viewModel.descriptionView
                    .textSelection(.enabled)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }

    // MARK: - Transcript Content (no ScrollView wrapper - parent provides scrolling)
    private var transcriptContent: some View {
        VStack(spacing: 0) {
            if viewModel.hasTranscript && !viewModel.isTranscriptProcessing {
                // Case 1: Transcript exists and we are idle - show live captions
                liveCaptionsContent
            } else {
                // Case 2: Processing or no transcript
                transcriptStatusSection
                    .padding(.vertical)
                    .frame(maxWidth: .infinity)
            }
        }
        .task(id: playbackTimerActive) {
            // Task-based timer for playback updates - automatically cancelled when view disappears
            guard playbackTimerActive else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { break }
                // Always update when this episode is current (playing or paused)
                if viewModel.isCurrentEpisode {
                    await MainActor.run {
                        currentPlaybackTime = viewModel.audioManager.currentTime
                    }
                }
            }
        }
        .onAppear {
            playbackTimerActive = true
            // Initialize immediately to avoid delay
            if viewModel.isCurrentEpisode {
                currentPlaybackTime = viewModel.audioManager.currentTime
            }
        }
        .onDisappear {
            playbackTimerActive = false
        }
    }

    // MARK: - Live Captions Content (Apple Podcasts Style - Flowing Text)
    private var liveCaptionsContent: some View {
        VStack(spacing: 0) {
            // Compact header with search and menu
            transcriptHeader

            // Flowing transcript content (no ScrollView - parent provides scrolling)
            // Always pass currentTime when this is the current episode (like ExpandedPlayerView)
            FlowingTranscriptView(
                segments: viewModel.filteredTranscriptSegments,
                currentTime: viewModel.isCurrentEpisode ? currentPlaybackTime : nil,
                searchQuery: viewModel.transcriptSearchQuery,
                onSegmentTap: { segment in
                    viewModel.seekToSegment(segment)
                }
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Transcript Header
    private var transcriptHeader: some View {
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

            // Translate button with circular progress - shows language picker
            Button {
                showTranslationLanguagePicker = true
            } label: {
                if viewModel.translationStatus.isTranslating {
                    TranslationProgressCircle(status: viewModel.translationStatus)
                        .frame(width: 28, height: 28)
                } else if case .failed = viewModel.translationStatus {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.red)
                } else {
                    Image(systemName: viewModel.hasExistingTranslation ? "translate.fill" : "translate")
                        .font(.system(size: 20))
                        .foregroundColor(viewModel.hasExistingTranslation ? .blue : .secondary)
                }
            }
            .disabled(viewModel.translationStatus.isTranslating)

            // Settings button
            Button {
                showSubtitleSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
            }

            // Options menu
            Menu {
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

                // Copy options section
                Section("Copy") {
                    Button(action: {
                        viewModel.copyTranscriptToClipboard()
                        showCopySuccess = true
                    }) {
                        Label("Copy All (with timestamps)", systemImage: "doc.on.doc")
                    }

                    Button(action: {
                        PlatformClipboard.string = viewModel.cleanTranscriptText
                        showCopySuccess = true
                    }) {
                        Label("Copy Text Only", systemImage: "text.alignleft")
                    }
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
    }

    // MARK: - Transcript Status Section
    @ViewBuilder
    private var transcriptStatusSection: some View {
        VStack(spacing: 16) {
            switch viewModel.transcriptState {
            case .idle:
                // Check RSS transcript availability first
                if viewModel.hasRSSTranscriptAvailable {
                    VStack(spacing: 12) {
                        Image(systemName: "captions.bubble")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                        Text("Transcript Available").font(.headline)
                        Text("This episode has a transcript from the podcast feed.")
                            .font(.caption).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button(action: { viewModel.downloadRSSTranscript() }) {
                            Label("Download Transcript", systemImage: "arrow.down.circle")
                                .font(.subheadline)
                                .padding(.horizontal, 20).padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if viewModel.isDownloadingRSSTranscript {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Downloading Transcript").font(.headline)
                            .padding(.top, 8)
                    }
                } else if viewModel.hasLocalAudio {
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

}

// MARK: - Translation Progress Circle

/// A circular progress indicator for translation status
struct TranslationProgressCircle: View {
    let status: TranslationStatus

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 3)

            // Progress arc
            if case .translating(let progress, let completed, _) = status {
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.2), value: progress)

                // Small text showing count
                Text("\(completed)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.blue)
            } else if case .preparingSession = status {
                // Indeterminate spinning indicator
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
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

    // Access subtitle settings for display mode
    @State private var settings = SubtitleSettingsManager.shared

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
        let (primary, secondary) = segment.displayText(mode: settings.displayMode)

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

                // Text content with dual subtitle support
                VStack(alignment: .leading, spacing: 4) {
                    // Primary text with search highlighting
                    highlightedText(primary)
                        .font(.body)
                        .foregroundColor(isCurrentSegment ? .white : .primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Secondary text (for dual modes)
                    if let secondaryText = secondary {
                        highlightedText(secondaryText)
                            .font(.subheadline)
                            .foregroundColor(isCurrentSegment ? .white.opacity(0.8) : .secondary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
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
    private func highlightedText(_ text: String) -> some View {
        if searchQuery.isEmpty {
            Text(text)
        } else {
            highlightMatches(in: text, query: searchQuery)
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

// NOTE: CJKTextUtils, FlowingTranscriptView, FlowingSegmentText, WordHighlightedText,
// SearchHighlightedText are now in Views/Components/TranscriptViews.swift

