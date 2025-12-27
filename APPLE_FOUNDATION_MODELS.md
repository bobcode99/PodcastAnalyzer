# Apple Foundation Models Integration

This document describes how PodcastAnalyzer uses Apple's on-device Foundation Models (Apple Intelligence) for AI-powered podcast episode analysis.

## Overview

PodcastAnalyzer leverages Apple's `FoundationModels` framework (iOS 26+/macOS 26+) to provide on-device AI analysis of podcast transcripts. All processing happens locally on the device, ensuring privacy and enabling offline functionality.

## Requirements

- **iOS 26.0+** or **macOS 26.0+**
- **Apple Intelligence enabled** in Settings → Apple Intelligence & Siri
- **Compatible hardware**: iPhone 15 Pro or newer, or M1+ Mac/iPad

## Architecture

### Core Components

```
┌─────────────────────────────────────────────────────────────────┐
│                    EpisodeDetailViewModel                        │
│  - Manages AI analysis state and results                        │
│  - Coordinates between UI and EpisodeAnalysisService            │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                   EpisodeAnalysisService (Actor)                 │
│  - Handles transcript chunking                                   │
│  - Manages hierarchical summarization                           │
│  - Uses LanguageModelSession for inference                      │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                      @Generable Models                           │
│  - EpisodeSummary, EpisodeTags, EpisodeEntities                │
│  - EpisodeHighlights, EpisodeAnswer, etc.                       │
└─────────────────────────────────────────────────────────────────┘
```

## @Generable Models

Apple's Foundation Models use the `@Generable` macro to define structured output schemas. Each model includes `@Guide` annotations that provide instructions to the LLM.

### EpisodeSummary

```swift
@Generable
struct EpisodeSummary {
    @Guide(description: "Concise 2-3 sentence summary of the main topic and key points")
    var summary: String

    @Guide(description: "List of 3-5 main topics or themes discussed, in order of importance")
    var mainTopics: [String]

    @Guide(description: "List of 3-5 key takeaways or insights from the episode")
    var keyTakeaways: [String]

    @Guide(description: "Target audience who would benefit most from this episode")
    var targetAudience: String

    @Guide(description: "Estimated engagement level: 'high', 'medium', or 'low'")
    var engagementLevel: String
}
```

### EpisodeTags

```swift
@Generable
struct EpisodeTags {
    var tags: [String]              // 5-10 relevant keywords
    var primaryCategory: String     // e.g., 'Technology', 'Business'
    var secondaryCategories: [String]
    var difficultyLevel: String     // 'beginner', 'intermediate', 'advanced'
    var technicalTerms: [String]    // Specialized vocabulary used
}
```

### EpisodeEntities

```swift
@Generable
struct EpisodeEntities {
    var people: [String]            // People mentioned by name
    var organizations: [String]     // Companies, institutions
    var products: [String]          // Products, technologies
    var locations: [String]         // Places mentioned
    var resources: [String]         // Books, articles, studies
}
```

### EpisodeHighlights

```swift
@Generable
struct EpisodeHighlights {
    var highlights: [String]        // 3-5 most impactful moments
    var bestQuote: String           // Most memorable quote
    var entertainingMoment: String? // Funniest moment
    var controversialPoint: String? // Most debatable point
    var actionItems: [String]       // Practical advice provided
}
```

### EpisodeAnswer (Q&A)

```swift
@Generable
struct EpisodeAnswer {
    var answer: String              // Direct answer to user's question
    var timestamp: String           // Approximate time in episode
    var confidence: String          // 'high', 'medium', 'low'
    var relatedTopics: [String]     // Related segments for context
}
```

## Token Management & Chunking

Apple's on-device models have strict context window limits (~4096 tokens total). The app implements a sophisticated chunking strategy to handle long transcripts.

### Context Budget

```swift
private let maxContextTokens = 4096
private let maxInputTokens = 800    // Conservative for input
private let maxOutputTokens = 400   // Reserved for output
private let promptOverhead = 250    // System prompt and formatting
```

### Token Estimation

Token counts are estimated based on language:

```swift
static func estimateTokenCount(for text: String, language: String = "en") -> Int {
    let isAsianLanguage = ["zh", "ja", "ko"].contains(langPrefix)
    // Asian languages: ~0.5 chars per token (CJK characters often = 2-3 tokens)
    // English/European: ~2.5 chars per token (conservative)
    let charsPerToken = isAsianLanguage ? 0.5 : 2.5
    return Int(ceil(Double(text.count) / charsPerToken))
}
```

### Chunking Strategy

The `SRTParser.chunkText()` method splits transcripts:

1. **Check if chunking needed**: If text fits in `maxTokens`, return as-is
2. **Split by sentences**: Uses regex for sentence boundaries (`. `, `? `, `! `)
3. **Accumulate sentences**: Add sentences until token limit approached
4. **Create chunks**: Each chunk respects the token budget

```swift
static func chunkText(_ text: String, maxTokens: Int = 3000, language: String = "en") -> [String] {
    // Split by sentences, accumulate until limit reached
    let sentences = splitIntoSentences(text)
    var chunks: [String] = []
    var currentChunk: [String] = []
    var currentTokenCount = 0

    for sentence in sentences {
        let sentenceTokens = estimateTokenCount(for: sentence, language: language)
        if currentTokenCount + sentenceTokens > maxTokens && !currentChunk.isEmpty {
            chunks.append(currentChunk.joined(separator: " "))
            currentChunk = [sentence]
            currentTokenCount = sentenceTokens
        } else {
            currentChunk.append(sentence)
            currentTokenCount += sentenceTokens
        }
    }
    // ... add final chunk
}
```

### Hierarchical Summarization

For long transcripts that exceed the context window:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Full Transcript                               │
│    (e.g., 60 minutes = ~12,000+ tokens)                         │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Split into chunks
                            ▼
┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐     ┌─────────┐
│ Chunk 1 │ │ Chunk 2 │ │ Chunk 3 │ │ Chunk 4 │ ... │ Chunk N │
│ ~800 tk │ │ ~800 tk │ │ ~800 tk │ │ ~800 tk │     │ ~800 tk │
└────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘     └────┬────┘
     │           │           │           │               │
     ▼           ▼           ▼           ▼               ▼
┌────────────────────────────────────────────────────────────────┐
│              Summarize each chunk (2-3 sentences)               │
└───────────────────────────┬────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Combined Summaries                           │
│               (still may exceed context limit)                   │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Condense if needed
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Final Structured Summary                       │
│               (EpisodeSummary with all fields)                  │
└─────────────────────────────────────────────────────────────────┘
```

### Chunk Sampling

When transcripts produce too many chunks (>20), the service samples evenly:

```swift
private func sampleChunks(_ chunks: [String], targetCount: Int) -> [(index: Int, content: String)] {
    // Always include first and last for context
    sampled.append((0, chunks[0]))

    // Calculate step size for even distribution
    let step = Double(chunks.count - 2) / Double(middleCount + 1)

    // Sample middle chunks at regular intervals
    for i in 1...middleCount {
        let index = Int(Double(i) * step)
        sampled.append((index, chunks[index]))
    }

    sampled.append((chunks.count - 1, chunks.last!))
    return sampled.sorted { $0.index < $1.index }
}
```

This ensures coverage across the entire episode while respecting processing limits.

## Analysis Features

### 1. Summary Generation

Generates comprehensive episode summaries with:
- Main overview (2-3 sentences)
- Key topics (3-5 items, ranked by importance)
- Key takeaways (3-5 actionable insights)
- Target audience identification
- Engagement level assessment

**Multi-chunk process:**
1. Split transcript into ~800 token chunks
2. Summarize each chunk to 2-3 sentences
3. Combine chunk summaries
4. Generate final structured `EpisodeSummary`

### 2. Tag Generation

Extracts categorization and metadata:
- 5-10 relevant keyword tags
- Primary category (Technology, Business, etc.)
- Secondary categories (1-3)
- Difficulty level (beginner/intermediate/advanced)
- Technical terms and jargon

### 3. Entity Extraction

Identifies named entities:
- **People**: Individuals mentioned by name
- **Organizations**: Companies, institutions, groups
- **Products**: Products, services, technologies
- **Locations**: Places and geographic references
- **Resources**: Books, articles, studies cited

### 4. Highlights Generation

Finds key moments:
- 3-5 most impactful moments
- Best quote from the episode
- Entertaining/funny moments (optional)
- Controversial points (optional)
- Action items and practical advice

### 5. Question Answering

Interactive Q&A about episode content:
1. User enters question
2. Search each chunk for relevance
3. Combine relevant chunks
4. Generate structured answer with:
   - Direct answer
   - Approximate timestamp
   - Confidence level
   - Related topics

## Progress Tracking

The service provides real-time progress updates via callbacks:

```swift
func generateSummary(
    from transcriptText: String,
    episodeTitle: String,
    progressCallback: ((String, Double) -> Void)? = nil
) async throws -> EpisodeSummary {
    progressCallback?("Preparing transcript...", 0.1)
    // ... processing
    progressCallback?("Summarizing part 3 of 10...", 0.5)
    // ... more processing
    progressCallback?("Generating final summary...", 0.9)
}
```

The UI displays:
- Progress bar with percentage
- Current operation message
- Animated sparkle indicator

## Error Handling

### Availability Checking

```swift
func checkAvailability() -> FoundationModelsAvailability {
    switch systemModel.availability {
    case .available:
        return .available
    case .unavailable(.appleIntelligenceNotEnabled):
        return .unavailable(reason: "Enable Apple Intelligence in Settings")
    case .unavailable(.deviceNotEligible):
        return .unavailable(reason: "Requires iPhone 15 Pro+ or M1+ Mac/iPad")
    case .unavailable(.modelNotReady):
        return .unavailable(reason: "AI model is downloading...")
    }
}
```

### Safety Guardrails

Apple's models may refuse certain content. The service handles this gracefully:

```swift
do {
    let response = try await session.respond(to: prompt)
    chunkSummaries.append(response.content)
} catch {
    if error.localizedDescription.contains("unsafe") ||
       error.localizedDescription.contains("guardrail") {
        // Skip chunk, add placeholder
        skippedChunks += 1
        chunkSummaries.append("[Content could not be summarized]")
    } else {
        throw error
    }
}
```

## UI Integration

### EpisodeAIAnalysisView

The main analysis UI with:
- **Segmented tabs**: Summary, Tags, Entities, Highlights, Q&A
- **Availability banner**: Shows if AI is unavailable and why
- **Generate buttons**: Trigger analysis for each type
- **Result cards**: Formatted display of analysis results
- **Regenerate**: Clear and re-run analysis
- **Progress indicators**: Real-time feedback during processing

### Analysis State

Each analysis type has its own state:

```swift
enum AnalysisState: Equatable {
    case idle
    case analyzing(progress: Double, message: String)
    case completed
    case error(String)
}
```

## Files

| File | Purpose |
|------|---------|
| `Models/EpisodeAnalysisModels.swift` | @Generable model definitions |
| `Services/EpisodeAnalysisService.swift` | Core analysis logic, chunking, LLM calls |
| `Views/EpisodeAIAnalysisView.swift` | SwiftUI analysis UI |
| `ViewModels/EpisodeDetailViewModel.swift` | State management, UI coordination |
| `Utilities/SRTParser.swift` | Text chunking and token estimation |

## Usage Example

```swift
// Check availability
if #available(iOS 26.0, macOS 26.0, *) {
    let service = EpisodeAnalysisService()
    let availability = await service.checkAvailability()

    if availability.isAvailable {
        // Generate summary with progress
        let summary = try await service.generateSummary(
            from: transcriptText,
            episodeTitle: "Episode Title",
            language: "en",
            progressCallback: { message, progress in
                print("\(message) (\(Int(progress * 100))%)")
            }
        )

        print("Summary: \(summary.summary)")
        print("Topics: \(summary.mainTopics.joined(separator: ", "))")
    }
}
```

## Performance Considerations

1. **Token budget is tight**: The ~4096 token context requires aggressive chunking
2. **Chunk sampling**: Long episodes (20+ chunks) sample evenly for coverage
3. **Hierarchical processing**: Multi-stage summarization for quality results
4. **Conservative estimates**: Token estimation errs on the side of caution
5. **Async processing**: All operations use Swift concurrency for responsiveness
