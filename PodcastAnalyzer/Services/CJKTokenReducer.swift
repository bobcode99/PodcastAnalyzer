//
//  CJKTokenReducer.swift
//  PodcastAnalyzer
//
//  Reduces token consumption for CJK text by translating to English before AI processing.
//  Ported from https://github.com/bobcode99/cjk-token-reducer
//

import CryptoKit
import Foundation
import OSLog

/// Nonisolated container for the logger to avoid @MainActor default in app target.
private nonisolated enum CJKLog {
    static let logger = Logger(subsystem: "com.podcast.analyzer", category: "CJKTokenReducer")
}

// MARK: - Language Detection

nonisolated enum CJKLanguage: String, Sendable {
    case chinese = "zh-TW"
    case japanese = "ja"
    case korean = "ko"
    case english = "en"
    case unknown = "auto"
}

nonisolated struct LanguageDetectionResult: Sendable {
    let language: CJKLanguage
    let ratio: Double  // 0.0 to 1.0, proportion of CJK characters
}

nonisolated struct LanguageDetector {
    /// CJK Unicode ranges for character classification
    private static let chineseRanges: [ClosedRange<UInt32>] = [
        0x4E00...0x9FFF,    // CJK Unified Ideographs
        0x3400...0x4DBF,    // Extension A
        0x20000...0x2A6DF,  // Extension B
        0x2A700...0x2B73F,  // Extension C
        0x2B740...0x2B81F,  // Extension D
    ]

    private static let hiraganaRange: ClosedRange<UInt32> = 0x3040...0x309F
    private static let katakanaRange: ClosedRange<UInt32> = 0x30A0...0x30FF
    private static let hangulSyllablesRange: ClosedRange<UInt32> = 0xAC00...0xD7AF
    private static let hangulJamoRange: ClosedRange<UInt32> = 0x1100...0x11FF

    static func detect(_ text: String) -> LanguageDetectionResult {
        guard !text.isEmpty else {
            return LanguageDetectionResult(language: .unknown, ratio: 0)
        }

        var chineseCount = 0
        var japaneseCount = 0
        var koreanCount = 0
        var totalNonWhitespace = 0

        for scalar in text.unicodeScalars {
            guard !scalar.properties.isWhitespace else { continue }
            totalNonWhitespace += 1

            let value = scalar.value

            let isChinese = chineseRanges.contains { $0.contains(value) }
            let isHiragana = hiraganaRange.contains(value)
            let isKatakana = katakanaRange.contains(value)
            let isHangul = hangulSyllablesRange.contains(value) || hangulJamoRange.contains(value)

            if isChinese { chineseCount += 1 }
            if isHiragana || isKatakana { japaneseCount += 1 }
            if isHangul { koreanCount += 1 }
        }

        guard totalNonWhitespace > 0 else {
            return LanguageDetectionResult(language: .unknown, ratio: 0)
        }

        // Weighted scoring — Japanese gets partial credit for shared Kanji
        let japaneseScore = Double(japaneseCount) + Double(chineseCount) / 3.0
        let chineseScore = Double(chineseCount)
        let koreanScore = Double(koreanCount)

        let totalCJK = chineseCount + japaneseCount + koreanCount
        let ratio = Double(totalCJK) / Double(totalNonWhitespace)

        let maxScore = max(japaneseScore, chineseScore, koreanScore)
        let language: CJKLanguage
        if maxScore == 0 {
            language = .english
        } else if japaneseScore == maxScore && japaneseCount > 0 {
            language = .japanese
        } else if koreanScore == maxScore {
            language = .korean
        } else {
            language = .chinese
        }

        return LanguageDetectionResult(language: language, ratio: ratio)
    }
}

// MARK: - Segment Preservation

nonisolated struct PreservedSegment: Sendable {
    let placeholder: String
    let original: String
}

nonisolated struct PreservationResult: Sendable {
    let textWithPlaceholders: String
    let segments: [PreservedSegment]
}

nonisolated struct SegmentPreserver {
    /// Placeholder prefix using zero-width space (invisible in most rendering)
    private static let placeholderPrefix = "\u{FEFF}PRSV"
    private static let placeholderSuffix = "\u{FEFF}"

    static func preserve(_ text: String) -> PreservationResult {
        var result = text
        var segments: [PreservedSegment] = []
        var index = 0

        func addPlaceholder(for original: String) -> String {
            let placeholder = "\(placeholderPrefix)\(index)\(placeholderSuffix)"
            segments.append(PreservedSegment(placeholder: placeholder, original: original))
            index += 1
            return placeholder
        }

        // 1. Code blocks (```...```)
        let codeBlockPattern = try! NSRegularExpression(pattern: "```[\\s\\S]*?```", options: [])
        let codeBlockMatches = codeBlockPattern.matches(
            in: result, range: NSRange(result.startIndex..., in: result)
        )
        for match in codeBlockMatches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let original = String(result[range])
            let placeholder = addPlaceholder(for: original)
            result.replaceSubrange(range, with: placeholder)
        }

        // 2. Inline code (`...`)
        let inlineCodePattern = try! NSRegularExpression(pattern: "`[^`]+`", options: [])
        let inlineMatches = inlineCodePattern.matches(
            in: result, range: NSRange(result.startIndex..., in: result)
        )
        for match in inlineMatches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let original = String(result[range])
            let placeholder = addPlaceholder(for: original)
            result.replaceSubrange(range, with: placeholder)
        }

        // 3. URLs
        let urlPattern = try! NSRegularExpression(pattern: "https?://[^\\s,;)>\\]]+", options: [])
        let urlMatches = urlPattern.matches(
            in: result, range: NSRange(result.startIndex..., in: result)
        )
        for match in urlMatches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let original = String(result[range])
            let placeholder = addPlaceholder(for: original)
            result.replaceSubrange(range, with: placeholder)
        }

        // 4. English technical terms (camelCase, PascalCase, SCREAMING_CASE)
        let techTermPattern = try! NSRegularExpression(
            pattern:
                "\\b(?:[a-z]+[A-Z][a-zA-Z]*|[A-Z][a-z]+[A-Z][a-zA-Z]*|[A-Z]{2,}(?:_[A-Z]{2,})+)\\b",
            options: []
        )
        let techMatches = techTermPattern.matches(
            in: result, range: NSRange(result.startIndex..., in: result)
        )
        for match in techMatches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let original = String(result[range])
            let placeholder = addPlaceholder(for: original)
            result.replaceSubrange(range, with: placeholder)
        }

        return PreservationResult(textWithPlaceholders: result, segments: segments)
    }

    static func restore(_ text: String, segments: [PreservedSegment]) -> String {
        var result = text
        for segment in segments {
            result = result.replacingOccurrences(of: segment.placeholder, with: segment.original)
        }
        return result
    }
}

// MARK: - Token Estimation

nonisolated struct TokenEstimator {
    /// Estimate token count for CJK text (~1.5 tokens per CJK char)
    static func estimateCJKTokens(_ text: String) -> Int {
        var cjkChars = 0
        var nonCJKChars = 0
        for scalar in text.unicodeScalars {
            if CJKTextUtils.isCJKScalar(scalar) {
                cjkChars += 1
            } else if !scalar.properties.isWhitespace {
                nonCJKChars += 1
            }
        }
        return Int(ceil(Double(cjkChars) * 1.5 + Double(nonCJKChars) * 0.25))
    }

    /// Estimate token count for English text (~0.25 tokens per char, i.e. 1 per 4 chars)
    static func estimateEnglishTokens(_ text: String) -> Int {
        let nonWhitespace = text.unicodeScalars.filter { !$0.properties.isWhitespace }.count
        return max(1, Int(ceil(Double(nonWhitespace) * 0.25)))
    }
}

// MARK: - Translation Result

nonisolated struct CJKTranslationResult: Sendable {
    let original: String
    let translated: String
    let wasTranslated: Bool
    let sourceLanguage: CJKLanguage
    let originalTokenEstimate: Int
    let translatedTokenEstimate: Int

    var tokenSavingsPercent: Double {
        guard originalTokenEstimate > 0, wasTranslated else { return 0 }
        return Double(originalTokenEstimate - translatedTokenEstimate)
            / Double(originalTokenEstimate) * 100
    }
}

// MARK: - Cache Entry (nonisolated for Codable synthesis)

private nonisolated struct CacheEntry: Codable, Sendable {
    let translated: String
    let createdAt: Date
}

// MARK: - CJK Token Reducer Actor

/// Actor that manages CJK→English translation for token reduction.
/// All mutable state (cache directory) is actor-isolated; helper structs are nonisolated.
actor CJKTokenReducer {
    static let shared = CJKTokenReducer()

    /// Minimum CJK ratio to trigger translation
    private let threshold: Double = 0.1
    /// Max characters per chunk for Google Translate
    private let maxChunkSize = 4500
    /// Cache TTL in seconds (30 days)
    private let cacheTTL: TimeInterval = 30 * 24 * 3600

    private let cacheDirectory: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("cjk-token-reducer", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true
        )
    }

    /// Translate CJK text to English for token reduction
    func translateToEnglish(_ text: String) async -> CJKTranslationResult {
        let detection = LanguageDetector.detect(text)

        // Skip if not CJK or below threshold
        guard detection.language != .english,
            detection.language != .unknown,
            detection.ratio >= threshold
        else {
            return CJKTranslationResult(
                original: text,
                translated: text,
                wasTranslated: false,
                sourceLanguage: detection.language,
                originalTokenEstimate: TokenEstimator.estimateEnglishTokens(text),
                translatedTokenEstimate: TokenEstimator.estimateEnglishTokens(text)
            )
        }

        // Preserve code blocks, URLs, technical terms
        let preserved = SegmentPreserver.preserve(text)

        // Check cache
        let cacheKey = makeCacheKey(lang: detection.language, text: preserved.textWithPlaceholders)
        if let cached = loadFromCache(key: cacheKey) {
            let restored = SegmentPreserver.restore(cached, segments: preserved.segments)
            return CJKTranslationResult(
                original: text,
                translated: restored,
                wasTranslated: true,
                sourceLanguage: detection.language,
                originalTokenEstimate: TokenEstimator.estimateCJKTokens(text),
                translatedTokenEstimate: TokenEstimator.estimateEnglishTokens(restored)
            )
        }

        // Translate (with chunking for long text)
        let translated: String
        if preserved.textWithPlaceholders.count > maxChunkSize {
            let chunks = splitIntoChunks(preserved.textWithPlaceholders)
            translated = await translateChunksConcurrently(chunks, language: detection.language)
        } else {
            translated = await translateWithRetry(
                preserved.textWithPlaceholders, language: detection.language
            )
        }

        // Cache the result (before restoring placeholders)
        saveToCache(key: cacheKey, value: translated)

        // Restore preserved segments
        let restored = SegmentPreserver.restore(translated, segments: preserved.segments)

        return CJKTranslationResult(
            original: text,
            translated: restored,
            wasTranslated: true,
            sourceLanguage: detection.language,
            originalTokenEstimate: TokenEstimator.estimateCJKTokens(text),
            translatedTokenEstimate: TokenEstimator.estimateEnglishTokens(restored)
        )
    }

    // MARK: - Chunking

    /// Split text into chunks at sentence boundaries using single-pass reverse iteration
    private func splitIntoChunks(_ text: String) -> [String] {
        var chunks: [String] = []
        var remaining = text

        while remaining.count > maxChunkSize {
            let searchEnd = remaining.index(remaining.startIndex, offsetBy: maxChunkSize)
            let searchRange = remaining.startIndex..<searchEnd

            // Find best split point by priority (reverse search)
            let searchStr = String(remaining[searchRange])
            var splitIndex: String.Index?

            // Priority 1: CJK sentence endings (。！？)
            let cjkEndings: [Character] = ["\u{3002}", "\u{FF01}", "\u{FF1F}"]
            for char in cjkEndings {
                if let idx = searchStr.lastIndex(of: char) {
                    let candidate = remaining.index(
                        remaining.startIndex,
                        offsetBy: searchStr.distance(from: searchStr.startIndex, to: idx) + 1
                    )
                    if splitIndex == nil || candidate > splitIndex! {
                        splitIndex = candidate
                    }
                }
            }

            // Priority 2: Western sentence endings
            if splitIndex == nil {
                for char: Character in [".", "!", "?"] {
                    if let idx = searchStr.lastIndex(of: char) {
                        let offset = searchStr.distance(from: searchStr.startIndex, to: idx) + 1
                        let candidate = remaining.index(remaining.startIndex, offsetBy: offset)
                        if splitIndex == nil || candidate > splitIndex! {
                            splitIndex = candidate
                        }
                    }
                }
            }

            // Priority 3: Newlines
            if splitIndex == nil {
                if let idx = searchStr.lastIndex(of: "\n") {
                    splitIndex = remaining.index(
                        remaining.startIndex,
                        offsetBy: searchStr.distance(from: searchStr.startIndex, to: idx) + 1
                    )
                }
            }

            // Fallback: split at max size
            let actualSplit = splitIndex ?? searchEnd

            chunks.append(String(remaining[remaining.startIndex..<actualSplit]))
            remaining = String(remaining[actualSplit...])
        }

        if !remaining.isEmpty {
            chunks.append(remaining)
        }
        return chunks
    }

    /// Translate chunks concurrently with TaskGroup
    private func translateChunksConcurrently(
        _ chunks: [String], language: CJKLanguage
    ) async -> String {
        await withTaskGroup(of: (Int, String).self) { group in
            for (index, chunk) in chunks.enumerated() {
                group.addTask { [self] in
                    let translated = await self.translateWithRetry(chunk, language: language)
                    return (index, translated)
                }
            }

            var results = [(Int, String)]()
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1).joined()
        }
    }

    // MARK: - Google Translate API

    private func translateWithRetry(_ text: String, language: CJKLanguage) async -> String {
        // First attempt
        if let result = await callGoogleTranslate(text, sourceLanguage: language) {
            return result
        }

        // Retry after 1 second
        try? await Task.sleep(for: .seconds(1))
        if let result = await callGoogleTranslate(text, sourceLanguage: language) {
            return result
        }

        // Graceful degradation: return original
        CJKLog.logger.warning("Translation failed after retry, returning original text")
        return text
    }

    private nonisolated func callGoogleTranslate(
        _ text: String, sourceLanguage: CJKLanguage
    ) async -> String? {
        guard
            let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else {
            return nil
        }

        let urlString =
            "https://translate.googleapis.com/translate_a/single?client=gtx&sl=\(sourceLanguage.rawValue)&tl=en&dt=t&q=\(encoded)"

        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                (200...299).contains(httpResponse.statusCode)
            else {
                CJKLog.logger.error("Google Translate returned non-200 status")
                return nil
            }

            // Parse response: nested array [[["translated","original",...],...],...]
            guard let json = try JSONSerialization.jsonObject(with: data) as? [Any],
                let sentences = json.first as? [[Any]]
            else {
                CJKLog.logger.error("Failed to parse Google Translate response")
                return nil
            }

            return sentences.compactMap { $0.first as? String }.joined()
        } catch {
            CJKLog.logger.error("Google Translate request failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Caching

    private func makeCacheKey(lang: CJKLanguage, text: String) -> String {
        let input = "\(lang.rawValue)|en|\(text)"
        let hash = SHA256.hash(data: Data(input.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func loadFromCache(key: String) -> String? {
        let fileURL = cacheDirectory.appendingPathComponent("\(key).json")
        guard let data = try? Data(contentsOf: fileURL),
            let entry = try? JSONDecoder().decode(CacheEntry.self, from: data)
        else {
            return nil
        }

        // Check TTL
        guard Date().timeIntervalSince(entry.createdAt) < cacheTTL else {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }

        return entry.translated
    }

    private func saveToCache(key: String, value: String) {
        let entry = CacheEntry(translated: value, createdAt: Date())
        let fileURL = cacheDirectory.appendingPathComponent("\(key).json")
        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: fileURL)
        }
    }
}

// MARK: - CJKTextUtils Extension

nonisolated extension CJKTextUtils {
    /// Check if a Unicode scalar is in CJK ranges
    static func isCJKScalar(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        let ranges: [ClosedRange<UInt32>] = [
            0x4E00...0x9FFF,
            0x3400...0x4DBF,
            0x20000...0x2A6DF,
            0x2A700...0x2B73F,
            0x2B740...0x2B81F,
            0x3040...0x309F,
            0x30A0...0x30FF,
            0xAC00...0xD7AF,
            0x1100...0x11FF,
        ]
        return ranges.contains { $0.contains(value) }
    }
}
