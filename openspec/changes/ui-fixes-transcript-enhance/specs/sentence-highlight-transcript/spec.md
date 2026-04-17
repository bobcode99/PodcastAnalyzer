## ADDED Requirements

### Requirement: Sentence highlight display mode
The system SHALL provide a "Sentence Highlight" display mode in `SubtitleDisplayMode` that users can select from Settings. When enabled, transcript segments SHALL be merged into natural sentences (split on sentence-ending punctuation: . ! ? 。 ！ ？) with up to 8 segments per sentence. Sentences SHALL flow as continuous paragraphs without per-sentence visual dividers.

#### Scenario: Mode selectable in Settings
- **WHEN** user opens Settings > Subtitles > Display Mode
- **THEN** "Sentence Highlight" SHALL appear as a selectable option alongside existing modes

#### Scenario: Segments merged into sentences
- **WHEN** sentence highlight mode is active and transcript has segments: ["This BBC podcast is supported by ads", "outside the UK.", "If journalism is the 1st draft of", "history."]
- **THEN** display SHALL show two merged sentences: "This BBC podcast is supported by ads outside the UK." and "If journalism is the 1st draft of history."

#### Scenario: CJK segments merged without spaces
- **WHEN** sentence highlight mode is active and transcript segments contain CJK text
- **THEN** segments SHALL be merged without inserting spaces between them

### Requirement: Per-segment time-based highlighting during playback
When sentence highlight mode is active and audio is playing, the system SHALL highlight the currently active segment's text within the merged sentence display. Each segment's text portion SHALL be highlighted (blue, semibold) when playback time falls within that segment's time range. Played segments SHALL appear in secondary color, and future segments in primary color.

#### Scenario: First segment highlighted at start
- **WHEN** playback time is 00:00:01 and the first segment spans 00:00:00–00:00:02 with text "This BBC podcast is supported by ads"
- **THEN** "This BBC podcast is supported by ads" SHALL be displayed in blue semibold, and "outside the UK." in primary (normal) color

#### Scenario: Highlight advances to next segment
- **WHEN** playback time advances past 00:00:02,580 into the second segment spanning 00:00:02,580–00:00:03,899
- **THEN** "This BBC podcast is supported by ads" SHALL change to secondary (gray) color and "outside the UK." SHALL become blue semibold

#### Scenario: Cross-sentence highlight transition
- **WHEN** playback moves from the last segment of one sentence to the first segment of the next sentence
- **THEN** the previous sentence SHALL be fully gray (played) and the new sentence's first segment SHALL be blue semibold

#### Scenario: Tap to seek on segment text
- **WHEN** user taps on a segment's text within a merged sentence
- **THEN** playback SHALL seek to that segment's start time

### Requirement: Paragraph-style sentence grouping for highlight mode
In sentence highlight mode, the system SHALL use a more aggressive grouping strategy than the default (4 segments max). Sentences SHALL accumulate up to 8 segments before forcing a break, and SHALL only split on sentence-ending punctuation (. ! ? 。 ！ ？) or paragraph boundaries (double newline). A character limit of ~300 characters SHALL serve as a fallback break point for unpunctuated content.

#### Scenario: Long unpunctuated content splits at character limit
- **WHEN** 10 segments accumulate without sentence-ending punctuation and exceed 300 characters
- **THEN** the system SHALL force a sentence break at the most recent segment boundary

#### Scenario: Short punctuated content groups naturally
- **WHEN** segments contain sentence-ending punctuation within the first 3 segments
- **THEN** the sentence SHALL end at the punctuation, not waiting for 8 segments

### Requirement: Top Episodes row layout compact sizing
The Top Episodes row SHALL use 56pt artwork (down from 80pt), `.headline` font for rank number (down from `.title2`), 10pt spacing between elements, and the ellipsis menu SHALL be positioned inline within the row's `HStack` (not as an overlay). The row's vertical padding SHALL be 8pt.

#### Scenario: Compact row dimensions
- **WHEN** Top Episodes section renders on the Home tab
- **THEN** artwork SHALL be 56x56pt with 10pt corner radius, rank number SHALL use `.headline` font weight `.bold`, and row vertical padding SHALL be 8pt

#### Scenario: Ellipsis inline positioning
- **WHEN** a Top Episodes row displays
- **THEN** the ellipsis menu button SHALL appear as the last element in the row's `HStack`, immediately after the `Spacer`, not as a floating overlay

### Requirement: CJK sentence text spacing fix
`TranscriptSentence.text` and `TranscriptSentence.translatedText` computed properties SHALL use `CJKTextUtils.containsCJK()` to determine the join separator. CJK content SHALL use empty string separator; non-CJK content SHALL use space separator.

#### Scenario: Chinese transcript segments joined without spaces
- **WHEN** transcript has segments with Chinese text ["这个", "函数", "有问题"]
- **THEN** `TranscriptSentence.text` SHALL return "这个函数有问题" (no spaces)

#### Scenario: English transcript segments joined with spaces
- **WHEN** transcript has segments with English text ["This is", "a test"]
- **THEN** `TranscriptSentence.text` SHALL return "This is a test" (with spaces)
