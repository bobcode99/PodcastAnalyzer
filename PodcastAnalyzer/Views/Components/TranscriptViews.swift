//
//  TranscriptViews.swift
//  PodcastAnalyzer
//
//  Shared transcript display components for flowing sentence-based layout
//  with segment-level highlighting (word-level highlighting optional when timings available)
//

import SwiftUI

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
            // For CJK text, split by character (excluding whitespace tokens)
            return text.map { String($0) }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        } else {
            // For non-CJK text, split by words
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

            // Add highlighted match (use original case)
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

// MARK: - Flowing Transcript View (Segment-Based Highlighting)

/// A flowing paragraph-style transcript view with segment-level highlighting
/// Word-level highlighting is optional and only used when accurate word timings are available
struct FlowingTranscriptView: View {
    let segments: [TranscriptSegment]
    let currentTime: TimeInterval?
    let searchQuery: String
    let onSegmentTap: (TranscriptSegment) -> Void

    /// Whether to show timestamps on the left
    var showTimestamps: Bool = false

    /// Whether to attempt word-level highlighting (only effective when wordTimings exist)
    var enableWordHighlighting: Bool = false

    @State private var settings = SubtitleSettingsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(segments) { segment in
                let isCurrentSegment = isSegmentActive(segment)

                FlowingSegmentText(
                    segment: segment,
                    isActive: isCurrentSegment,
                    currentTime: currentTime,
                    searchQuery: searchQuery,
                    displayMode: settings.displayMode,
                    showTimestamp: showTimestamps,
                    enableWordHighlighting: enableWordHighlighting,
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
}

// MARK: - Flowing Segment Text

/// Individual segment rendered as flowing text with segment highlighting
/// Word-level highlighting only active when enableWordHighlighting is true AND wordTimings exist
struct FlowingSegmentText: View {
    let segment: TranscriptSegment
    let isActive: Bool
    let currentTime: TimeInterval?
    let searchQuery: String
    let displayMode: SubtitleDisplayMode
    var showTimestamp: Bool = false
    var enableWordHighlighting: Bool = false
    let onTap: () -> Void

    var body: some View {
        let (primary, secondary) = segment.displayText(mode: displayMode)

        Button(action: onTap) {
            HStack(alignment: .top, spacing: showTimestamp ? 12 : 0) {
                // Timestamp (optional)
                if showTimestamp {
                    Text(segment.formattedStartTime)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(isActive ? .blue : .secondary)
                        .frame(width: 50, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 2) {
                    // Primary text with highlighting
                    buildHighlightedText(primary, isPrimary: true)
                        .font(.system(size: 17, weight: isActive ? .medium : .regular))
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
            }
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
        // Use word-level highlighting only if:
        // 1. This segment is active
        // 2. It's the primary text
        // 3. Word highlighting is enabled
        // 4. Word timings exist and are accurate
        if isActive, isPrimary, enableWordHighlighting, let timings = segment.wordTimings, !timings.isEmpty {
            WordHighlightedText(
                text: text,
                wordTimings: timings,
                currentTime: currentTime,
                searchQuery: searchQuery
            )
        } else if !searchQuery.isEmpty {
            // Search highlighting only
            SearchHighlightedText(text: text, query: searchQuery)
        } else {
            // Plain text with segment-level styling
            Text(text)
                .foregroundColor(isActive && isPrimary ? .primary : (isPrimary ? .primary : .secondary))
        }
    }
}

// MARK: - Word Highlighted Text (Optional - for when accurate timings exist)

/// Text view with word-by-word highlighting based on playback progress
/// Only used when accurate word timings are available from the transcription
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

        // Use word timings for precise highlighting
        guard let time = currentTime else {
            // No current time - show plain text
            return AttributedString(text)
        }

        for (index, timing) in wordTimings.enumerated() {
            var wordAttr = AttributedString(timing.word)

            let isSpoken = time >= timing.endTime
            let isSpeaking = time >= timing.startTime && time < timing.endTime

            if isSpeaking {
                // Currently speaking this word
                wordAttr.foregroundColor = .blue
                wordAttr.font = .system(size: 17, weight: .bold)
                wordAttr.backgroundColor = Color.blue.opacity(0.2)
            } else if isSpoken {
                // Already spoken
                wordAttr.foregroundColor = .blue
                wordAttr.font = .system(size: 17, weight: .semibold)
            } else {
                // Not yet spoken
                wordAttr.foregroundColor = .primary.opacity(0.6)
                wordAttr.font = .system(size: 17, weight: .regular)
            }

            // Apply search highlighting if applicable
            if !searchQuery.isEmpty && timing.word.lowercased().contains(searchQuery.lowercased()) {
                wordAttr.backgroundColor = .yellow.opacity(0.4)
            }

            result.append(wordAttr)

            // Add space after word for non-CJK text
            if !isCJKText && index < wordTimings.count - 1 {
                result.append(AttributedString(" "))
            }
        }

        return result
    }
}

// MARK: - Compact Transcript Preview (for ExpandedPlayerView)

/// A compact preview showing current segment and a few upcoming segments
struct TranscriptPreviewView: View {
    let segments: [TranscriptSegment]
    let currentSegmentId: Int?
    let currentTime: TimeInterval?
    let onSegmentTap: (TranscriptSegment) -> Void
    let onExpandTap: () -> Void

    /// Number of segments to show in preview
    var previewCount: Int = 4

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

            // Current segment highlight
            if let currentText = currentSegmentText {
                Text(currentText)
                    .font(.body)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
            }

            // Preview of nearby segments
            VStack(spacing: 0) {
                ForEach(previewSegments, id: \.id) { segment in
                    Button(action: { onSegmentTap(segment) }) {
                        HStack(alignment: .top, spacing: 10) {
                            Text(segment.formattedStartTime)
                                .font(.caption)
                                .foregroundColor(.blue)
                                .frame(width: 50, alignment: .leading)

                            Text(segment.text)
                                .font(.subheadline)
                                .foregroundColor(currentSegmentId == segment.id ? .primary : .secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            currentSegmentId == segment.id
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

    private var currentSegmentText: String? {
        guard let id = currentSegmentId,
              let segment = segments.first(where: { $0.id == id }) else {
            return nil
        }
        return segment.text
    }

    private var previewSegments: [TranscriptSegment] {
        guard !segments.isEmpty else { return [] }

        let currentId = currentSegmentId ?? 0
        let startIndex = max(0, currentId - 1)
        let endIndex = min(segments.count, startIndex + previewCount)

        return Array(segments[startIndex..<endIndex])
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

            // Transcript segments
            ScrollViewReader { proxy in
                ScrollView {
                    FlowingTranscriptView(
                        segments: filteredSegments,
                        currentTime: currentTime,
                        searchQuery: searchQuery,
                        onSegmentTap: onSegmentTap,
                        showTimestamps: false,
                        enableWordHighlighting: false  // Segment-level highlighting by default
                    )
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .onChange(of: currentSegmentId) { _, newId in
                    if let id = newId, searchQuery.isEmpty {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("segment-\(id)", anchor: .center)
                        }
                    }
                }
            }
        }
    }
}
