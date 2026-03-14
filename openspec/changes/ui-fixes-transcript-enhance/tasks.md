## 1. UI Quick Fixes

- [x] 1.1 Fix CJK sentence spacing: Update `TranscriptSentence.text` and `translatedText` in `TranscriptViews.swift` to use `CJKTextUtils.containsCJK()` for conditional join separator (empty for CJK, space for non-CJK)
- [x] 1.2 Fix Top Episodes row layout: In `HomeView.swift`, change `TrendingEpisodeRow` artwork from 80pt to 56pt (cornerRadius 10), rank font from `.title2` to `.headline`, vertical padding from 10pt to 8pt, spacing from 12 to 10
- [x] 1.3 Fix ellipsis positioning: In `TrendingEpisodeRowWithNav`, move ellipsis `Menu` from `.overlay(alignment: .trailing)` to inline as last element in the row's `HStack` body, and in `TrendingEpisodesListView` apply the same inline pattern
- [x] 1.4 Build and verify UI fixes on iOS simulator

## 2. CJK Token Reducer — Language Detection

- [x] 2.1 Create `Services/CJKTokenReducer.swift` with `LanguageDetector` struct: CJK Unicode range constants, `detectLanguage(_ text:) -> DetectionResult` with weighted scoring (Japanese gets Kanji partial credit), `Language` enum (.chinese, .japanese, .korean, .english, .unknown), ratio computation
- [x] 2.2 Write unit tests for language detection: Chinese, Japanese (with Kanji), Korean, English, mixed text below threshold, empty string

## 3. CJK Token Reducer — Segment Preservation

- [x] 3.1 Add `SegmentPreserver` struct: extract code blocks (triple backticks), inline code (single backticks), URLs (http/https), and English technical terms (camelCase, PascalCase, SCREAMING_CASE) → replace with unique placeholders, return mapping for restoration
- [x] 3.2 Add `restoreSegments` function to replace placeholders back with original content
- [x] 3.3 Write unit tests for preservation: code blocks, URLs, camelCase terms, round-trip preservation+restoration

## 4. CJK Token Reducer — Translation & Caching

- [x] 4.1 Add `CJKTokenReducer` actor with `translateToEnglish(_ text:)` method: detect language, preserve segments, call Google Translate free API (`translate.googleapis.com/translate_a/single`), restore segments, return `TranslationResult` with original/translated text and token counts
- [x] 4.2 Add chunking for texts > 4500 chars: single-pass reverse iteration splitting at CJK sentence endings (。！？), then Western (. ! ?), then newlines; translate chunks concurrently with `TaskGroup`
- [x] 4.3 Add file-based JSON cache: SHA256 key from (source lang + target lang + text), store in app caches directory, 30-day TTL expiry
- [x] 4.4 Add retry logic: retry once after 1s on failure, return original text on second failure (graceful degradation)
- [x] 4.5 Add token estimation helpers: CJK ~1.5 tokens/char, English ~0.25 tokens/char (1 per 4 chars)
- [x] 4.6 Write integration test for translation (mock URLSession or use live API with small text)

## 5. Sentence Highlight Transcript Mode

- [x] 5.1 Add `sentenceHighlight` case to `SubtitleDisplayMode` enum in `SubtitleSettingsModel.swift` with display name "Sentence Highlight"
- [x] 5.2 Add paragraph-style sentence grouping in `TranscriptGrouping`: new method `groupIntoParagraphSentences` with max 8 segments, 300-char fallback limit, split only on sentence-ending punctuation or double newlines
- [x] 5.3 In `EpisodeDetailViewModel`, expose `paragraphGroupedSentences` computed property using the new grouping when display mode is `.sentenceHighlight`
- [x] 5.4 In `transcriptContent` (EpisodeDetailView.swift), switch between `groupedSentences` and `paragraphGroupedSentences` based on display mode
- [x] 5.5 In `SentenceView`, when display mode is `.sentenceHighlight`: remove per-sentence accent bar, reduce vertical padding to 4pt, use continuous paragraph flow style
- [x] 5.6 Verify per-segment highlighting works in sentence highlight mode (existing `buildSegmentHighlightedAttributedString` should work unchanged — segments within larger sentences still have time ranges)
- [x] 5.7 Build and end-to-end test: load an SRT transcript, enable sentence highlight mode, verify merged display and per-segment highlighting during playback

## 6. Final Verification

- [x] 6.1 Build for iOS simulator — zero errors
- [x] 6.2 Run all unit tests (CJK detection, preservation, sentence grouping)
- [ ] 6.3 Manual test: Home tab Top Episodes layout, ellipsis menu, CJK transcript spacing, sentence highlight mode with playback
