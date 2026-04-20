//
//  TranscriptContentView.swift
//  PodcastAnalyzer
//
//  Transcript tab content extracted from EpisodeDetailView.
//  Owns the playback timer, scroll state, and search focus for the transcript tab.
//

import SwiftUI

struct TranscriptContentView: View {
    @Bindable var viewModel: EpisodeDetailViewModel
    @Binding var isHeaderVisible: Bool
    @Binding var lastScrollOffset: CGFloat
    @Binding var isUserScrolling: Bool
    @Binding var scrollToTopTrigger: Bool

    var onShowTranslationPicker: () -> Void
    var onShowSubtitleSettings: () -> Void
    var onShowRegenerateConfirmation: () -> Void

    // Playback timer state (task-managed, auto-cancelled on disappear)
    @State private var playbackTimerActive = false
    @State private var currentPlaybackTime: TimeInterval = 0

    // Auto-scroll state
    @State private var autoScrollEnabled = true

    // Scroll position timestamp indicator
    @State private var topVisibleSentenceId: Int?
    @State private var showScrollTimestamp = false

    // Local binding for RSSTranscriptWarningBanner — onChange bridges to callback
    @State private var showRegenerateConfirmation = false

    // Search focus owned here, passed into TranscriptToolbar
    @FocusState private var searchFocused: Bool

    private var subtitleSettings: SubtitleSettingsManager { .shared }

    // MARK: - Derived

    /// Current sentence ID for auto-scroll.
    private var currentSentenceId: Int? {
        guard viewModel.isCurrentEpisode else { return nil }
        return viewModel.transcriptSentences.first { $0.containsTime(currentPlaybackTime) }?.id
    }

    /// Timestamp of the top-visible sentence during scrolling.
    private var scrollTimestamp: String? {
        guard let id = topVisibleSentenceId else { return nil }
        return viewModel.transcriptSentences.first { $0.id == id }?.formattedStartTime
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Always-visible search bar / toolbar
            TranscriptToolbar(
                viewModel: viewModel,
                searchFocused: $searchFocused,
                autoScrollEnabled: $autoScrollEnabled,
                onShowTranslationPicker: onShowTranslationPicker,
                onShowSubtitleSettings: onShowSubtitleSettings,
                onShowRegenerateOptions: onShowRegenerateConfirmation
            )
            .background(.ultraThinMaterial)
            Divider()

            // RSS transcript warning with regenerate option
            if viewModel.transcriptSource == "rss" && viewModel.hasTranscript {
                RSSTranscriptWarningBanner(
                    showRegenerateConfirmation: $showRegenerateConfirmation,
                    hasLocalAudio: viewModel.hasLocalAudio
                )
            }

            // Scrollable content area
            if viewModel.hasTranscript && !viewModel.isTranscriptProcessing {
                transcriptScrollContent
            } else {
                transcriptStatusSection
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: showRegenerateConfirmation) { _, isShowing in
            if isShowing {
                onShowRegenerateConfirmation()
                showRegenerateConfirmation = false
            }
        }
        .onChange(of: viewModel.transcriptSearchQuery) { _, newQuery in
            viewModel.updateSearchMatches(query: newQuery)
        }
        .task(id: playbackTimerActive) {
            // Task-based timer for playback updates — automatically cancelled when view disappears
            guard playbackTimerActive else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { break }
                if viewModel.isCurrentEpisode && viewModel.audioManager.isPlaying {
                    let newTime = viewModel.audioManager.currentTime
                    let timeDiff = abs(newTime - currentPlaybackTime)

                    if subtitleSettings.sentenceHighlightEnabled && !viewModel.hasExistingTranslation {
                        // Sentence highlight mode: update whenever the active segment changes
                        let currentSentence = viewModel.transcriptSentences.first { $0.containsTime(newTime) }
                        let oldSentence = viewModel.transcriptSentences.first { $0.containsTime(currentPlaybackTime) }
                        let newSegIdx = currentSentence?.segments.firstIndex { newTime >= $0.startTime && newTime <= $0.endTime }
                        let oldSegIdx = oldSentence?.segments.firstIndex { currentPlaybackTime >= $0.startTime && currentPlaybackTime <= $0.endTime }
                        if newSegIdx != oldSegIdx || currentSentence?.id != oldSentence?.id || timeDiff >= 0.5 {
                            currentPlaybackTime = newTime
                        }
                    } else {
                        // Default mode: skip update if time diff < 0.5s and sentence unchanged
                        if timeDiff >= 0.5 {
                            currentPlaybackTime = newTime
                        } else {
                            let newSentenceId = viewModel.transcriptSentences.first { $0.containsTime(newTime) }?.id
                            let oldSentenceId = currentSentenceId
                            if newSentenceId != oldSentenceId {
                                currentPlaybackTime = newTime
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            playbackTimerActive = true
            if viewModel.isCurrentEpisode {
                currentPlaybackTime = viewModel.audioManager.currentTime
            }
        }
        .onDisappear {
            playbackTimerActive = false
        }
    }

    // MARK: - Transcript Scroll Content

    private var transcriptScrollContent: some View {
        let sentences = viewModel.transcriptSentences
        let currentTime: TimeInterval? = viewModel.isCurrentEpisode ? currentPlaybackTime : nil
        let searchQuery = viewModel.transcriptSearchQuery
        let searchMatchIdSet = Set(viewModel.searchMatchIds)
        let currentSearchMatchId: Int? = viewModel.searchMatchIds.isEmpty
            ? nil : viewModel.searchMatchIds[viewModel.currentMatchIndex]
        let highlightEnabled = subtitleSettings.sentenceHighlightEnabled && !viewModel.hasExistingTranslation
        let displayMode = subtitleSettings.displayMode

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: highlightEnabled ? 4 : 14) {
                    Color.clear.frame(height: 0).id("transcriptTop")
                    if !searchQuery.isEmpty,
                       !viewModel.searchMatchIds.isEmpty {
                        TranscriptSearchNavigationBar(
                            matchCount: viewModel.searchMatchIds.count,
                            currentIndex: viewModel.currentMatchIndex,
                            onPrevious: { _ = viewModel.previousMatch() },
                            onNext: { _ = viewModel.nextMatch() }
                        )
                        .padding(.vertical, 4)
                    }

                    // Sentences inlined (not wrapped in SentenceBasedTranscriptView)
                    // so .scrollPosition(id:) can track individual sentence IDs
                    ForEach(sentences) { sentence in
                        let highlightState = TranscriptGrouping.highlightState(
                            for: sentence,
                            currentTime: currentTime
                        )
                        SentenceView(
                            sentence: sentence,
                            highlightState: highlightState,
                            searchQuery: searchQuery,
                            subtitleMode: displayMode,
                            sentenceHighlightEnabled: highlightEnabled,
                            isSearchMatch: searchMatchIdSet.contains(sentence.id),
                            isCurrentSearchMatch: currentSearchMatchId == sentence.id,
                            onSegmentTap: { segment in
                                // Immediately move the highlight to the tapped sentence so
                                // the view responds before the 250ms polling timer fires.
                                currentPlaybackTime = segment.startTime
                                viewModel.seekToSegment(segment)
                            }
                        )
                        .equatable()
                        .id(sentence.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .scrollTargetLayout()
            }
            .overlay(alignment: .topTrailing) {
                if showScrollTimestamp, let timestamp = scrollTimestamp {
                    Text(timestamp)
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .scrollPosition(id: $topVisibleSentenceId, anchor: .top)
            .trackScrollForHeaderCollapse(
                isHeaderVisible: $isHeaderVisible,
                lastOffset: $lastScrollOffset,
                isUserScrolling: isUserScrolling
            )
            .onScrollPhaseChange { oldPhase, newPhase in
                if newPhase == .interacting { autoScrollEnabled = false }
                isUserScrolling = newPhase == .interacting || newPhase == .decelerating
                // Show timestamp when user starts scrolling
                if newPhase == .interacting && !showScrollTimestamp {
                    withAnimation(.easeIn(duration: 0.15)) {
                        showScrollTimestamp = true
                    }
                }
                // Hide timestamp indicator when scrolling stops
                if newPhase == .idle && oldPhase != .idle {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showScrollTimestamp = false
                    }
                }
            }
            .onChange(of: currentSentenceId) { _, newId in
                guard autoScrollEnabled,
                      let id = newId,
                      viewModel.transcriptSearchQuery.isEmpty else { return }
                withAnimation(.spring(duration: 0.5, bounce: 0.1)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onChange(of: viewModel.currentMatchIndex) { _, _ in
                guard !viewModel.searchMatchIds.isEmpty else { return }
                let matchId = viewModel.searchMatchIds[viewModel.currentMatchIndex]
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(matchId, anchor: .center)
                }
            }
            .onChange(of: scrollToTopTrigger) { _, _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("transcriptTop", anchor: .top)
                }
                isHeaderVisible = true
            }
        }
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
