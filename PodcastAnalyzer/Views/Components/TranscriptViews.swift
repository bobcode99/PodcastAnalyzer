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
//  - Optional: Word-level highlighting when accurate wordTimings exist
//

import SwiftUI

// MARK: - Transcript Sentence Model

/// A sentence composed of multiple transcript segments
/// Segments are grouped until a sentence-ending punctuation is found
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

// MARK: - Sentence Grouping Utilities

enum TranscriptGrouping {
    /// Sentence-ending punctuation marks (English and CJK)
    private static let sentenceEndings: Set<Character> = [".", "!", "?", "。", "！", "？"]

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
            highlighted.backgroundColor = .yellow.opacity(0.4)
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

// MARK: - Sentence-Based Transcript View (NEW - Primary View)

/// Displays transcript as sentences with segment-level highlighting within each sentence
/// This is the main transcript view used by EpisodeDetailView and ExpandedPlayerView
struct SentenceBasedTranscriptView: View {
    let segments: [TranscriptSegment]
    let currentTime: TimeInterval?
    let searchQuery: String
    let onSegmentTap: (TranscriptSegment) -> Void

    /// Whether to show timestamps on the left
    var showTimestamps: Bool = false

    /// Whether to enable word-level highlighting (requires wordTimings)
    var enableWordHighlighting: Bool = false

    @State private var settings = SubtitleSettingsManager.shared

    /// Sentences grouped from segments
    private var sentences: [TranscriptSentence] {
        TranscriptGrouping.groupIntoSentences(segments)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(sentences) { sentence in
                SentenceView(
                    sentence: sentence,
                    currentTime: currentTime,
                    searchQuery: searchQuery,
                    displayMode: settings.displayMode,
                    showTimestamp: showTimestamps,
                    enableWordHighlighting: enableWordHighlighting,
                    onSegmentTap: onSegmentTap
                )
                .id("sentence-\(sentence.id)")
            }
        }
    }
}

// MARK: - Sentence View (displays one sentence with segment highlighting)

/// Displays a single sentence with individual segment highlighting
struct SentenceView: View {
    let sentence: TranscriptSentence
    let currentTime: TimeInterval?
    let searchQuery: String
    let displayMode: SubtitleDisplayMode
    var showTimestamp: Bool = false
    var enableWordHighlighting: Bool = false
    let onSegmentTap: (TranscriptSegment) -> Void

    /// The currently active segment within this sentence
    private var activeSegment: TranscriptSegment? {
        guard let time = currentTime else { return nil }
        return sentence.activeSegment(at: time)
    }

    /// Whether any segment in this sentence is active
    private var isSentenceActive: Bool {
        guard let time = currentTime else { return false }
        return sentence.containsTime(time)
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
                        .foregroundColor(isSentenceActive ? .blue : .secondary)
                        .frame(width: 50, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 2) {
                    // Primary text with segment-level highlighting
                    buildSentenceText(isPrimary: true)
                        .font(.system(size: 17, weight: .regular))
                        .lineSpacing(4)

                    // Secondary text (translation) if in dual mode
                    if let translatedText = sentence.translatedText,
                       displayMode == .dualOriginalFirst || displayMode == .dualTranslatedFirst {
                        Text(translatedText)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.secondary)
                            .lineSpacing(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSentenceActive ? Color.blue.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    /// Builds the sentence text with segment-level highlighting
    @ViewBuilder
    private func buildSentenceText(isPrimary: Bool) -> some View {
        // If searching, just show search highlighting
        if !searchQuery.isEmpty {
            SearchHighlightedText(text: sentence.text, query: searchQuery)
        } else {
            // Build text with segment highlighting
            Text(buildSegmentHighlightedAttributedString())
        }
    }

    /// Builds an AttributedString where the active segment is highlighted
    private func buildSegmentHighlightedAttributedString() -> AttributedString {
        var result = AttributedString()
        let isCJK = CJKTextUtils.containsCJK(sentence.text)

        for (index, segment) in sentence.segments.enumerated() {
            let segmentText = segment.text.trimmingCharacters(in: .whitespaces)
            var attrText = AttributedString(segmentText)

            // Check if this segment is the active one
            let isActiveSegment = activeSegment?.id == segment.id

            if isActiveSegment {
                // Highlight the active segment
                attrText.foregroundColor = .blue
                attrText.font = .system(size: 17, weight: .semibold)
                attrText.backgroundColor = Color.blue.opacity(0.15)
            } else if let time = currentTime, time > segment.endTime {
                // Segment already played
                attrText.foregroundColor = .blue.opacity(0.7)
                attrText.font = .system(size: 17, weight: .medium)
            } else {
                // Segment not yet played
                attrText.foregroundColor = .primary.opacity(0.7)
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

// MARK: - Legacy FlowingTranscriptView (for backward compatibility)

/// A flowing paragraph-style transcript view with segment-level highlighting
/// NOTE: Consider using SentenceBasedTranscriptView for better sentence grouping
struct FlowingTranscriptView: View {
    let segments: [TranscriptSegment]
    let currentTime: TimeInterval?
    let searchQuery: String
    let onSegmentTap: (TranscriptSegment) -> Void

    var showTimestamps: Bool = false
    var enableWordHighlighting: Bool = false

    @State private var settings = SubtitleSettingsManager.shared

    var body: some View {
        // Use the new sentence-based view
        SentenceBasedTranscriptView(
            segments: segments,
            currentTime: currentTime,
            searchQuery: searchQuery,
            onSegmentTap: onSegmentTap,
            showTimestamps: showTimestamps,
            enableWordHighlighting: enableWordHighlighting
        )
    }
}

// MARK: - Word Highlighted Text (Optional - for accurate word timings)

/// Text view with word-by-word highlighting based on playback progress
/// Only used when accurate word timings are available from TranscriptService
///
/// enableWordHighlighting conditions:
/// 1. The segment must have wordTimings array populated
/// 2. wordTimings must come from TranscriptService.audioToSRTWithWordTimings()
/// 3. This is typically only accurate for on-device transcription
struct WordHighlightedText: View {
    let text: String
    let wordTimings: [WordTiming]
    let currentTime: TimeInterval?
    let searchQuery: String

    var body: some View {
        Text(buildAttributedString())
    }

    private func buildAttributedString() -> AttributedString {
        var result = AttributedString()
        let isCJKText = CJKTextUtils.containsCJK(text)

        guard let time = currentTime else {
            return AttributedString(text)
        }

        for (index, timing) in wordTimings.enumerated() {
            var wordAttr = AttributedString(timing.word)

            let isSpoken = time >= timing.endTime
            let isSpeaking = time >= timing.startTime && time < timing.endTime

            if isSpeaking {
                wordAttr.foregroundColor = .blue
                wordAttr.font = .system(size: 17, weight: .bold)
                wordAttr.backgroundColor = Color.blue.opacity(0.2)
            } else if isSpoken {
                wordAttr.foregroundColor = .blue
                wordAttr.font = .system(size: 17, weight: .semibold)
            } else {
                wordAttr.foregroundColor = .primary.opacity(0.6)
                wordAttr.font = .system(size: 17, weight: .regular)
            }

            if !searchQuery.isEmpty && timing.word.lowercased().contains(searchQuery.lowercased()) {
                wordAttr.backgroundColor = .yellow.opacity(0.4)
            }

            result.append(wordAttr)

            if !isCJKText && index < wordTimings.count - 1 {
                result.append(AttributedString(" "))
            }
        }

        return result
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
                        .foregroundColor(.purple)
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
                    .foregroundColor(.blue)
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
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
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
                                .foregroundColor(.blue)
                                .frame(width: 50, alignment: .leading)

                            Text(sentence.text)
                                .font(.subheadline)
                                .foregroundColor(sentence.id == currentSentence?.id ? .primary : .secondary)
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
            .background(Color.platformSystemGray6)
            .cornerRadius(12)
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
                // ACTIVE: blue, bold
                attrText.foregroundColor = .blue
                attrText.font = .system(size: 17, weight: .bold)
            } else if let time = currentTime, time > segment.endTime {
                // PAST: light blue, medium weight
                attrText.foregroundColor = .blue.opacity(0.7)
                attrText.font = .system(size: 17, weight: .medium)
            } else {
                // FUTURE: gray, regular weight
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

    /// Sentences for scroll tracking
    private var sentences: [TranscriptSentence] {
        TranscriptGrouping.groupIntoSentences(filteredSegments)
    }

    /// Current sentence ID based on time
    private var currentSentenceId: Int? {
        guard let time = currentTime else { return nil }
        return sentences.first { $0.containsTime(time) }?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
                TextField("Search transcript...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.platformSystemGray6)
            .cornerRadius(10)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Transcript with sentence grouping
            ScrollViewReader { proxy in
                ScrollView {
                    SentenceBasedTranscriptView(
                        segments: filteredSegments,
                        currentTime: currentTime,
                        searchQuery: searchQuery,
                        onSegmentTap: onSegmentTap,
                        showTimestamps: false,
                        enableWordHighlighting: false
                    )
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .onChange(of: currentSentenceId) { _, newId in
                    if let id = newId, searchQuery.isEmpty {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("sentence-\(id)", anchor: .center)
                        }
                    }
                }
            }
        }
    }
}
