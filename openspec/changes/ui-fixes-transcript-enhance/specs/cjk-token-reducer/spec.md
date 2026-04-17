## ADDED Requirements

### Requirement: CJK language detection
The system SHALL detect whether input text is primarily CJK (Chinese, Japanese, Korean) by analyzing Unicode character ranges and computing a CJK ratio. Detection SHALL cover CJK Unified Ideographs (U+4E00–U+9FFF, extensions A–D), Hiragana (U+3040–U+309F), Katakana (U+30A0–U+30FF), and Hangul Syllables (U+AC00–U+D7AF). The system SHALL identify the dominant CJK language using weighted scoring (Japanese gets partial credit for shared Kanji characters).

#### Scenario: Chinese text detected
- **WHEN** input text is "这个函数有问题，需要修复"
- **THEN** detection returns language `.chinese` with ratio >= 0.8

#### Scenario: Japanese text with Kanji detected
- **WHEN** input text is "この関数に問題があります"
- **THEN** detection returns language `.japanese` with ratio >= 0.8

#### Scenario: Korean text detected
- **WHEN** input text is "이 함수에 문제가 있습니다"
- **THEN** detection returns language `.korean` with ratio >= 0.8

#### Scenario: English text skipped
- **WHEN** input text is "This function has a bug"
- **THEN** detection returns language `.english` with ratio < 0.1

#### Scenario: Mixed text with low CJK ratio
- **WHEN** input text has CJK ratio below threshold (0.1)
- **THEN** the system SHALL skip translation and return original text

### Requirement: Segment preservation
The system SHALL preserve code blocks, inline code, URLs, and English technical terms (camelCase, PascalCase, SCREAMING_CASE) by replacing them with unique placeholders before translation, and restoring them afterward. This prevents corruption of code identifiers, URLs, and technical vocabulary during translation.

#### Scenario: Code block preserved
- **WHEN** input contains a fenced code block (triple backticks)
- **THEN** the code block content SHALL be replaced with a placeholder before translation and restored identically afterward

#### Scenario: URL preserved
- **WHEN** input contains "https://example.com/api/v2"
- **THEN** the URL SHALL be preserved through translation unchanged

#### Scenario: camelCase term preserved
- **WHEN** input contains "getUserData" embedded in CJK text
- **THEN** the term SHALL be preserved through translation unchanged

#### Scenario: Placeholders restored after translation
- **WHEN** translation completes with placeholders in the output
- **THEN** all placeholders SHALL be replaced with original preserved content

### Requirement: Translation via Google Translate API
The system SHALL translate CJK text to English using the Google Translate free API (`translate.googleapis.com/translate_a/single`). For texts exceeding 4500 characters, the system SHALL split into chunks at sentence boundaries (CJK sentence endings 。！？ have priority, then Western . ! ?, then newlines). Chunks SHALL be translated concurrently using `TaskGroup`.

#### Scenario: Short text translated
- **WHEN** CJK text under 4500 characters is provided
- **THEN** the system SHALL make a single API call and return the English translation

#### Scenario: Long text chunked and translated
- **WHEN** CJK text exceeding 4500 characters is provided
- **THEN** the system SHALL split at sentence boundaries and translate chunks concurrently

#### Scenario: Translation failure graceful degradation
- **WHEN** the Google Translate API returns an error or times out
- **THEN** the system SHALL retry once after 1 second, and if still failing, return the original text without translation

### Requirement: Translation caching
The system SHALL cache translations using a SHA256 hash of (source language + target language + text with placeholders) as the key. Cache SHALL be stored as JSON files in the app's caches directory. Cached entries SHALL expire after 30 days.

#### Scenario: Cache hit
- **WHEN** the same text has been translated before and cache has not expired
- **THEN** the system SHALL return the cached translation without making an API call

#### Scenario: Cache miss
- **WHEN** text has not been translated before
- **THEN** the system SHALL call the API, cache the result, and return it

#### Scenario: Cache expiry
- **WHEN** a cached entry is older than 30 days
- **THEN** the system SHALL treat it as a miss and re-translate

### Requirement: Token count reporting
The system SHALL report estimated token counts for both original CJK text and translated English text. CJK estimation: ~1.5 tokens per CJK character. English estimation: ~0.25 tokens per character (1 token per 4 characters).

#### Scenario: Token savings reported
- **WHEN** a CJK transcript is translated to English
- **THEN** the system SHALL return both original and translated token counts so callers can log or display savings
