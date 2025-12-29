# App Intents & Shortcuts Integration

## Overview

This guide explains how to use **App Intents** to run AI analysis **without app switching**, and how to integrate with Apple Intelligence (PCC) and ChatGPT via Shortcuts.

---

## 🎯 **The Problem**

When using Shortcuts to call Apple Intelligence or ChatGPT:

```
Your App → Shortcuts App (processing) → Back to Your App
         ❌ Visible app switch ❌
```

This creates a **jarring user experience** with visible app switching.

---

## ✅ **Solution: App Intents Framework**

**App Intents** (iOS 16+) allows Shortcuts to run **in your app's process** without opening the Shortcuts app!

### **Key Setting**

```swift
struct MyIntent: AppIntent {
    // ✅ This is the magic setting!
    static var openAppWhenRun: Bool = false

    // Your intent code runs IN YOUR APP
    // No app switching! 🎉
}
```

---

## 🚀 **Implementation**

### **Step 1: Add App Intents to Info.plist**

```xml
<key>NSSupportsAppIntents</key>
<true/>
```

### **Step 2: Create Your App Intent**

Already implemented in `AppIntents/EpisodeAnalysisIntents.swift`:

```swift
@available(iOS 16.0, *)
struct AnalyzeEpisodeIntent: AppIntent {
    static var title: LocalizedStringResource = "Analyze Episode"
    static var openAppWhenRun: Bool = false  // ✅ No app switching!

    @Parameter(title: "Transcript Text")
    var transcriptText: String

    @Parameter(title: "Analysis Type")
    var analysisType: AnalysisTypeEnum

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // This code runs in YOUR app!
        let service = EpisodeAnalysisService()
        let summary = try await service.generateSummary(...)
        return .result(value: summary.summary)
    }
}
```

### **Step 3: Use in Shortcuts**

1. Open **Shortcuts app**
2. Create new shortcut
3. Add action: Search for "Analyze Episode"
4. Your app intent appears!
5. Configure parameters
6. **Run shortcut** - No app switching! ✅

---

## 📱 **Usage Patterns**

### **Pattern 1: In-App Button → App Intent**

```swift
struct EpisodeDetailView: View {
    @State private var analysisResult: String = ""

    var body: some View {
        Button("Analyze with AI") {
            Task {
                await analyzeWithAppIntent()
            }
        }
    }

    func analyzeWithAppIntent() async {
        let intent = AnalyzeEpisodeIntent()
        intent.episodeTitle = episode.title
        intent.transcriptText = transcriptText
        intent.analysisType = .summary

        do {
            let result = try await intent.perform()
            analysisResult = result.value
        } catch {
            print("Error: \(error)")
        }
    }
}
```

### **Pattern 2: Siri Voice Command**

User says:
> "Hey Siri, analyze episode in PodcastAnalyzer"

Siri runs your App Intent **in background** without opening app!

### **Pattern 3: Shortcuts Automation**

Create automation:
```
When: Episode download completes
Do: Run "Analyze Episode" intent
```

Runs **automatically** in background! No app switching!

### **Pattern 4: Spotlight Search**

Your App Intents appear in **Spotlight**:
- User searches: "analyze episode"
- Your intent shows up
- Tap to run (no app switching)

---

## 🎨 **Comparison: App Intents vs Shortcuts**

| Feature | App Intents | Traditional Shortcuts |
|---------|-------------|----------------------|
| App Switching | ❌ None | ✅ Switches to Shortcuts app |
| Speed | ⚡ Fast (in-process) | 🐌 Slower (IPC) |
| Background Execution | ✅ Yes | ⚠️ Limited |
| Siri Integration | ✅ Built-in | ✅ Yes |
| Complexity | 🟢 Simple | 🟡 Moderate |
| iOS Requirement | iOS 16+ | iOS 13+ |

---

## 🔗 **When to Use Each Approach**

### **Use App Intents For:**

✅ **On-device AI** (Foundation Models)
- Summary generation
- Tag extraction
- Entity recognition
- Question answering
- **No app switching needed!**

### **Use Shortcuts For:**

✅ **External services** that require Shortcuts:
- ChatGPT integration
- Web search
- Multi-step workflows
- Third-party API calls

---

## 💡 **Hybrid Approach: Best of Both Worlds**

Use **App Intents for processing**, then pass to **Shortcuts for external services**:

### **Example: AI Summary + ChatGPT Enhancement**

**Shortcut workflow:**

```
1. Run App Intent: "Analyze Episode"
   ↓ (returns summary, no app switch)
2. Pass summary to ChatGPT via Shortcuts
   ↓ (switches to Shortcuts briefly)
3. Get enhanced result
   ↓
4. Return to your app
```

**Implementation:**

```swift
// Step 1: Your App Intent (no switching)
@available(iOS 16.0, *)
struct AnalyzeEpisodeIntent: AppIntent {
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Fast on-device analysis
        let service = EpisodeAnalysisService()
        let summary = try await service.generateSummary(...)

        // Return to Shortcuts for ChatGPT enhancement
        return .result(value: summary.summary)
    }
}
```

**In Shortcuts app:**

```
1. [Run App Intent] "Analyze Episode"
   → Get on-device summary (fast, no switch)

2. [Text] "Enhance this summary with examples: {result}"

3. [Ask ChatGPT] with enhanced prompt
   → Opens Shortcuts briefly for ChatGPT

4. [Quick Look] Show final result
```

---

## 🎯 **Recommended Implementation Strategy**

### **For 95% of Use Cases: Use Foundation Models (Already Implemented!)**

```swift
// Already in your EpisodeDetailViewModel
viewModel.generateAISummary()       // On-device, no switching
viewModel.generateAITags()          // On-device, no switching
viewModel.extractAIEntities()       // On-device, no switching
viewModel.askAIQuestion("...")      // On-device, no switching
```

**Benefits:**
- ✅ Zero app switching
- ✅ Faster (on-device)
- ✅ More private
- ✅ Works offline
- ✅ Free (no API costs)

### **For 5% of Use Cases: Use Shortcuts + ChatGPT**

When you **specifically need**:
- Web search integration
- Latest real-time information
- GPT-4 level reasoning
- Multi-step complex workflows

**Minimize app switching with x-callback-url:**

```swift
func runShortcutWithCallback() {
    let callbackURL = "podcastanalyzer://shortcut-complete"
    let shortcutName = "Enhance with ChatGPT"
    let input = summaryText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

    let urlString = """
    shortcuts://x-callback-url/run-shortcut?\
    name=\(shortcutName)&\
    input=text&\
    text=\(input)&\
    x-success=\(callbackURL)&\
    x-error=\(callbackURL)
    """

    if let url = URL(string: urlString) {
        UIApplication.shared.open(url)
    }
}

// Handle callback
func application(_ app: UIApplication, open url: URL) -> Bool {
    if url.scheme == "podcastanalyzer" {
        // Process result from Shortcuts
        handleShortcutResult(url)
    }
    return true
}
```

---

## 📊 **Performance Comparison**

### **Foundation Models (On-Device)**

```
Episode summary request
        ↓
In-app processing (2-5 seconds)
        ↓
Result displayed

Total: ~3-5 seconds
App switches: 0 ✅
```

### **App Intent (Background)**

```
Siri: "Analyze episode"
        ↓
App Intent runs (2-5 seconds, no UI)
        ↓
Siri speaks result

Total: ~3-5 seconds
App switches: 0 ✅
```

### **Traditional Shortcut (with switching)**

```
Tap shortcut
        ↓
Switch to Shortcuts app (1 second)
        ↓
Processing (2-5 seconds)
        ↓
Switch back to your app (1 second)

Total: ~4-7 seconds
App switches: 2 ❌
```

---

## 🔧 **Advanced: Hybrid AI Pipeline**

Combine **on-device Foundation Models** with **ChatGPT** for best results:

```swift
struct HybridAIAnalyzer {

    // Step 1: Fast on-device processing (Foundation Models)
    func generateInitialAnalysis(transcript: String) async throws -> EpisodeSummary {
        let service = EpisodeAnalysisService()
        return try await service.generateSummary(from: transcript, ...)
    }

    // Step 2: Optional ChatGPT enhancement (via Shortcuts)
    func enhanceWithChatGPT(summary: EpisodeSummary) async -> EnhancedSummary {
        // Only if user wants deeper analysis
        let prompt = """
        Enhance this podcast summary with examples and analogies:
        \(summary.summary)
        """

        return await runShortcutWithChatGPT(prompt: prompt)
    }

    // Usage
    func analyzeEpisode() async {
        // Step 1: Fast initial analysis (no app switch)
        let summary = try await generateInitialAnalysis(transcript: transcriptText)
        showResult(summary)  // User sees result immediately!

        // Step 2: Optional enhancement (user can skip)
        if userWantsEnhancement {
            let enhanced = await enhanceWithChatGPT(summary: summary)
            updateResult(enhanced)  // Shows enhanced version
        }
    }
}
```

---

## 🎨 **UI/UX Best Practices**

### **1. Show Immediate Feedback**

```swift
Button("Analyze") {
    showLoading = true  // ✅ Immediate feedback

    Task {
        let result = await analyzeWithAppIntent()
        showLoading = false
        displayResult(result)
    }
}
```

### **2. Provide Alternative Options**

```swift
Menu("Analyze") {
    Button("Quick Analysis (On-Device)") {
        // Foundation Models - Fast, no switching
        viewModel.generateAISummary()
    }

    Button("Enhanced Analysis (ChatGPT)") {
        // Shortcuts + ChatGPT - Slower, app switching
        runChatGPTShortcut()
    }
}
```

### **3. Explain App Switching**

```swift
if usesShortcuts {
    Text("Note: This will briefly open Shortcuts to access ChatGPT")
        .font(.caption)
        .foregroundColor(.secondary)
}
```

---

## 📝 **Complete Example: In-App + App Intent**

```swift
struct AIAnalysisView: View {
    @State private var analysisResult: String = ""
    @State private var isAnalyzing = false

    var body: some View {
        VStack {
            // Option 1: Direct in-app (Foundation Models)
            Button("Quick Analysis") {
                quickAnalysis()
            }
            .disabled(isAnalyzing)

            // Option 2: App Intent (background, no switch)
            Button("Siri-Compatible Analysis") {
                appIntentAnalysis()
            }
            .disabled(isAnalyzing)

            // Option 3: Shortcuts + ChatGPT (with switch)
            Button("ChatGPT Enhanced") {
                chatGPTAnalysis()
            }
            .disabled(isAnalyzing)

            if isAnalyzing {
                ProgressView()
            }

            Text(analysisResult)
        }
    }

    // Option 1: Direct Foundation Models
    func quickAnalysis() {
        isAnalyzing = true
        Task {
            let service = EpisodeAnalysisService()
            let summary = try await service.generateSummary(...)
            analysisResult = summary.summary
            isAnalyzing = false
        }
    }

    // Option 2: App Intent
    func appIntentAnalysis() {
        isAnalyzing = true
        Task {
            let intent = AnalyzeEpisodeIntent()
            intent.transcriptText = transcriptText
            let result = try await intent.perform()
            analysisResult = result.value
            isAnalyzing = false
        }
    }

    // Option 3: Shortcuts with callback
    func chatGPTAnalysis() {
        isAnalyzing = true

        // Show overlay to hide app switch
        showFullScreenOverlay(message: "Analyzing with ChatGPT...")

        // Run shortcut with callback
        let url = URL(string: "shortcuts://run-shortcut?name=ChatGPT%20Analysis")!
        UIApplication.shared.open(url)

        // Handle result via callback (see AppDelegate)
    }
}
```

---

## 🎯 **Recommendation**

### **Primary Approach: Foundation Models (Already Implemented)**

```swift
// ✅ Use this for 95% of use cases
viewModel.generateAISummary()
viewModel.generateAITags()
viewModel.extractAIEntities()
viewModel.askAIQuestion("...")
```

**Advantages:**
- Zero app switching
- Faster
- More private
- Works offline
- Free

### **Secondary Approach: App Intents**

```swift
// ✅ Use for Siri/Spotlight/Automation
let intent = AnalyzeEpisodeIntent()
try await intent.perform()
```

**Advantages:**
- No app switching
- Siri integration
- Spotlight search
- Background execution

### **Tertiary Approach: Shortcuts + ChatGPT**

```swift
// ⚠️ Use ONLY when you need:
// - ChatGPT specifically
// - Web search
// - Multi-step workflows
runShortcutWithCallback()
```

**Trade-offs:**
- App switching (unavoidable)
- Slower
- Requires internet
- May have API costs

---

## 🚀 **Quick Start**

1. **For immediate use:** Use Foundation Models (already implemented)
   ```swift
   viewModel.generateAISummary()
   ```

2. **For Siri/automation:** Use App Intents (just added)
   ```swift
   let intent = AnalyzeEpisodeIntent()
   try await intent.perform()
   ```

3. **For ChatGPT:** Use Shortcuts with x-callback-url
   ```swift
   runShortcutWithCallback()
   ```

---

## 📚 **Resources**

- [App Intents Documentation](https://developer.apple.com/documentation/appintents)
- [Foundation Models Guide](./APPLE_INTELLIGENCE_INTEGRATION.md)
- [Shortcuts URL Scheme](https://support.apple.com/guide/shortcuts/run-shortcuts-from-a-url-apd624386f42/ios)

---

## 💡 **Summary**

**Best Solution:** Use the **Foundation Models** you already have! They provide:
- ✅ No app switching
- ✅ Fast on-device processing
- ✅ Complete privacy
- ✅ Offline support
- ✅ Free operation

**Use Shortcuts ONLY when you specifically need ChatGPT or external services.**

Your app already has the best solution implemented! 🎉
