# AI Analysis Architecture

This document describes how PodcastAnalyzer uses AI for podcast episode analysis with a hybrid approach: on-device for quick metadata tags, cloud APIs for full transcript analysis.

## Overview

PodcastAnalyzer uses a **two-tier AI architecture**:

1. **On-Device AI (Apple Foundation Models)**: For quick, lightweight tasks on episode metadata (title, description, duration)
2. **Cloud AI (BYOK - Bring Your Own Key)**: For full transcript analysis using user-provided API keys

This approach provides the best user experience:
- **On-device**: Fast, private, no API costs, works offline (but limited context)
- **Cloud**: Powerful analysis with large context windows (128K-1M tokens), user controls costs

## Why Not On-Device for Transcripts?

Apple's Foundation Models have a ~4096 token context window. After accounting for system prompts, schema, and output reservation, only ~600-800 tokens remain for input - equivalent to ~2-3 minutes of podcast content. This is inadequate for meaningful transcript analysis.

**Solution**: Use on-device AI for what it does well (quick metadata categorization) and cloud APIs for heavy lifting (transcript analysis).

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                       EpisodeDetailView                         │
│  - Keywords Tab → On-device quick tags                         │
│  - AI Button → Cloud transcript analysis                       │
└───────────────────────────┬─────────────────────────────────────┘
                            │
          ┌─────────────────┼─────────────────┐
          │                 │                 │
          ▼                 ▼                 ▼
┌─────────────────┐ ┌───────────────┐ ┌─────────────────┐
│ Keywords Tab    │ │ AI Analysis   │ │ Settings        │
│                 │ │ View          │ │ (AISettingsView)│
└────────┬────────┘ └───────┬───────┘ └────────┬────────┘
         │                  │                  │
         ▼                  ▼                  ▼
┌─────────────────┐ ┌───────────────┐ ┌─────────────────┐
│ On-Device       │ │ CloudAI       │ │ AISettings      │
│ AnalysisService │ │ Service       │ │ Manager         │
│ (Foundation     │ │ (OpenAI,      │ │ (API Keys,      │
│  Models)        │ │  Claude,      │ │  Model Prefs)   │
│                 │ │  Gemini,      │ │                 │
│                 │ │  Grok)        │ │                 │
└─────────────────┘ └───────────────┘ └─────────────────┘
```

## On-Device AI (Quick Tags)

### Use Case
Generate quick tags and categorization from episode **metadata only**:
- Episode title
- Episode description (~500 chars max)
- Duration
- Release date

### Requirements
- iOS 26.0+ / macOS 26.0+
- Apple Intelligence enabled
- Compatible hardware (iPhone 15 Pro+, M1+ Mac/iPad)

### Model: EpisodeQuickTags

```swift
@Generable
struct EpisodeQuickTags {
    @Guide(description: "List of 5-8 relevant keywords")
    var tags: [String]

    @Guide(description: "Primary category: Technology, Business, etc.")
    var primaryCategory: String

    var secondaryCategory: String?
    var contentType: String  // interview, solo, panel, etc.
    var difficulty: String   // beginner, intermediate, advanced
}
```

### Token Budget
- Total context: ~4096 tokens
- System prompt: ~200 tokens
- Schema: ~100 tokens
- Input (metadata): ~500 tokens (truncated description)
- Output reservation: ~200 tokens
- **Fits comfortably within limits**

## Cloud AI (Transcript Analysis)

### Use Case
Full transcript analysis with large language models:
- Comprehensive summaries
- Entity extraction (people, organizations, products)
- Highlights and key moments
- Question answering about content

### Supported Providers (BYOK)

| Provider | Models | Context Window | Free Tier |
|----------|--------|----------------|-----------|
| **Gemini** | Flash, Pro, 2.0 | 1M tokens | Yes |
| **OpenAI** | GPT-4o-mini, GPT-4o | 128K tokens | Credits |
| **Claude** | Haiku, Sonnet, Opus | 200K tokens | No |
| **Grok** | grok-beta, grok-2 | 128K tokens | No |

### How It Works

1. User configures API key in Settings > AI Settings
2. User navigates to AI Analysis view (requires transcript)
3. User selects analysis type (Summary, Entities, Highlights, Full Analysis, Q&A)
4. CloudAIService sends transcript to selected provider
5. Results displayed with provider/model metadata

### API Key Storage
- Stored securely in iOS Keychain
- Never sent to our servers
- User has full control

## Files

| File | Purpose |
|------|---------|
| `Services/EpisodeAnalysisService.swift` | On-device quick tags generation |
| `Services/CloudAIService.swift` | Cloud API calls (OpenAI, Claude, Gemini, Grok) |
| `Models/AISettingsModel.swift` | Provider enum, settings manager, Keychain storage |
| `Models/EpisodeAnalysisModels.swift` | @Generable models, analysis states, cache types |
| `Views/AISettingsView.swift` | Settings UI for API keys and model selection |
| `Views/EpisodeAIAnalysisView.swift` | Cloud analysis UI with tabs |
| `Views/EpisodeDetailView.swift` | Keywords tab with on-device tags |
| `ViewModels/EpisodeDetailViewModel.swift` | AI state management, analysis methods |

## Usage Examples

### On-Device Quick Tags (Keywords Tab)

```swift
// Check availability
func checkOnDeviceAIAvailability() {
    if #available(iOS 26.0, macOS 26.0, *) {
        let service = EpisodeAnalysisService()
        let availability = await service.checkAvailability()
        // .available or .unavailable(reason:)
    }
}

// Generate tags from metadata
func generateQuickTags() {
    let service = EpisodeAnalysisService()
    let tags = try await service.generateQuickTags(
        title: episode.title,
        description: episode.description,
        podcastTitle: podcastTitle,
        duration: episode.duration,
        releaseDate: episode.pubDate
    )
    // tags.primaryCategory, tags.tags, tags.contentType, etc.
}
```

### Cloud Transcript Analysis

```swift
// Check if provider configured
let settings = AISettingsManager.shared
guard settings.hasConfiguredProvider else { return }

// Analyze transcript
let service = CloudAIService.shared
let result = try await service.analyzeTranscript(
    transcript,
    episodeTitle: "Episode Title",
    podcastTitle: "Podcast Name",
    analysisType: .summary,
    progressCallback: { message, progress in
        print("\(message) (\(Int(progress * 100))%)")
    }
)

// result.content (the analysis text)
// result.provider (which provider was used)
// result.model (which model was used)
// result.timestamp (when generated)
```

### Ask Questions

```swift
let answer = try await service.askQuestion(
    "What were the main topics discussed?",
    transcript: transcript,
    episodeTitle: "Episode Title"
)
```

## Cost Considerations

**On-Device**: Free, unlimited, private

**Cloud (BYOK)**:
- **Gemini**: Has generous free tier (Flash model)
- **OpenAI**: gpt-4o-mini is very affordable (~$0.15/1M input tokens)
- **Claude**: No free tier, but Haiku is affordable
- **Grok**: More expensive, but powerful

Users control their own costs by:
1. Choosing which provider/model to use
2. Deciding when to run analysis
3. Using their own API keys

## Privacy

- **On-Device**: All processing happens locally, completely private
- **Cloud**: Transcripts sent to user's chosen provider
  - Users explicitly configure which provider to use
  - No data sent to our servers
  - Provider's privacy policy applies
