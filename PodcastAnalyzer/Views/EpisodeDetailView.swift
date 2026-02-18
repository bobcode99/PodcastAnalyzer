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
    @State private var subtitleSettings = SubtitleSettingsManager.shared

    // Translation error alert
    @State private var showTranslationError = false
    @State private var translationErrorMessage = ""

    // Timer state for transcript highlighting during playback (managed by .task modifier)
    @State private var playbackTimerActive = false
    @State private var currentPlaybackTime: TimeInterval = 0

    // Auto-scroll state
    @State private var autoScrollEnabled = true

    // Transcript search focus
    @FocusState private var transcriptSearchFocused: Bool

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

    private var scrollContent: some View {
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
                    .glassEffect(Glass.regular)
            }
        }
    }

    /// Current sentence ID for auto-scroll
    private var currentSentenceId: Int? {
        guard viewModel.isCurrentEpisode else { return nil }
        let time = currentPlaybackTime
        return viewModel.groupedSentences.first { $0.containsTime(time) }?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                scrollContent
            }
            .onScrollPhaseChange { _, newPhase in
                // Disable auto-scroll when user interacts
                if newPhase == .interacting {
                    autoScrollEnabled = false
                }
            }
            .onChange(of: currentSentenceId) { _, newId in
                if autoScrollEnabled, let id = newId, selectedTab == 1, viewModel.transcriptSearchQuery.isEmpty {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            .onChange(of: viewModel.currentMatchIndex) { _, _ in
                // Scroll to the current search match
                if !viewModel.searchMatchIds.isEmpty {
                    let matchId = viewModel.searchMatchIds[viewModel.currentMatchIndex]
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(matchId, anchor: .center)
                    }
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
        EpisodeDetailHeaderView(viewModel: viewModel)
    }
    // MARK: - Download Button (Icon-Only Capsule)
    @ViewBuilder
    private var downloadButtonIconOnly: some View {
        switch viewModel.downloadState {
        case .notDownloaded:
            Button(action: { viewModel.startDownload() }) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
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
                            .foregroundStyle(.white)
                    }
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
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
                    .foregroundStyle(.white)
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
                    .foregroundStyle(.white)
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

    @ViewBuilder
    private var descriptionView: some View {
        switch viewModel.descriptionContent {
        case .loading:
            Text("Loading...").foregroundStyle(.secondary)
        case .empty:
            Text("No description available.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .parsed(let attributedString):
            HTMLTextView(attributedString: attributedString)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
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
                        descriptionView
                            .textSelection(.enabled)
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            } else {
                // Original description only
                descriptionView
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
        let sentences = viewModel.transcriptSearchQuery.isEmpty
            ? viewModel.groupedSentences
            : viewModel.filteredGroupedSentences
        let searchMatchIdSet = Set(viewModel.searchMatchIds)

        return Section {
            // Search navigation bar
            if !viewModel.transcriptSearchQuery.isEmpty && !viewModel.searchMatchIds.isEmpty {
                TranscriptSearchNavigationBar(
                    matchCount: viewModel.searchMatchIds.count,
                    currentIndex: viewModel.currentMatchIndex,
                    onPrevious: {
                        _ = viewModel.previousMatch()
                    },
                    onNext: {
                        _ = viewModel.nextMatch()
                    }
                )
                .padding(.vertical, 4)
            }

            // Sentence-based transcript content
            SentenceBasedTranscriptView(
                sentences: sentences,
                currentTime: viewModel.isCurrentEpisode ? currentPlaybackTime : nil,
                searchQuery: viewModel.transcriptSearchQuery,
                onSegmentTap: { segment in
                    viewModel.seekToSegment(segment)
                },
                subtitleMode: subtitleSettings.displayMode,
                searchMatchIds: searchMatchIdSet,
                currentSearchMatchId: viewModel.searchMatchIds.isEmpty ? nil : viewModel.searchMatchIds[viewModel.currentMatchIndex]
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        } header: {
            transcriptHeader
                .background(.ultraThinMaterial)
        }
        .onChange(of: viewModel.transcriptSearchQuery) { _, newQuery in
            viewModel.updateSearchMatches(query: newQuery)
        }
    }

    // MARK: - Transcript Header
    private var transcriptHeader: some View {
        HStack(spacing: 12) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
                TextField(
                    "Search transcript...",
                    text: $viewModel.transcriptSearchQuery
                )
                .textFieldStyle(.plain)
                .font(.subheadline)
                .focused($transcriptSearchFocused)
                .submitLabel(.search)
                if !viewModel.transcriptSearchQuery.isEmpty {
                    Button {
                        viewModel.transcriptSearchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .rect(cornerRadius: 10))

            if transcriptSearchFocused || !viewModel.transcriptSearchQuery.isEmpty {
                // Cancel search — clears query and dismisses keyboard
                Button("Cancel") {
                    viewModel.transcriptSearchQuery = ""
                    transcriptSearchFocused = false
                }
                .font(.subheadline)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
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
                        .foregroundStyle(.red)
                } else if viewModel.hasExistingTranslation {
                    ZStack(alignment: .bottomTrailing) {
                        Image(systemName: "translate.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.blue)
                        if let lang = viewModel.selectedTranslationLanguage {
                            Text(lang.shortName)
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(.blue)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                                .offset(x: 4, y: 4)
                        }
                    }
                } else {
                    Image(systemName: "translate")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(viewModel.translationStatus.isTranslating)

            // Auto-scroll toggle
            Button {
                autoScrollEnabled.toggle()
            } label: {
                Image(systemName: "arrow.up.and.down.text.horizontal")
                    .font(.system(size: 18))
                    .foregroundStyle(autoScrollEnabled ? .blue : .secondary)
            }

            // Display mode picker (when translation exists) or settings button
            if viewModel.hasExistingTranslation {
                Menu {
                    ForEach(SubtitleDisplayMode.allCases, id: \.self) { mode in
                        Button {
                            subtitleSettings.displayMode = mode
                        } label: {
                            if subtitleSettings.displayMode == mode {
                                Label(mode.displayName, systemImage: "checkmark")
                            } else {
                                Label(mode.displayName, systemImage: mode.icon)
                            }
                        }
                    }
                    Divider()
                    Button {
                        showSubtitleSettings = true
                    } label: {
                        Label("More Settings...", systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "textformat.alt")
                        .font(.system(size: 20))
                        .foregroundStyle(.blue)
                }
            } else {
                Button {
                    showSubtitleSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
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
                    .foregroundStyle(.secondary)
            }
            } // end else (not searching)
        }
        .animation(.easeInOut(duration: 0.2), value: transcriptSearchFocused)
        .animation(.easeInOut(duration: 0.2), value: viewModel.transcriptSearchQuery.isEmpty)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Transcript Status Section
    @ViewBuilder
    private var transcriptStatusSection: some View {
        EpisodeTranscriptStatusView(viewModel: viewModel)
            .frame(maxWidth: .infinity)
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
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
                    .foregroundStyle(.blue)
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
                    .foregroundStyle(isSelected ? .blue : .secondary)

                Rectangle()
                    .fill(isSelected ? Color.blue : Color.clear)
                    .frame(height: 2)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
