//
//  CJKTokenReducerTests.swift
//  PodcastAnalyzerTests
//
//  Tests for LanguageDetector, SegmentPreserver, and TokenEstimator.
//

import Foundation
import Testing
@testable import PodcastAnalyzer

// MARK: - Language Detection Tests

@MainActor
struct LanguageDetectorTests {

    @Test func detectChinese() {
        let result = LanguageDetector.detect("这是一段中文测试文本")
        #expect(result.language == .chinese)
        #expect(result.ratio > 0.9)
    }

    @Test func detectJapanese() {
        // Contains Hiragana/Katakana which are uniquely Japanese
        let result = LanguageDetector.detect("これはテストです。日本語のテキストです。")
        #expect(result.language == .japanese)
        #expect(result.ratio > 0.8)
    }

    @Test func detectJapaneseWithKanji() {
        // Mixed Kanji + Hiragana — should still detect as Japanese
        let result = LanguageDetector.detect("東京は日本の首都です")
        #expect(result.language == .japanese)
    }

    @Test func detectKorean() {
        let result = LanguageDetector.detect("한국어 테스트 텍스트입니다")
        #expect(result.language == .korean)
        #expect(result.ratio > 0.8)
    }

    @Test func detectEnglish() {
        let result = LanguageDetector.detect("This is a simple English text for testing")
        #expect(result.language == .english)
        #expect(result.ratio == 0)
    }

    @Test func detectEmpty() {
        let result = LanguageDetector.detect("")
        #expect(result.language == .unknown)
        #expect(result.ratio == 0)
    }

    @Test func detectWhitespaceOnly() {
        let result = LanguageDetector.detect("   \n\t  ")
        #expect(result.language == .unknown)
        #expect(result.ratio == 0)
    }

    @Test func detectMixedBelowThreshold() {
        // Mostly English with a single CJK character
        let result = LanguageDetector.detect("This is English text with one 中 character in a long sentence here")
        // Ratio should be low since only 1 CJK char in many
        #expect(result.ratio < 0.1)
    }
}

// MARK: - Segment Preservation Tests

@MainActor
struct SegmentPreserverTests {

    @Test func preserveCodeBlocks() {
        let text = "这是代码 ```swift\nlet x = 1\n``` 结束"
        let result = SegmentPreserver.preserve(text)
        #expect(!result.textWithPlaceholders.contains("```"))
        #expect(result.segments.count >= 1)
        #expect(result.segments.first?.original.contains("let x = 1") == true)
    }

    @Test func preserveInlineCode() {
        let text = "使用 `forEach` 函数来遍历数组"
        let result = SegmentPreserver.preserve(text)
        #expect(!result.textWithPlaceholders.contains("`forEach`"))
        #expect(result.segments.contains { $0.original == "`forEach`" })
    }

    @Test func preserveURLs() {
        let text = "访问 https://example.com/path?q=1 获取更多信息"
        let result = SegmentPreserver.preserve(text)
        #expect(!result.textWithPlaceholders.contains("https://"))
        #expect(result.segments.contains { $0.original.contains("example.com") })
    }

    @Test func preserveCamelCase() {
        let text = "调用 myFunction 方法"
        let result = SegmentPreserver.preserve(text)
        // camelCase pattern: lowercase then uppercase
        // "myFunction" matches [a-z]+[A-Z][a-zA-Z]*
        #expect(result.segments.contains { $0.original == "myFunction" })
    }

    @Test func preserveSCREAMING_CASE() {
        let text = "设置 MAX_RETRY_COUNT 参数"
        let result = SegmentPreserver.preserve(text)
        #expect(result.segments.contains { $0.original == "MAX_RETRY_COUNT" })
    }

    @Test func roundTripPreservation() {
        let original = "这是 `code` 和 https://test.com 以及 myVariable 测试"
        let preserved = SegmentPreserver.preserve(original)
        let restored = SegmentPreserver.restore(preserved.textWithPlaceholders, segments: preserved.segments)
        #expect(restored == original)
    }

    @Test func preserveEmptyText() {
        let result = SegmentPreserver.preserve("")
        #expect(result.textWithPlaceholders == "")
        #expect(result.segments.isEmpty)
    }

    @Test func preservePlainCJK() {
        let text = "这是一段没有代码的中文文本"
        let result = SegmentPreserver.preserve(text)
        #expect(result.textWithPlaceholders == text)
        #expect(result.segments.isEmpty)
    }
}

// MARK: - Token Estimation Tests

@MainActor
struct TokenEstimatorTests {

    @Test func estimateCJKTokens() {
        // 5 CJK chars → ~7.5 → 8 tokens
        let count = TokenEstimator.estimateCJKTokens("这是测试文")
        #expect(count == 8)  // ceil(5 * 1.5)
    }

    @Test func estimateEnglishTokens() {
        // "hello world" = 10 non-whitespace chars → ceil(10 * 0.25) = 3
        let count = TokenEstimator.estimateEnglishTokens("hello world")
        #expect(count == 3)
    }

    @Test func estimateEnglishMinimum() {
        // Very short text should return at least 1
        let count = TokenEstimator.estimateEnglishTokens("hi")
        #expect(count >= 1)
    }

    @Test func estimateMixedTokens() {
        // Mixed CJK + English
        let count = TokenEstimator.estimateCJKTokens("Hello 世界")
        // "Hello" = 5 non-CJK → 5 * 0.25 = 1.25
        // "世界" = 2 CJK → 2 * 1.5 = 3.0
        // Total = ceil(4.25) = 5
        #expect(count == 5)
    }
}
