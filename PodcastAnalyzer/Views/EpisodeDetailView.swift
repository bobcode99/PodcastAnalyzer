//
//  EpisodeDetailView.swift
//  PodcastAnalyzer
//
//  Fixed header + per-tab ScrollView architecture
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
    @State private var showDeleteConfirmation = false
    @State private var showSubtitleSettings = false
    @State private var showTranslationLanguagePicker = false

    // Translation error alert
    @State private var showTranslationError = false
    @State private var translationErrorMessage = ""

    // Header collapse state
    @State private var isHeaderVisible: Bool = true
    @State private var lastScrollOffset: CGFloat = 0
    @State private var isUserScrolling: Bool = false

    // Scroll-to-top trigger
    @State private var scrollToTopTrigger = false

    // Transcript DAI regenerate
    @State private var showRegenerateConfirmation = false

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

    var body: some View {
        VStack(spacing: 0) {
            EpisodeDetailHeaderView(viewModel: viewModel)
                .frame(height: isHeaderVisible ? nil : 0)
                .clipped()
                .opacity(isHeaderVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: isHeaderVisible)
            Divider()
                .opacity(isHeaderVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: isHeaderVisible)
            tabSelector
            Divider()
            tabContentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topTrailing) {
                    if !isHeaderVisible {
                        Button {
                            scrollToTopTrigger.toggle()
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 32)
                                .glassEffect(.regular, in: .circle)
                        }
                        .padding(.trailing, 12)
                        .padding(.top, 8)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: isHeaderVisible)
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
                    if selectedTab != 2 {
                        Button(action: { showTranslationLanguagePicker = true }) {
                            Image(systemName: "translate")
                        }
                        .accessibilityLabel("Translate")
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

                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More options")
                }
            }
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
        .confirmationDialog(
            "Regenerate Transcript",
            isPresented: $showRegenerateConfirmation,
            titleVisibility: .visible
        ) {
            Button("Regenerate from Audio") {
                viewModel.regenerateTranscript()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This will replace the current transcript with one generated from the downloaded audio. The new transcript will have accurate timestamps."
            )
        }
        .sheet(isPresented: $showSubtitleSettings) {
            SubtitleSettingsSheet(hasTranslation: viewModel.hasExistingTranslation)
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
        .onChange(of: selectedTab) { _, _ in
            lastScrollOffset = 0
        }
        .onAppear {
            viewModel.setModelContext(modelContext)
            viewModel.checkTranscriptStatus()
            // Try to load existing translations and check available ones
            viewModel.loadExistingTranslations()
            viewModel.checkAvailableTranslations()
        }
        .onDisappear {
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
        case 0: summaryTab
        case 1: TranscriptContentView(
            viewModel: viewModel,
            isHeaderVisible: $isHeaderVisible,
            lastScrollOffset: $lastScrollOffset,
            isUserScrolling: $isUserScrolling,
            scrollToTopTrigger: $scrollToTopTrigger,
            onShowTranslationPicker: { showTranslationLanguagePicker = true },
            onShowSubtitleSettings: { showSubtitleSettings = true },
            onShowRegenerateConfirmation: { showRegenerateConfirmation = true }
        )
        case 2: EpisodeAIAnalysisView(viewModel: viewModel, embedsOwnScroll: true, isHeaderVisible: $isHeaderVisible, lastScrollOffset: $lastScrollOffset, isUserScrolling: $isUserScrolling, scrollToTopTrigger: $scrollToTopTrigger)
        default: Text("Unknown tab: \(selectedTab)")
            .foregroundStyle(.secondary)
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

    // MARK: - Tab Selector
    private var tabSelector: some View {
        HStack(spacing: 0) {
            TabButton(title: "Summary", isSelected: selectedTab == 0) {
                withAnimation(.easeInOut(duration: 0.2)) { selectedTab = 0 }
            }
            TabButton(title: "Transcript", isSelected: selectedTab == 1) {
                withAnimation(.easeInOut(duration: 0.2)) { selectedTab = 1 }
            }
            TabButton(title: "AI", isSelected: selectedTab == 2) {
                withAnimation(.easeInOut(duration: 0.2)) { selectedTab = 2 }
            }
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

    // MARK: - Summary Tab (owns its own ScrollView)
    private var summaryTab: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: 0).id("summaryTop")
                summaryContent
            }
            .trackScrollForHeaderCollapse(
                isHeaderVisible: $isHeaderVisible,
                lastOffset: $lastScrollOffset,
                isUserScrolling: isUserScrolling
            )
            .onScrollPhaseChange { _, newPhase in
                isUserScrolling = newPhase == .interacting || newPhase == .decelerating
            }
            .onChange(of: scrollToTopTrigger) { _, _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("summaryTop", anchor: .top)
                }
                isHeaderVisible = true
            }
        }
    }

    // MARK: - Summary Content
    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Show translated description if available
            if let translated = viewModel.translatedDescription {
                VStack(alignment: .leading, spacing: 12) {
                    // Translated text
                    Text(translated)
                        .font(.body)
                        .textSelection(.enabled)

                    // Timestamp chips from translated text
                    timestampChips(from: translated)

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
                VStack(alignment: .leading, spacing: 8) {
                    descriptionView
                        .textSelection(.enabled)

                    // Timestamp chips from description
                    timestampChips(from: viewModel.episode.podcastEpisodeDescription)
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }

    // MARK: - Timestamp Chips

    @ViewBuilder
    private func timestampChips(from text: String?) -> some View {
        let timestamps = TimestampUtils.findTimestamps(in: text ?? "")
        if !timestamps.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(timestamps.indices, id: \.self) { i in
                    let ts = timestamps[i]
                    Menu {
                        Button {
                            viewModel.seekToTime(ts.seconds)
                        } label: {
                            Label("Play from \(ts.text)", systemImage: "play.fill")
                        }
                        Button {
                            viewModel.shareTimestampedLink(seconds: ts.seconds)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 10))
                            Text(ts.text)
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

}

// MARK: - Scroll Header Collapse Modifier

/// Snapshot of scroll geometry values for change detection
nonisolated struct ScrollGeometrySnapshot: Equatable {
    let contentOffset: CGFloat
    let contentHeight: CGFloat
    let visibleHeight: CGFloat
}

extension View {
    func trackScrollForHeaderCollapse(
        isHeaderVisible: Binding<Bool>,
        lastOffset: Binding<CGFloat>,
        isUserScrolling: Bool
    ) -> some View {
        self
            .onScrollGeometryChange(for: ScrollGeometrySnapshot.self) { geometry in
                ScrollGeometrySnapshot(
                    contentOffset: geometry.contentOffset.y,
                    contentHeight: geometry.contentSize.height,
                    visibleHeight: geometry.visibleRect.size.height
                )
            } action: { oldValue, newValue in
                guard isUserScrolling else { return }

                // Content fits without scrolling — never collapse header (avoids shaking loop)
                guard newValue.contentHeight > newValue.visibleHeight else {
                    if !isHeaderVisible.wrappedValue { isHeaderVisible.wrappedValue = true }
                    return
                }

                // Ignore layout-induced offset changes (e.g. header collapse/expand resizing content)
                if abs(newValue.contentHeight - oldValue.contentHeight) > 1 {
                    lastOffset.wrappedValue = newValue.contentOffset
                    return
                }

                // Near-top threshold: only show header when scrolled close to top
                let nearTopThreshold: CGFloat = 60
                if newValue.contentOffset <= nearTopThreshold {
                    if !isHeaderVisible.wrappedValue {
                        isHeaderVisible.wrappedValue = true
                    }
                    lastOffset.wrappedValue = newValue.contentOffset
                    return
                }

                // Ignore rubber-band bounce at the bottom edge
                let maxOffset = newValue.contentHeight - newValue.visibleHeight
                if maxOffset > 0, newValue.contentOffset >= maxOffset - 5 {
                    lastOffset.wrappedValue = newValue.contentOffset
                    return
                }

                let delta = newValue.contentOffset - lastOffset.wrappedValue
                // Dead zone to prevent jitter
                guard abs(delta) > 8 else { return }

                // Only collapse when scrolling down; do NOT re-show on scroll-up
                // Header only reappears when near the top (handled above)
                if delta > 0 && isHeaderVisible.wrappedValue {
                    isHeaderVisible.wrappedValue = false
                }
                lastOffset.wrappedValue = newValue.contentOffset
            }
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
    let title: LocalizedStringKey
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
