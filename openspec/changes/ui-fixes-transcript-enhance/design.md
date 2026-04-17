## Context

The app has four issues to address:

1. **Top Episodes layout** (`HomeView.swift`): `TrendingEpisodeRow` uses 80pt artwork and `.title2` rank — too large for the paged horizontal scroll. The ellipsis `Menu` is positioned as a `.overlay(alignment: .trailing)` which floats over the row's `Spacer` area, making it visually disconnected and positioned at the far right edge regardless of content width.

2. **CJK sentence spacing** (`TranscriptViews.swift` line 36): `TranscriptSentence.text` uses `joined(separator: " ")` unconditionally. The `buildSegmentHighlightedAttributedString()` at line 450 already handles CJK correctly (no space for CJK), but the plain `text` property does not. This causes the sentence preview text to show unwanted spaces between CJK characters.

3. **CJK token reducer**: The Rust project at `cjk-token-reducer` implements a Translate-Compute-Translate pattern — detect CJK ratio, preserve code/URLs/English terms with placeholders, translate via Google Translate free API, restore placeholders. This reduces token count by 35-50% for CJK text. Need a Swift port for on-device use.

4. **Sentence-merged highlight mode**: The current transcript groups segments into sentences (max 4 segments per sentence, split on sentence-ending punctuation). The existing `SentenceHighlightState.active(activeSegmentIndex:)` already highlights the active segment within a sentence. The new feature is essentially the same behavior — but the user wants it as a distinct, toggleable "paragraph-style" display where sentences flow more naturally (larger grouping, no per-sentence visual separation), and the per-segment highlighting is the primary UX.

## Goals / Non-Goals

**Goals:**
- Fix Top Episodes row to have compact, balanced layout with accessible ellipsis
- Fix CJK `TranscriptSentence.text` to not insert spaces between CJK segments
- Port CJK token reducer core to Swift (detection + preservation + translation + cache)
- Add sentence-highlight transcript mode toggleable from Settings
- Write unit tests for CJK token reducer

**Non-Goals:**
- Full Rust feature parity (circuit breaker, NLP entity recognition — keep it simple)
- Back-translating AI responses from English to CJK (one-directional only)
- Changing the existing segment/sentence display modes — additive only
- Word-level highlighting within segments (existing segment-level is sufficient)

## Decisions

### 1. Top Episodes Row Layout

**Decision**: Reduce artwork to 56pt, rank to `.headline`, add ellipsis as inline `Menu` within the `HStack` (not overlay).

**Rationale**: The overlay approach causes the ellipsis to float at the far-right edge regardless of content. Inline placement keeps it visually connected to the row. 56pt artwork matches Apple Podcasts "Browse" rows. The hidden `NavigationLink` background pattern stays — it works for tap navigation. The `Menu` just moves from overlay to inline within the row body.

**Alternative considered**: Keep overlay but with padding offset — rejected because it still disconnects visually on narrow content.

### 2. CJK Sentence Text Property

**Decision**: Use `CJKTextUtils.containsCJK()` in `TranscriptSentence.text` and `translatedText` to conditionally omit the space separator.

**Rationale**: The rendering code (`buildSegmentHighlightedAttributedString`) already does this at line 450. The `text` property is the only place that's inconsistent. One-line fix.

### 3. CJK Token Reducer Architecture

**Decision**: Single `CJKTokenReducer` actor with three components: `LanguageDetector` (struct), `SegmentPreserver` (struct), and the actor itself handling translation + caching.

**Rationale**:
- `actor` for thread safety on cache and network calls
- Struct helpers for pure functions (detection, preservation) — no shared state needed
- Use `URLSession` for Google Translate free API (no dependency)
- Cache with `FileManager` + `Codable` JSON (simple, no Core Data overhead)
- No circuit breaker — just retry once with 1s delay (simpler than Rust version; podcast transcripts are small)

**Alternative considered**: Using Apple's Translation framework — rejected because it requires iOS 17.4+, user confirmation dialog, and doesn't support programmatic batch translation without UI.

### 4. Sentence-Highlight Transcript Mode

**Decision**: Add a new `SubtitleDisplayMode` case `.sentenceHighlight` that reuses the existing `SentenceBasedTranscriptView` and `SentenceView` infrastructure but with visual changes:
- Remove per-sentence dividers/spacing — sentences flow as continuous paragraphs
- Keep per-segment highlighting (already exists in `buildSegmentHighlightedAttributedString`)
- Use a more aggressive sentence grouping (up to 8 segments per sentence instead of 4, split only on sentence-ending punctuation)

**Rationale**: The existing highlighting already does exactly what's needed — blue+semibold for active segment, gray for played, normal for future. The difference is presentation: instead of visually separated sentence blocks, it flows as a paragraph. Reusing the existing infrastructure means minimal new code.

**Alternative considered**: Completely new transcript view — rejected because 90% of the logic already exists. The `SentenceView` just needs a "compact/paragraph" variant.

### 5. Settings Integration

**Decision**: Add `.sentenceHighlight` to `SubtitleDisplayMode` enum with display name "Sentence Highlight". The picker in Settings already uses `CaseIterable` so it auto-appears.

**Rationale**: Minimal change. The enum is `CaseIterable` and the Settings picker iterates all cases. Just add the case and its display name.

## Risks / Trade-offs

- **Google Translate free API rate limits** → Mitigation: cache aggressively (SHA256 key), retry once, degrade gracefully (return original text on failure). Transcript text is typically translated once and cached.
- **CJK detection false positives** (e.g., emoji in CJK ranges) → Mitigation: use the same proven Unicode ranges from the Rust project, require ratio >= 10% threshold.
- **Sentence grouping too aggressive** (8 segments could create very long paragraphs) → Mitigation: also split on paragraph breaks (double newline) and keep max character limit (~300 chars) as fallback.
- **Token reducer adds latency** → Mitigation: run translation async before AI analysis, cache results, show progress indicator. Not on the critical playback path.
