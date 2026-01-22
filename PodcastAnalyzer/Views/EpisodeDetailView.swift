//
//  EpisodeDetailView.swift
//  PodcastAnalyzer
//
//  Fixed: Added Regenerate option to live view and fixed state visibility
//  Fixed: Memory leaks from static timer and proper cleanup on macOS
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

// MARK: - Scroll Offset Tracking

/// Preference key for tracking scroll offset
/// Uses Optional so inactive tabs can report nil without overwriting active tab's offset
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        // Only update if the next value is non-nil (from active tab)
        if let next = nextValue() {
            value = next
        }
    }
}

/// Helper view to read scroll offset using named coordinate space
/// Only reports offset when isActive is true to work correctly inside TabView with page style
struct ScrollOffsetReader: View {
    let coordinateSpace: String
    var isActive: Bool = true  // Only report offset when active (for TabView support)

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: ScrollOffsetPreferenceKey.self,
                    value: isActive ? proxy.frame(in: .named(coordinateSpace)).minY : nil
                )
        }
        .frame(height: 1)
    }
}

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

    // Translation error alert
    @State private var showTranslationError = false
    @State private var translationErrorMessage = ""

    // Timer state for transcript highlighting during playback (managed by .task modifier)
    @State private var playbackTimerActive = false

    // Scroll offset for collapsible header
    @State private var scrollOffset: CGFloat = 0
    @State private var baselineOffset: CGFloat?  // Captured on first scroll report

    // AI sub-tab selection (for integrated AI tab)


    // Computed properties for header collapse
    private var isHeaderCollapsed: Bool {
        scrollOffset < -80
    }

    private var headerOpacity: Double {
        let threshold: CGFloat = 80
        if scrollOffset >= 0 {
            return 1.0
        } else if scrollOffset <= -threshold {
            return 0.0
        } else {
            return 1.0 + Double(scrollOffset / threshold)
        }
    }



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
        ZStack(alignment: .top) {
            // Main content
            VStack(spacing: 0) {
                // Header with animated height collapse
                headerSection
                    .frame(height: isHeaderCollapsed ? 0 : nil)
                    .opacity(headerOpacity)
                    .clipped()

                if !isHeaderCollapsed {
                    Divider()
                }

                tabSelector
                Divider()

                #if os(iOS)
                TabView(selection: $selectedTab) {
                    summaryTab.tag(0)
                    transcriptTab.tag(1)
                    aiTab.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                #else
                // macOS: Use simple view switching to avoid default tab bar
                Group {
                    switch selectedTab {
                    case 0: summaryTab
                    case 1: transcriptTab
                    case 2: aiTab
                    default: summaryTab
                    }
                }
                #endif
            }

            // Collapsed mini header overlay (floats on top)
            if isHeaderCollapsed {
                collapsedMiniHeader
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .coordinateSpace(name: "EpisodeDetailScroll")
        .animation(.easeInOut(duration: 0.2), value: isHeaderCollapsed)
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
            // Only update if we got a non-nil value from the active tab
            guard let rawOffset = value else { return }

            // Capture baseline on first report
            if baselineOffset == nil {
                baselineOffset = rawOffset
            }

            // Calculate relative offset (negative = scrolled down)
            scrollOffset = rawOffset - (baselineOffset ?? 0)
        }
        .onChange(of: selectedTab) { _, _ in
            // Reset baseline when switching tabs
            baselineOffset = nil
            scrollOffset = 0
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

        .onAppear {
            viewModel.setModelContext(modelContext)
            viewModel.checkTranscriptStatus()
            // Try to load existing translations
            viewModel.loadExistingTranslations()
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

    // MARK: - Translation Helpers

    private func triggerTranscriptTranslation() {
        let settings = SubtitleSettingsManager.shared
        guard let targetLang = settings.targetLanguage.localeLanguage else { return }

        let sourceLang = TranslationService.shared.detectSourceLanguage(from: viewModel.podcastLanguage)
        transcriptTranslationConfig = TranslationService.shared.makeConfiguration(
            sourceLanguage: sourceLang,
            targetLanguage: targetLang
        )
    }

    private func triggerDescriptionTranslation() {
        let settings = SubtitleSettingsManager.shared
        guard let targetLang = settings.targetLanguage.localeLanguage else { return }

        let sourceLang = TranslationService.shared.detectSourceLanguage(from: viewModel.podcastLanguage)
        descriptionTranslationConfig = TranslationService.shared.makeConfiguration(
            sourceLanguage: sourceLang,
            targetLanguage: targetLang
        )
    }

    private func triggerTitleTranslation() {
        let settings = SubtitleSettingsManager.shared
        guard let targetLang = settings.targetLanguage.localeLanguage else { return }

        let sourceLang = TranslationService.shared.detectSourceLanguage(from: viewModel.podcastLanguage)
        titleTranslationConfig = TranslationService.shared.makeConfiguration(
            sourceLanguage: sourceLang,
            targetLanguage: targetLang
        )
    }

    private func triggerPodcastTitleTranslation() {
        let settings = SubtitleSettingsManager.shared
        guard let targetLang = settings.targetLanguage.localeLanguage else { return }

        let sourceLang = TranslationService.shared.detectSourceLanguage(from: viewModel.podcastLanguage)
        podcastTitleTranslationConfig = TranslationService.shared.makeConfiguration(
            sourceLanguage: sourceLang,
            targetLanguage: targetLang
        )
    }

    // MARK: - Collapsed Mini Header
    private var collapsedMiniHeader: some View {
        HStack(spacing: 12) {
            // Small artwork
            if let url = URL(string: viewModel.imageURLString) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Color.gray.overlay(ProgressView().scaleEffect(0.5))
                }
                .frame(width: 36, height: 36)
                .cornerRadius(6)
            } else {
                Color.gray
                    .frame(width: 36, height: 36)
                    .cornerRadius(6)
            }

            // Episode title (1 line)
            Text(viewModel.translatedEpisodeTitle ?? viewModel.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)

            Spacer()

            // Circular play button
            Button(action: { viewModel.playAction() }) {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 36, height: 36)

                    if viewModel.isPlayingThisEpisode && viewModel.audioManager.isPlaying {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isPlayDisabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
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
        .background(Color.platformBackground)
    }

    // MARK: - Summary Tab
    private var summaryTab: some View {
        ScrollView {
            ScrollOffsetReader(coordinateSpace: "EpisodeDetailScroll", isActive: selectedTab == 0)
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
                    ScrollOffsetReader(coordinateSpace: "EpisodeDetailScroll", isActive: selectedTab == 1)
                    transcriptStatusSection
                        .padding(.vertical)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task(id: playbackTimerActive) {
            // Task-based timer for playback updates - automatically cancelled when view disappears
            guard playbackTimerActive else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, viewModel.isPlayingThisEpisode else { continue }
                // The view updates automatically via @Observable
            }
        }
        .onAppear {
            playbackTimerActive = true
        }
        .onDisappear {
            playbackTimerActive = false
        }
    }

    // MARK: - Live Captions View (Apple Podcasts Style - Flowing Text)
    private var liveCaptionsView: some View {
        VStack(spacing: 0) {
            // Compact header with search and menu
            transcriptHeader

            // Flowing transcript content
            ScrollViewReader { proxy in
                ScrollView {
                    ScrollOffsetReader(coordinateSpace: "EpisodeDetailScroll", isActive: selectedTab == 1)
                    FlowingTranscriptView(
                        segments: viewModel.filteredTranscriptSegments,
                        currentTime: viewModel.isPlayingThisEpisode ? viewModel.audioManager.currentTime : nil,
                        searchQuery: viewModel.transcriptSearchQuery,
                        onSegmentTap: { segment in
                            viewModel.seekToSegment(segment)
                        }
                    )
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .onChange(of: viewModel.currentSegmentId) { _, newId in
                    if let id = newId, viewModel.transcriptSearchQuery.isEmpty {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("segment-\(id)", anchor: .center)
                        }
                    }
                }
            }
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

            // Translate button with circular progress
            Button {
                viewModel.translateTranscript()
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

    // MARK: - AI Tab (reuse EpisodeAIAnalysisView)
    private var aiTab: some View {
        EpisodeAIAnalysisView(viewModel: viewModel, isActive: selectedTab == 2)
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

// MARK: - CJK Text Utilities

/// Utilities for detecting and tokenizing CJK (Chinese, Japanese, Korean) text
enum CJKTextUtils {
    /// CJK Unicode ranges
    private static let cjkRanges: [ClosedRange<UInt32>] = [
        0x4E00...0x9FFF,    // CJK Unified Ideographs
        0x3400...0x4DBF,    // CJK Unified Ideographs Extension A
        0x20000...0x2A6DF,  // CJK Unified Ideographs Extension B
        0x2A700...0x2B73F,  // CJK Unified Ideographs Extension C
        0x2B740...0x2B81F,  // CJK Unified Ideographs Extension D
        0x3040...0x309F,    // Hiragana
        0x30A0...0x30FF,    // Katakana
        0xAC00...0xD7AF,    // Hangul Syllables
        0x1100...0x11FF,    // Hangul Jamo
    ]

    /// Check if text contains CJK characters
    static func containsCJK(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            for range in cjkRanges {
                if range.contains(scalar.value) {
                    return true
                }
            }
        }
        return false
    }

    /// Tokenize text - uses NLTokenizer for CJK, space-split for others
    static func tokenize(_ text: String) -> [String] {
        if containsCJK(text) {
            return tokenizeCJK(text)
        } else {
            return text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        }
    }

    /// Tokenize CJK text using NLTokenizer
    private static func tokenizeCJK(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        var tokens: [String] = []
        var lastIndex = text.startIndex

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            // Add any non-token text (spaces, punctuation) before this token
            if lastIndex < range.lowerBound {
                let betweenText = String(text[lastIndex..<range.lowerBound])
                if !betweenText.isEmpty {
                    tokens.append(betweenText)
                }
            }

            // Add the token
            tokens.append(String(text[range]))
            lastIndex = range.upperBound
            return true
        }

        // Add any remaining text after the last token
        if lastIndex < text.endIndex {
            let remaining = String(text[lastIndex..<text.endIndex])
            if !remaining.isEmpty {
                tokens.append(remaining)
            }
        }

        return tokens.isEmpty ? [text] : tokens
    }

    /// Check if a token is a CJK character (for determining if space should be added)
    static func isCJKToken(_ token: String) -> Bool {
        guard let first = token.unicodeScalars.first else { return false }
        for range in cjkRanges {
            if range.contains(first.value) {
                return true
            }
        }
        return false
    }
}

// MARK: - Flowing Transcript View (Apple Podcasts Style)

/// A flowing paragraph-style transcript view with word-level highlighting
struct FlowingTranscriptView: View {
    let segments: [TranscriptSegment]
    let currentTime: TimeInterval?
    let searchQuery: String
    let onSegmentTap: (TranscriptSegment) -> Void

    @State private var settings = SubtitleSettingsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(segments) { segment in
                let isCurrentSegment = isSegmentActive(segment)
                let wordProgress = calculateWordProgress(for: segment)

                FlowingSegmentText(
                    segment: segment,
                    isActive: isCurrentSegment,
                    wordProgress: wordProgress,
                    currentTime: currentTime,
                    searchQuery: searchQuery,
                    displayMode: settings.displayMode,
                    onTap: { onSegmentTap(segment) }
                )
                .id("segment-\(segment.id)")
            }
        }
    }

    private func isSegmentActive(_ segment: TranscriptSegment) -> Bool {
        guard let time = currentTime else { return false }
        return time >= segment.startTime && time <= segment.endTime
    }

    /// Calculate word progress within the current segment (0.0 to 1.0)
    private func calculateWordProgress(for segment: TranscriptSegment) -> Double? {
        guard let time = currentTime,
              time >= segment.startTime && time <= segment.endTime else {
            return nil
        }

        let duration = segment.endTime - segment.startTime
        guard duration > 0 else { return nil }

        return (time - segment.startTime) / duration
    }
}

/// Individual segment rendered as flowing text with word highlighting
struct FlowingSegmentText: View {
    let segment: TranscriptSegment
    let isActive: Bool
    let wordProgress: Double?
    let currentTime: TimeInterval?
    let searchQuery: String
    let displayMode: SubtitleDisplayMode
    let onTap: () -> Void

    var body: some View {
        let (primary, secondary) = segment.displayText(mode: displayMode)

        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                // Primary text with word-level highlighting
                buildHighlightedText(primary, isPrimary: true)
                    .font(.system(size: 17, weight: .regular))
                    .lineSpacing(4)

                // Secondary text (translation) if in dual mode
                if let secondaryText = secondary {
                    buildHighlightedText(secondaryText, isPrimary: false)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.secondary)
                        .lineSpacing(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? Color.blue.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func buildHighlightedText(_ text: String, isPrimary: Bool) -> some View {
        if isActive, isPrimary {
            // Word-level highlighting for currently playing segment
            // Use word timings if available, otherwise fall back to linear interpolation
            WordHighlightedText(
                text: text,
                progress: wordProgress ?? 0,
                wordTimings: segment.wordTimings,
                currentTime: currentTime,
                searchQuery: searchQuery
            )
        } else if !searchQuery.isEmpty {
            // Search highlighting only
            SearchHighlightedText(text: text, query: searchQuery)
        } else {
            // Plain text
            Text(text)
                .foregroundColor(isActive && isPrimary ? .primary : (isPrimary ? .primary : .secondary))
        }
    }
}

/// Text view with word-by-word highlighting based on playback progress
/// Supports CJK text with character-level tokenization
/// Uses actual word timings when available for accurate highlighting
struct WordHighlightedText: View {
    let text: String
    let progress: Double
    let wordTimings: [WordTiming]?
    let currentTime: TimeInterval?
    let searchQuery: String

    var body: some View {
        // Use CJKTextUtils for proper tokenization (handles CJK and non-CJK)
        let tokens = CJKTextUtils.tokenize(text)

        // Calculate which word index should be highlighted
        let (highlightedIndex, isSpeaking) = calculateHighlightedWordIndex(tokens: tokens)

        // Build attributed string with highlighted tokens
        Text(buildAttributedString(tokens: tokens, highlightedIndex: highlightedIndex, isSpeaking: isSpeaking))
    }

    /// Calculates which word index should be highlighted based on current time
    /// Returns (index, isSpeaking) where isSpeaking indicates if we're mid-word
    private func calculateHighlightedWordIndex(tokens: [String]) -> (Int, Bool) {
        // If we have actual word timings and current time, use precise highlighting
        if let timings = wordTimings, let time = currentTime, !timings.isEmpty {
            // Find the word that matches current time
            for (index, timing) in timings.enumerated() {
                if time >= timing.startTime && time <= timing.endTime {
                    return (index, true)  // Currently speaking this word
                } else if time < timing.startTime {
                    // We're before this word - highlight up to previous word
                    return (max(0, index - 1), false)
                }
            }
            // We're past the last word - all words spoken
            return (timings.count, false)
        }

        // Fall back to linear interpolation when word timings unavailable
        let totalTokens = tokens.count
        let highlightedCount = Int(Double(totalTokens) * progress)
        return (highlightedCount, true)
    }

    private func buildAttributedString(tokens: [String], highlightedIndex: Int, isSpeaking: Bool) -> AttributedString {
        var result = AttributedString()
        let isCJKText = CJKTextUtils.containsCJK(text)

        for (index, token) in tokens.enumerated() {
            var tokenAttr = AttributedString(token)

            if index < highlightedIndex {
                // Already spoken - bold blue
                tokenAttr.foregroundColor = .blue
                tokenAttr.font = .system(size: 17, weight: .semibold)
            } else if index == highlightedIndex && isSpeaking {
                // Currently speaking - highlighted with background
                tokenAttr.foregroundColor = .blue
                tokenAttr.font = .system(size: 17, weight: .bold)
                tokenAttr.backgroundColor = Color.blue.opacity(0.2)
            } else if index == highlightedIndex {
                // Just finished this word
                tokenAttr.foregroundColor = .blue
                tokenAttr.font = .system(size: 17, weight: .semibold)
            } else {
                // Not yet spoken
                tokenAttr.foregroundColor = .primary.opacity(0.6)
                tokenAttr.font = .system(size: 17, weight: .regular)
            }

            // Apply search highlighting if applicable
            if !searchQuery.isEmpty && token.lowercased().contains(searchQuery.lowercased()) {
                tokenAttr.backgroundColor = .yellow.opacity(0.4)
            }

            result.append(tokenAttr)

            // Add space after token for non-CJK text only (CJK doesn't use spaces between words)
            if !isCJKText && index < tokens.count - 1 {
                result.append(AttributedString(" "))
            }
        }

        return result
    }
}

/// Text with search query highlighting
struct SearchHighlightedText: View {
    let text: String
    let query: String

    var body: some View {
        Text(buildHighlightedAttributedString())
    }

    private func buildHighlightedAttributedString() -> AttributedString {
        guard !query.isEmpty else { return AttributedString(text) }

        var result = AttributedString()
        let lowercasedText = text.lowercased()
        let lowercasedQuery = query.lowercased()

        var currentIndex = text.startIndex

        while let range = lowercasedText[currentIndex...].range(of: lowercasedQuery) {
            // Add text before match
            let beforeRange = currentIndex..<range.lowerBound
            if !beforeRange.isEmpty {
                result.append(AttributedString(String(text[beforeRange])))
            }

            // Add highlighted match
            let matchRange = range.lowerBound..<range.upperBound
            var matchAttr = AttributedString(String(text[matchRange]))
            matchAttr.backgroundColor = .yellow.opacity(0.5)
            matchAttr.font = .system(size: 17, weight: .semibold)
            result.append(matchAttr)

            currentIndex = range.upperBound
        }

        // Add remaining text
        if currentIndex < text.endIndex {
            result.append(AttributedString(String(text[currentIndex...])))
        }

        return result
    }
}

// (Existing Helper Components: TabButton, TranscriptSegmentRow remain unchanged)
