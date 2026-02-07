//
//  TranscriptViews.swift
//  PodcastAnalyzer
//
//  Shared transcript display components with sentence-based layout
//  and segment-level highlighting within sentences.
//
//  Architecture:
//  - Segments are grouped into Sentences (until sentence-ending punctuation)
//  - Each sentence is displayed as one visual block
//  - Within a sentence, the currently playing segment is highlighted
//  - SentenceHighlightState enables efficient SwiftUI diffing
//

import SwiftUI

// MARK: - Transcript Sentence Model

/// A sentence composed of multiple transcript segments
struct TranscriptSentence: Identifiable {
    let id: Int
    let segments: [TranscriptSegment]

    /// Start time of the first segment
    var startTime: TimeInterval {
        segments.first?.startTime ?? 0
    }

    /// End time of the last segment
    var endTime: TimeInterval {
        segments.last?.endTime ?? 0
    }

    /// Combined text of all segments (with proper spacing)
    var text: String {
        segments.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
    }

    /// Combined translated text (if available)
    var translatedText: String? {
        let translations = segments.compactMap { $0.translatedText?.trimmingCharacters(in: .whitespaces) }
        guard translations.count == segments.count else { return nil }
        return translations.joined(separator: " ")
    }

    /// Formatted start time string
    var formattedStartTime: String {
        segments.first?.formattedStartTime ?? "0:00"
    }

    /// Check if a given time falls within this sentence
    func containsTime(_ time: TimeInterval) -> Bool {
        time >= startTime && time <= endTime
    }

    /// Find the segment that contains the given time
    /// Returns nil if time is in a gap between segments
    func activeSegment(at time: TimeInterval) -> TranscriptSegment? {
        segments.first { time >= $0.startTime && time <= $0.endTime }
    }
}

// MARK: - Sentence Highlight State

/// POD enum for efficient SwiftUI diffing — prevents 100-225 unnecessary re-renders per timer tick
enum SentenceHighlightState: Equatable {
    case active(activeSegmentIndex: Int)
    case played
    case future
}

// MARK: - Sentence Grouping Utilities

enum TranscriptGrouping {
    /// Sentence-ending punctuation marks (English and CJK)
    private static let sentenceEndings: Set<Character> = [".", "!", "?", "\u{3002}", "\u{FF01}", "\u{FF1F}"]

    /// Maximum segments per sentence to handle long unpunctuated streams
    static let maxSegmentsPerSentence = 4

    /// Check if text ends with a sentence-ending punctuation
    static func isSentenceEnd(_ text: String) -> Bool {
        guard let lastChar = text.trimmingCharacters(in: .whitespaces).last else { return false }
        return sentenceEndings.contains(lastChar)
    }

    /// Group segments into sentences
    /// Segments are accumulated until a segment ending with sentence punctuation is found
    /// or until maxSegmentsPerSentence is reached (handles long unpunctuated content)
    static func groupIntoSentences(_ segments: [TranscriptSegment]) -> [TranscriptSentence] {
        var sentences: [TranscriptSentence] = []
        var currentGroup: [TranscriptSegment] = []
        var sentenceId = 0

        for segment in segments {
            currentGroup.append(segment)

            // Check if this segment ends the sentence OR we've reached max segments
            let shouldEndSentence = isSentenceEnd(segment.text) ||
                                    currentGroup.count >= maxSegmentsPerSentence

            if shouldEndSentence {
                sentences.append(TranscriptSentence(id: sentenceId, segments: currentGroup))
                sentenceId += 1
                currentGroup = []
            }
        }

        // Add any remaining segments as the last sentence
        if !currentGroup.isEmpty {
            sentences.append(TranscriptSentence(id: sentenceId, segments: currentGroup))
        }

        return sentences
    }

    /// Compute highlight state for a sentence given the current playback time
    static func highlightState(for sentence: TranscriptSentence, currentTime: TimeInterval?) -> SentenceHighlightState {
        guard let time = currentTime else { return .future }

        if sentence.containsTime(time) {
            // Find which segment is active
            if let activeIndex = sentence.segments.firstIndex(where: { time >= $0.startTime && time <= $0.endTime }) {
                return .active(activeSegmentIndex: activeIndex)
            }
            // Time is in a gap between segments within the sentence
            return .active(activeSegmentIndex: -1)
        } else if time > sentence.endTime {
            return .played
        } else {
            return .future
        }
    }
}

// MARK: - CJK Text Utilities

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

    /// Tokenize text appropriately for CJK (character-by-character) or non-CJK (word-by-word)
    static func tokenize(_ text: String) -> [String] {
        if containsCJK(text) {
            return text.map { String($0) }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        } else {
            return text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        }
    }
}

// MARK: - Search Highlighted Text

/// Text view with search term highlighting
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
            let originalRange = Range(uncheckedBounds: (
                lower: text.index(text.startIndex, offsetBy: text.distance(from: text.startIndex, to: range.lowerBound)),
                upper: text.index(text.startIndex, offsetBy: text.distance(from: text.startIndex, to: range.upperBound))
            ))
            var highlighted = AttributedString(String(text[originalRange]))
            highlighted.backgroundColor = .yellow.opacity(0.3)
            highlighted.font = .system(size: 17, weight: .semibold)
            result.append(highlighted)

            currentIndex = range.upperBound
        }

        // Add remaining text
        if currentIndex < text.endIndex {
            result.append(AttributedString(String(text[currentIndex...])))
        }

        return result
    }
}

// MARK: - Sentence-Based Transcript View (Primary View)

/// Displays transcript as sentences with segment-level highlighting within each sentence
/// This is the main transcript view used by EpisodeDetailView and ExpandedPlayerView
struct SentenceBasedTranscriptView: View {
    let sentences: [TranscriptSentence]
    let currentTime: TimeInterval?
    let searchQuery: String
    let onSegmentTap: (TranscriptSegment) -> Void

    /// Whether to show timestamps on the left
    var showTimestamps: Bool = false

    /// Subtitle display mode
    var subtitleMode: SubtitleDisplayMode = .originalOnly

    /// Search match IDs for navigation highlight
    var searchMatchIds: Set<Int> = []

    /// Currently focused search match ID
    var currentSearchMatchId: Int?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(sentences) { sentence in
                let highlightState = TranscriptGrouping.highlightState(
                    for: sentence,
                    currentTime: currentTime
                )
                SentenceView(
                    sentence: sentence,
                    highlightState: highlightState,
                    searchQuery: searchQuery,
                    subtitleMode: subtitleMode,
                    showTimestamp: showTimestamps,
                    isSearchMatch: searchMatchIds.contains(sentence.id),
                    isCurrentSearchMatch: currentSearchMatchId == sentence.id,
                    onSegmentTap: onSegmentTap
                )
                .equatable()
                .id(sentence.id)
            }
        }
    }
}

// MARK: - Sentence View (displays one sentence with segment highlighting)

/// Displays a single sentence with individual segment highlighting.
/// Conforms to Equatable for efficient SwiftUI diffing with `.equatable()`.
struct SentenceView: View, Equatable {
    let sentence: TranscriptSentence
    let highlightState: SentenceHighlightState
    let searchQuery: String
    let subtitleMode: SubtitleDisplayMode
    var showTimestamp: Bool = false
    var isSearchMatch: Bool = false
    var isCurrentSearchMatch: Bool = false
    let onSegmentTap: (TranscriptSegment) -> Void

    static func == (lhs: SentenceView, rhs: SentenceView) -> Bool {
        lhs.sentence.id == rhs.sentence.id &&
        lhs.sentence.translatedText == rhs.sentence.translatedText &&
        lhs.highlightState == rhs.highlightState &&
        lhs.searchQuery == rhs.searchQuery &&
        lhs.subtitleMode == rhs.subtitleMode &&
        lhs.isSearchMatch == rhs.isSearchMatch &&
        lhs.isCurrentSearchMatch == rhs.isCurrentSearchMatch
    }

    /// Whether this sentence is the active one
    private var isActive: Bool {
        if case .active = highlightState { return true }
        return false
    }

    /// Primary text to display based on subtitle mode
    private var primaryText: String {
        switch subtitleMode {
        case .originalOnly, .dualOriginalFirst:
            return sentence.text
        case .translatedOnly, .dualTranslatedFirst:
            return sentence.translatedText ?? sentence.text
        }
    }

    /// Whether primary text uses translated content
    private var primaryIsTranslated: Bool {
        switch subtitleMode {
        case .originalOnly, .dualOriginalFirst:
            return false
        case .translatedOnly, .dualTranslatedFirst:
            return sentence.translatedText != nil
        }
    }

    /// Secondary text for dual modes (nil for single modes)
    private var secondaryText: String? {
        switch subtitleMode {
        case .originalOnly, .translatedOnly:
            return nil
        case .dualOriginalFirst:
            return sentence.translatedText
        case .dualTranslatedFirst:
            return sentence.translatedText != nil ? sentence.text : nil
        }
    }

    var body: some View {
        Button(action: {
            // Tap seeks to the first segment of the sentence
            if let firstSegment = sentence.segments.first {
                onSegmentTap(firstSegment)
            }
        }) {
            HStack(alignment: .top, spacing: showTimestamp ? 12 : 0) {
                // Timestamp (optional)
                if showTimestamp {
                    Text(sentence.formattedStartTime)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(isActive ? .blue : .secondary)
                        .frame(width: 50, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 4) {
                    // Primary text with segment-level highlighting
                    buildSentenceText()
                        .font(.system(size: 17, weight: .regular))
                        .lineSpacing(4)

                    // Secondary text for dual subtitle modes
                    if let secondary = secondaryText {
                        Text(secondary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .overlay(alignment: .leading) {
                // Active sentence accent bar
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.blue)
                    .frame(width: 3)
                    .opacity(isActive ? 1 : 0)
                    .scaleEffect(x: 1, y: isActive ? 1 : 0.5, anchor: .leading)
                    .animation(.easeInOut(duration: 0.25), value: isActive)
            }
        }
        .buttonStyle(.plain)
    }

    /// Builds the sentence text with segment-level or search highlighting
    @ViewBuilder
    private func buildSentenceText() -> some View {
        if !searchQuery.isEmpty {
            // Show search highlighting with yellow backgrounds
            SearchHighlightedText(text: primaryText, query: searchQuery)
        } else if primaryIsTranslated {
            // Translated text doesn't have segment-level timing, show as plain styled text
            Text(buildPlainStyledText(primaryText))
        } else {
            // Original text with segment highlighting
            Text(buildSegmentHighlightedAttributedString())
        }
    }

    /// Builds a plain styled AttributedString for translated text (no segment-level highlighting)
    private func buildPlainStyledText(_ text: String) -> AttributedString {
        var attrText = AttributedString(text)
        switch highlightState {
        case .active:
            attrText.foregroundColor = .blue
            attrText.font = .system(size: 17, weight: .semibold)
        case .played:
            attrText.foregroundColor = .secondary
            attrText.font = .system(size: 17, weight: .regular)
        case .future:
            attrText.foregroundColor = .primary
            attrText.font = .system(size: 17, weight: .regular)
        }
        return attrText
    }

    /// Builds an AttributedString with refined highlighting colors:
    /// - Active segment: blue foreground, semibold
    /// - Played segment: secondary foreground, regular
    /// - Future segment: primary foreground, regular
    private func buildSegmentHighlightedAttributedString() -> AttributedString {
        var result = AttributedString()
        let isCJK = CJKTextUtils.containsCJK(sentence.text)

        for (index, segment) in sentence.segments.enumerated() {
            let segmentText = segment.text.trimmingCharacters(in: .whitespaces)
            var attrText = AttributedString(segmentText)

            switch highlightState {
            case .active(let activeSegmentIndex):
                if index == activeSegmentIndex {
                    // Active segment: blue + semibold
                    attrText.foregroundColor = .blue
                    attrText.font = .system(size: 17, weight: .semibold)
                } else if index < activeSegmentIndex || (activeSegmentIndex == -1) {
                    // Played segment within active sentence
                    attrText.foregroundColor = .secondary
                    attrText.font = .system(size: 17, weight: .regular)
                } else {
                    // Future segment within active sentence
                    attrText.foregroundColor = .primary
                    attrText.font = .system(size: 17, weight: .regular)
                }
            case .played:
                attrText.foregroundColor = .secondary
                attrText.font = .system(size: 17, weight: .regular)
            case .future:
                attrText.foregroundColor = .primary
                attrText.font = .system(size: 17, weight: .regular)
            }

            result.append(attrText)

            // Add space between segments (not for CJK or last segment)
            if index < sentence.segments.count - 1 && !isCJK {
                result.append(AttributedString(" "))
            }
        }

        return result
    }
}

// MARK: - Search Navigation Bar

/// Floating search navigation overlay showing match count and prev/next buttons
struct TranscriptSearchNavigationBar: View {
    let matchCount: Int
    let currentIndex: Int
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\(currentIndex + 1) of \(matchCount)")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)

            Divider()
                .frame(height: 20)

            Button(action: onPrevious) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 14, weight: .semibold))
            }
            .disabled(matchCount == 0)

            Button(action: onNext) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
            }
            .disabled(matchCount == 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Compact Transcript Preview (for ExpandedPlayerView)

/// A compact preview showing current sentence and nearby segments
struct TranscriptPreviewView: View {
    let segments: [TranscriptSegment]
    let currentSegmentId: Int?
    let currentTime: TimeInterval?
    let onSegmentTap: (TranscriptSegment) -> Void
    let onExpandTap: () -> Void

    var previewCount: Int = 3

    /// Sentences for display
    private var sentences: [TranscriptSentence] {
        TranscriptGrouping.groupIntoSentences(segments)
    }

    /// Current sentence based on playback time
    private var currentSentence: TranscriptSentence? {
        guard let time = currentTime else { return sentences.first }
        return sentences.first { $0.containsTime(time) } ?? sentences.first
    }

    /// Active segment within current sentence
    private var activeSegmentInSentence: TranscriptSegment? {
        guard let time = currentTime else { return nil }
        return currentSentence?.activeSegment(at: time)
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "captions.bubble.fill")
                        .foregroundStyle(.purple)
                    Text("Transcript")
                        .font(.headline)
                }

                Spacer()

                Button(action: onExpandTap) {
                    HStack(spacing: 4) {
                        Text("Expand")
                            .font(.subheadline)
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption)
                    }
                    .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 20)

            // Current sentence with segment highlighting
            if let sentence = currentSentence {
                Text(buildPreviewAttributedString(for: sentence))
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .glassEffect(.regular.tint(.blue), in: .rect(cornerRadius: 12))
                    .padding(.horizontal, 16)
            }

            // Preview of nearby sentences
            VStack(spacing: 0) {
                ForEach(previewSentences) { sentence in
                    Button(action: {
                        if let firstSegment = sentence.segments.first {
                            onSegmentTap(firstSegment)
                        }
                    }) {
                        HStack(alignment: .top, spacing: 10) {
                            Text(sentence.formattedStartTime)
                                .font(.caption)
                                .foregroundStyle(.blue)
                                .frame(width: 50, alignment: .leading)

                            Text(sentence.text)
                                .font(.subheadline)
                                .foregroundStyle(sentence.id == currentSentence?.id ? .primary : .secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            sentence.id == currentSentence?.id
                            ? Color.blue.opacity(0.15)
                            : Color.clear
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
    }

    private var previewSentences: [TranscriptSentence] {
        guard !sentences.isEmpty else { return [] }

        let currentIdx = sentences.firstIndex { $0.id == currentSentence?.id } ?? 0
        let startIndex = max(0, currentIdx - 1)
        let endIndex = min(sentences.count, startIndex + previewCount)

        return Array(sentences[startIndex..<endIndex])
    }

    /// Build attributed string for preview with segment highlighting
    private func buildPreviewAttributedString(for sentence: TranscriptSentence) -> AttributedString {
        var result = AttributedString()
        let isCJK = CJKTextUtils.containsCJK(sentence.text)

        for (index, segment) in sentence.segments.enumerated() {
            let segmentText = segment.text.trimmingCharacters(in: .whitespaces)
            var attrText = AttributedString(segmentText)

            let isActive = activeSegmentInSentence?.id == segment.id

            if isActive {
                attrText.foregroundColor = .blue
                attrText.font = .system(size: 17, weight: .bold)
            } else if let time = currentTime, time > segment.endTime {
                attrText.foregroundColor = .secondary
                attrText.font = .system(size: 17, weight: .regular)
            } else {
                attrText.foregroundColor = .primary.opacity(0.6)
                attrText.font = .system(size: 17, weight: .regular)
            }

            result.append(attrText)

            if index < sentence.segments.count - 1 && !isCJK {
                result.append(AttributedString(" "))
            }
        }

        return result
    }
}

// MARK: - Full Transcript Sheet Content

/// Full-screen transcript view content (for use in sheets)
struct FullTranscriptContent: View {
    let segments: [TranscriptSegment]
    let currentSegmentId: Int?
    let currentTime: TimeInterval?
    @Binding var searchQuery: String
    let filteredSegments: [TranscriptSegment]
    let onSegmentTap: (TranscriptSegment) -> Void

    @State private var settings = SubtitleSettingsManager.shared

    /// Sentences for display (from filtered segments)
    private var sentences: [TranscriptSentence] {
        TranscriptGrouping.groupIntoSentences(filteredSegments)
    }

    /// Current sentence ID based on time
    private var currentSentenceId: Int? {
        guard let time = currentTime else { return nil }
        return sentences.first { $0.containsTime(time) }?.id
    }

    /// Search match IDs
    private var searchMatchIds: Set<Int> {
        guard !searchQuery.isEmpty else { return [] }
        return Set(sentences.compactMap { sentence in
            sentence.text.localizedStandardContains(searchQuery) ? sentence.id : nil
        })
    }

    @State private var currentSearchIndex: Int = 0
    @State private var searchMatchIdsList: [Int] = []

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
                TextField("Search transcript...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 14))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.platformSystemGray6)
            .clipShape(.rect(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Transcript with sentence grouping
            ScrollViewReader { proxy in
                ZStack(alignment: .bottom) {
                    ScrollView {
                        SentenceBasedTranscriptView(
                            sentences: sentences,
                            currentTime: currentTime,
                            searchQuery: searchQuery,
                            onSegmentTap: onSegmentTap,
                            showTimestamps: false,
                            subtitleMode: settings.displayMode,
                            searchMatchIds: searchMatchIds,
                            currentSearchMatchId: searchMatchIdsList.isEmpty ? nil : searchMatchIdsList[currentSearchIndex]
                        )
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .padding(.bottom, !searchQuery.isEmpty && !searchMatchIdsList.isEmpty ? 60 : 0)
                    }
                    .onChange(of: currentSentenceId) { _, newId in
                        if let id = newId, searchQuery.isEmpty {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }

                    // Search navigation bar
                    if !searchQuery.isEmpty && !searchMatchIdsList.isEmpty {
                        TranscriptSearchNavigationBar(
                            matchCount: searchMatchIdsList.count,
                            currentIndex: currentSearchIndex,
                            onPrevious: {
                                if !searchMatchIdsList.isEmpty {
                                    currentSearchIndex = (currentSearchIndex - 1 + searchMatchIdsList.count) % searchMatchIdsList.count
                                    withAnimation {
                                        proxy.scrollTo(searchMatchIdsList[currentSearchIndex], anchor: .center)
                                    }
                                }
                            },
                            onNext: {
                                if !searchMatchIdsList.isEmpty {
                                    currentSearchIndex = (currentSearchIndex + 1) % searchMatchIdsList.count
                                    withAnimation {
                                        proxy.scrollTo(searchMatchIdsList[currentSearchIndex], anchor: .center)
                                    }
                                }
                            }
                        )
                        .padding(.bottom, 8)
                    }
                }
            }
        }
        .onChange(of: searchQuery) { _, newQuery in
            // Recompute search matches
            if newQuery.isEmpty {
                searchMatchIdsList = []
                currentSearchIndex = 0
            } else {
                searchMatchIdsList = sentences.compactMap { sentence in
                    sentence.text.localizedStandardContains(newQuery) ? sentence.id : nil
                }
                currentSearchIndex = 0
            }
        }
    }
}
