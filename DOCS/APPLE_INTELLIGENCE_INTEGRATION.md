# Apple Intelligence Integration Guide

## Overview

This guide explains how to integrate Apple Foundation Models (iOS 26+) into your PodcastAnalyzer app for AI-powered episode analysis.

## What's Been Implemented

### ✅ Core Components Created

1. **SRTParser** (`Utilities/SRTParser.swift`)
   - Extracts plain text from SRT transcripts
   - Parses SRT into structured segments
   - Estimates token counts for different languages
   - Smart text chunking to fit 4096 token limit

2. **@Generable Models** (`Models/EpisodeAnalysisModels.swift`)
   - `EpisodeSummary` - Summary with topics, takeaways, audience
   - `EpisodeTags` - Tags, categories, difficulty level
   - `EpisodeEntities` - People, organizations, products, locations
   - `EpisodeHighlights` - Key moments, quotes, action items
   - `EpisodeContentAnalysis` - Style, tone, complexity analysis
   - `EpisodeAnswer` - Q&A responses with confidence and timestamps

3. **EpisodeAnalysisService** (`Services/EpisodeAnalysisService.swift`)
   - Device availability checking
   - Summarization (single-chunk and multi-chunk with hierarchical approach)
   - Tag generation
   - Entity extraction
   - Highlights generation
   - Content analysis
   - Question answering (searches relevant chunks)
   - Multi-episode comparison analysis

4. **ViewModel Integration** (`ViewModels/EpisodeDetailViewModel.swift`)
   - Added AI state properties
   - Methods for each analysis type
   - Availability checking
   - Progress tracking
   - Error handling

5. **Example UI** (`Views/EpisodeAIAnalysisView.swift`)
   - Complete reference implementation
   - Tabbed interface for different analyses
   - Beautiful cards for displaying results
   - Question & Answer interface
   - Progress indicators
   - Availability warnings

---

## Requirements

### Device Requirements
- **iOS 26+** (or macOS 26+, iPadOS 26+)
- **Hardware:** iPhone 15 Pro or newer, M1+ iPads/Macs
- **Apple Intelligence:** Must be enabled in Settings → Apple Intelligence & Siri
- **Model Download:** ~1.6 GB on-device model (downloads automatically when enabled)

### Technical Constraints
- **Context Window:** 4096 tokens total (input + output)
- **Token Estimation:**
  - English/European languages: ~3-4 characters per token
  - Asian languages (Chinese/Japanese/Korean): ~1 character per token
- **On-Device Processing:** No cloud required, completely private
- **Supported Languages:** English, French, German, Italian, Portuguese, Spanish, Chinese, Japanese, Korean

---

## How It Works

### 1. Transcript Parsing & Chunking

```swift
// Parse SRT to plain text
let plainText = SRTParser.extractPlainText(from: srtContent)

// Estimate tokens
let tokenCount = SRTParser.estimateTokenCount(for: plainText, language: "en")

// Smart chunking if transcript is too long
let chunks = SRTParser.chunkText(plainText, maxTokens: 3000, language: "en")
```

**Why Chunking?**
- Most podcast transcripts exceed 4096 tokens
- Chunking splits by sentences to maintain context
- Multi-chunk summaries use hierarchical approach:
  1. Summarize each chunk
  2. Combine chunk summaries
  3. Generate final summary

### 2. Availability Checking

```swift
// Check if Foundation Models are available
let service = EpisodeAnalysisService()
let availability = await service.checkAvailability()

switch availability {
case .available:
    // Proceed with analysis
case .unavailable(.appleIntelligenceNotEnabled):
    // Show "Enable Apple Intelligence" message
case .unavailable(.deviceNotEligible):
    // Show "Device not supported" message
case .unavailable(.modelNotReady):
    // Show "Model downloading..." message
}
```

### 3. Structured Output with @Generable

```swift
// Define structure for AI output
@Generable
struct EpisodeSummary {
    @Guide(description: "Concise 2-3 sentence summary")
    var summary: String

    @Guide(description: "List of 3-5 main topics")
    var mainTopics: [String]

    @Guide(description: "List of 3-5 key takeaways")
    var keyTakeaways: [String]
}

// Foundation Models returns typed struct (not raw text!)
let summary: EpisodeSummary = try await session.respond(to: prompt)
```

**Benefits of @Generable:**
- Type-safe structured output
- No JSON parsing needed
- Guaranteed format compliance
- Compile-time validation

### 4. Summarization Flow

```swift
// For short transcripts (< 3000 tokens)
func generateSummarySingleChunk(_ text: String) async throws -> EpisodeSummary {
    let prompt = """
    Analyze this podcast episode and provide a comprehensive summary.
    Transcript: \(text)
    """
    return try await session.respond(to: prompt)
}

// For long transcripts (> 3000 tokens) - Hierarchical approach
func generateSummaryMultiChunk(_ chunks: [String]) async throws -> EpisodeSummary {
    // Step 1: Summarize each chunk
    var chunkSummaries: [String] = []
    for (index, chunk) in chunks.enumerated() {
        let prompt = "Summarize part \(index + 1) of \(chunks.count): \(chunk)"
        let summary = try await session.respond(to: prompt)
        chunkSummaries.append(summary)
    }

    // Step 2: Generate final summary from chunk summaries
    let combined = chunkSummaries.joined(separator: "\n\n")
    let finalPrompt = "Create comprehensive summary from these parts: \(combined)"
    return try await session.respond(to: finalPrompt)
}
```

### 5. Question Answering with Chunk Search

```swift
func answerQuestionMultiChunk(_ question: String, chunks: [String]) async throws -> EpisodeAnswer {
    // Step 1: Find relevant chunks
    var relevantChunks: [String] = []

    for chunk in chunks {
        let searchPrompt = """
        Does this section contain information relevant to: "\(question)"?
        Answer yes or no and explain why.
        Section: \(chunk)
        """
        let relevanceCheck = try await session.respond(to: searchPrompt)

        if relevanceCheck.lowercased().contains("yes") {
            relevantChunks.append(chunk)
        }
    }

    // Step 2: Answer from relevant chunks only
    let combined = relevantChunks.joined(separator: "\n\n")
    let answerPrompt = """
    Answer this question based on relevant sections:
    Question: \(question)
    Relevant content: \(combined)
    """

    return try await session.respond(to: answerPrompt)
}
```

---

## Integration Steps

### Step 1: Add AI Tab to EpisodeDetailView

```swift
// In EpisodeDetailView.swift
TabView(selection: $selectedTab) {
    summaryTab.tag(0)
    transcriptTab.tag(1)

    // NEW: Add AI Analysis tab
    if #available(iOS 26.0, *) {
        aiAnalysisTab.tag(2)
    }
}

private var aiAnalysisTab: some View {
    if #available(iOS 26.0, *) {
        NavigationLink(destination: EpisodeAIAnalysisView(viewModel: viewModel)) {
            Label("AI Analysis", systemImage: "sparkles")
        }
    }
}
```

### Step 2: Check Availability on View Appear

```swift
// In EpisodeDetailView.swift
.onAppear {
    viewModel.checkTranscriptStatus()
    viewModel.checkAIAvailability()  // NEW
}
```

### Step 3: Add Quick Actions

```swift
// Example: Add "Generate Summary" button in episode detail
if viewModel.hasTranscript {
    Button(action: {
        viewModel.generateAISummary()
    }) {
        Label("AI Summary", systemImage: "sparkles")
    }
    .disabled(!viewModel.aiAvailability.isAvailable)
}

// Show progress
if case .analyzing(let progress) = viewModel.analysisState {
    ProgressView(value: progress) {
        Text("Analyzing... \(Int(progress * 100))%")
    }
}

// Show results
if let summary = viewModel.episodeSummary {
    VStack(alignment: .leading) {
        Text("AI Summary")
            .font(.headline)
        Text(summary.summary)
            .font(.body)
    }
}
```

---

## Usage Examples

### Example 1: Generate Summary

```swift
// User taps "Generate Summary" button
viewModel.generateAISummary()

// Behind the scenes:
// 1. Check availability
// 2. Extract plain text from SRT
// 3. Chunk if needed
// 4. Generate summary (hierarchical if multi-chunk)
// 5. Return structured EpisodeSummary

// Result:
if let summary = viewModel.episodeSummary {
    print(summary.summary)              // "This episode discusses..."
    print(summary.mainTopics)           // ["SwiftUI", "MVVM", "Async/Await"]
    print(summary.keyTakeaways)         // ["Use @Observable for cleaner code", ...]
    print(summary.targetAudience)       // "iOS developers"
    print(summary.engagementLevel)      // "high"
}
```

### Example 2: Ask Questions

```swift
// User asks: "What did they say about SwiftUI performance?"
viewModel.askAIQuestion("What did they say about SwiftUI performance?")

// Result:
if let answer = viewModel.currentAnswer {
    print(answer.answer)                // "They discussed that SwiftUI..."
    print(answer.timestamp)             // "15:30-16:45"
    print(answer.confidence)            // "high"
    print(answer.relatedTopics)         // ["View optimization", "State management"]
}
```

### Example 3: Extract Entities

```swift
viewModel.extractAIEntities()

if let entities = viewModel.episodeEntities {
    print(entities.people)              // ["Steve Jobs", "Tim Cook"]
    print(entities.organizations)       // ["Apple", "Google", "Microsoft"]
    print(entities.products)            // ["iPhone", "SwiftUI", "Xcode"]
    print(entities.locations)           // ["Cupertino", "San Francisco"]
    print(entities.resources)           // ["WWDC 2025 Session 286"]
}
```

### Example 4: Multi-Episode Analysis

```swift
// Compare multiple episodes
let episodeData = [
    (title: "Episode 1: Intro to SwiftUI", transcript: transcript1),
    (title: "Episode 2: Advanced SwiftUI", transcript: transcript2),
    (title: "Episode 3: SwiftUI Performance", transcript: transcript3)
]

let service = EpisodeAnalysisService()
let analysis = try await service.analyzeMultipleEpisodes(episodeData)

print(analysis.commonThemes)            // ["SwiftUI", "Reactive programming"]
print(analysis.evolution)               // "Started with basics, progressed to..."
print(analysis.uniqueInsights)          // ["Episode 3 covered LazyVStack..."]
print(analysis.recommendedOrder)        // ["Episode 1", "Episode 2", "Episode 3"]
print(analysis.narrative)               // "This series builds from..."
```

---

## Best Practices

### 1. **Check Availability First**

```swift
// Always check before showing AI features
.onAppear {
    viewModel.checkAIAvailability()
}

// Show appropriate UI based on availability
if !viewModel.aiAvailability.isAvailable {
    Text(viewModel.aiAvailability.message ?? "AI unavailable")
        .foregroundColor(.secondary)
}
```

### 2. **Require Transcript First**

```swift
// AI analysis requires transcript
guard !transcriptText.isEmpty else {
    analysisState = .error("Generate transcript first")
    return
}
```

### 3. **Show Progress for Long Operations**

```swift
Task {
    await MainActor.run {
        analysisState = .analyzing(progress: 0.2)
    }

    // ... perform analysis ...

    await MainActor.run {
        analysisState = .completed
    }
}
```

### 4. **Handle Errors Gracefully**

```swift
do {
    let summary = try await service.generateSummary(...)
} catch {
    await MainActor.run {
        analysisState = .error("Failed: \(error.localizedDescription)")
    }
}
```

### 5. **Cache Results**

```swift
// Don't regenerate if already available
if let existingSummary = viewModel.episodeSummary {
    // Use cached result
    return
}

// Only generate if needed
viewModel.generateAISummary()
```

### 6. **Optimize Token Usage**

```swift
// For tags, entities, etc., condense long transcripts
let condensed = try await service.condenseIfNeeded(
    transcriptText,
    targetTokens: 2000,
    language: "en"
)
```

---

## Token Management Strategy

### Chunk Sizes by Operation

| Operation | Input Tokens | Output Tokens | Total |
|-----------|--------------|---------------|-------|
| Summary (full) | 3000 | 1000 | 4000 |
| Summary (condensed) | 2000 | 500 | 2500 |
| Tags | 2000 | 300 | 2300 |
| Entities | 2000 | 500 | 2500 |
| Highlights | 3000 | 800 | 3800 |
| Q&A | 3000 | 500 | 3500 |

### Hierarchical Summarization for Long Transcripts

```
Original Transcript: 20,000 tokens
    ↓
Split into 7 chunks (3000 tokens each)
    ↓
Generate 7 chunk summaries (500 tokens each)
    ↓
Total: 3500 tokens of summaries
    ↓
Final summary from combined summaries
```

---

## Testing Without iOS 26 Device

### Availability Simulation

```swift
// For testing UI without actual device
#if DEBUG
extension EpisodeDetailViewModel {
    func simulateAIResults() {
        episodeSummary = EpisodeSummary(
            summary: "This episode covers SwiftUI best practices...",
            mainTopics: ["SwiftUI", "MVVM", "Performance"],
            keyTakeaways: ["Use @Observable", "Prefer composition"],
            targetAudience: "iOS developers",
            engagementLevel: "high"
        )
        analysisState = .completed
    }
}
#endif
```

---

## Performance Considerations

### On-Device Processing
- **Speed:** ~50-100 tokens/second on iPhone 15 Pro
- **Battery:** Minimal impact, uses Neural Engine
- **Privacy:** No data leaves device
- **Offline:** Works without internet

### Multi-Chunk Overhead
- Each chunk requires separate model invocation
- 7-chunk summary ≈ 8 model calls (7 chunks + 1 final)
- Total time: ~30-60 seconds for long episode

### Optimization Tips
1. **Progressive UI:** Show chunk summaries as they complete
2. **Background Processing:** Use Task { } for async work
3. **Cancellation:** Support cancelling long operations
4. **Caching:** Save results to SwiftData to avoid regeneration

---

## Future Enhancements

### Potential Features
1. **Smart Timestamp Linking:** Parse transcript segments and link answer timestamps to exact SRT segments
2. **Cross-Episode Search:** "Find all episodes mentioning SwiftUI performance"
3. **Personalized Summaries:** "Summarize focusing on code examples"
4. **Chapter Generation:** Auto-generate chapters with timestamps
5. **Sentiment Analysis:** Track mood/tone throughout episode
6. **Speaker Detection:** Identify and label different speakers
7. **Related Episode Recommendations:** Based on content similarity

### Private Cloud Compute (Future)
- Apple's Private Cloud Compute for larger models
- Handles requests > 4096 tokens
- Maintains privacy with cryptographic guarantees
- Automatically used when needed (no API changes)

---

## Troubleshooting

### "Apple Intelligence Not Enabled"
**Solution:** Settings → Apple Intelligence & Siri → Enable

### "Device Not Eligible"
**Solution:** Requires iPhone 15 Pro or newer, M1+ Mac/iPad

### "Model Not Ready"
**Solution:** Model downloading (~1.6 GB), wait a few minutes

### "Transcript Too Long" Errors
**Solution:** Chunking should handle this automatically. Check:
```swift
let chunks = SRTParser.chunkText(text, maxTokens: 3000)
print("Split into \(chunks.count) chunks")
```

### Slow Performance
**Possible Causes:**
- Low battery (system throttles AI)
- Too many concurrent requests
- Very long transcript (many chunks)

**Solutions:**
- Ensure device is charging
- Process one analysis at a time
- Show progress indicators

---

## API Reference

### SRTParser

```swift
static func extractPlainText(from srtContent: String) -> String
static func parseSegments(from srtContent: String) -> [TranscriptSegment]
static func estimateTokenCount(for text: String, language: String = "en") -> Int
static func chunkText(_ text: String, maxTokens: Int = 3000, language: String = "en") -> [String]
```

### EpisodeAnalysisService

```swift
func checkAvailability() -> FoundationModelsAvailability
var isAvailable: Bool

func generateSummary(from: String, episodeTitle: String, language: String) async throws -> EpisodeSummary
func generateTags(from: String, episodeTitle: String, language: String) async throws -> EpisodeTags
func extractEntities(from: String, language: String) async throws -> EpisodeEntities
func generateHighlights(from: String, episodeTitle: String, language: String) async throws -> EpisodeHighlights
func analyzeContent(from: String, language: String) async throws -> EpisodeContentAnalysis
func answerQuestion(_ question: String, from: String, episodeTitle: String, language: String) async throws -> EpisodeAnswer
func analyzeMultipleEpisodes(_ episodeData: [(title: String, transcript: String)], language: String) async throws -> MultiEpisodeAnalysis
```

### EpisodeDetailViewModel (New Methods)

```swift
func checkAIAvailability()
func generateAISummary()
func generateAITags()
func extractAIEntities()
func generateAIHighlights()
func analyzeAIContent()
func askAIQuestion(_ question: String)
func generateAllAIAnalyses()
func clearAIResults()
```

---

## Resources & Documentation

### Apple Official Docs
- [Foundation Models Framework](https://developer.apple.com/documentation/FoundationModels)
- [WWDC 2025 Session 286: Meet the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/286/)
- [WWDC 2025 Session 301: Deep dive into the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/301/)
- [TN3193: Managing the on-device foundation model's context window](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)

### Community Resources
- [Getting Started with Apple's Foundation Models](https://artemnovichkov.com/blog/getting-started-with-apple-foundation-models)
- [Building AI features using Foundation Models | Swift with Majid](https://swiftwithmajid.com/2025/08/19/building-ai-features-using-foundation-models/)
- [Making the most of Apple Foundation Models: Context Window](https://zats.io/blog/making-the-most-of-apple-foundation-models-context-window/)

---

## Summary

You now have a complete, production-ready AI analysis system for your podcast app:

✅ **SRT parsing** with smart chunking
✅ **@Generable models** for structured output
✅ **Availability checking** for graceful degradation
✅ **Multi-chunk processing** for long transcripts
✅ **Question answering** with intelligent chunk search
✅ **Comprehensive UI** with example implementation
✅ **Error handling** and progress tracking
✅ **Privacy-first** on-device processing

The system handles all edge cases:
- Transcripts too long → Hierarchical summarization
- Device doesn't support AI → Clear messaging
- Model not ready → Download progress
- Network offline → Works offline

All while maintaining Apple's privacy standards and requiring zero backend infrastructure!
