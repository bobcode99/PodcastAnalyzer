//
//  CloudAIService.swift
//  PodcastAnalyzer
//
//  Service for cloud-based AI analysis using user-provided API keys (BYOK)
//  Supports OpenAI, Claude, Gemini, Grok, and Apple Intelligence via Shortcuts
//

import Foundation
import os.log
import UIKit

// MARK: - Cloud AI Service

@MainActor
final class CloudAIService {
    static let shared = CloudAIService()

    private let settings = AISettingsManager.shared
    private let logger = Logger(subsystem: "com.podcastanalyzer", category: "CloudAIService")

    // MARK: - API Endpoints

    private func apiEndpoint(for provider: CloudAIProvider) -> URL {
        switch provider {
        case .applePCC:
            // Apple PCC uses Shortcuts, no API endpoint needed
            return URL(string: "shortcuts://")!
        case .openai:
            return URL(string: "https://api.openai.com/v1/chat/completions")!
        case .claude:
            return URL(string: "https://api.anthropic.com/v1/messages")!
        case .gemini:
            return URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!
        case .groq:
            return URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        case .grok:
            return URL(string: "https://api.x.ai/v1/chat/completions")!
        }
    }

    // MARK: - Fetch Available Models

    /// Fetch available models from the provider's API
    func fetchAvailableModels(for provider: CloudAIProvider, apiKey: String) async throws -> [String] {
        switch provider {
        case .applePCC:
            // Apple PCC uses Shortcuts with Apple Intelligence - no model selection needed
            return ["Apple Intelligence"]
        case .openai:
            return try await fetchOpenAIModels(apiKey: apiKey)
        case .claude:
            return try await fetchClaudeModels(apiKey: apiKey)
        case .gemini:
            return try await fetchGeminiModels(apiKey: apiKey)
        case .groq:
            return try await fetchGroqModels(apiKey: apiKey)
        case .grok:
            return try await fetchGrokModels(apiKey: apiKey)
        }
    }

    private func fetchOpenAIModels(apiKey: String) async throws -> [String] {
        let endpoint = URL(string: "https://api.openai.com/v1/models")!

        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CloudAIError.invalidResponse
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let models = json?["data"] as? [[String: Any]] else {
            throw CloudAIError.invalidResponse
        }

        // Filter for chat models only (gpt-4, gpt-3.5, etc.)
        let chatModels = models.compactMap { $0["id"] as? String }
            .filter { id in
                id.contains("gpt-4") || id.contains("gpt-3.5")
            }
            .filter { id in
                // Exclude deprecated/instruct models
                !id.contains("instruct") && !id.contains("vision") && !id.contains("realtime")
            }
            .sorted { a, b in
                // Sort newer models first
                if a.contains("4.1") && !b.contains("4.1") { return true }
                if !a.contains("4.1") && b.contains("4.1") { return false }
                if a.contains("4o") && !b.contains("4o") { return true }
                if !a.contains("4o") && b.contains("4o") { return false }
                return a < b
            }

        return chatModels.isEmpty ? CloudAIProvider.openai.availableModels : Array(chatModels.prefix(8))
    }

    private func fetchClaudeModels(apiKey: String) async throws -> [String] {
        let endpoint = URL(string: "https://api.anthropic.com/v1/models")!

        var request = URLRequest(url: endpoint)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            // Fallback to hardcoded if API doesn't support listing
            return CloudAIProvider.claude.availableModels
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let models = json?["data"] as? [[String: Any]] else {
            return CloudAIProvider.claude.availableModels
        }

        let modelIds = models.compactMap { $0["id"] as? String }
            .filter { id in
                // Only include claude-3 and claude-4 models
                (id.contains("claude-3") || id.contains("claude-4") || id.contains("claude-sonnet") || id.contains("claude-opus") || id.contains("claude-haiku"))
            }
            .sorted { a, b in
                // Sort by version (4 > 3), then by capability (opus > sonnet > haiku)
                if a.contains("4") && !b.contains("4") { return true }
                if !a.contains("4") && b.contains("4") { return false }
                if a.contains("opus") && !b.contains("opus") { return true }
                if !a.contains("opus") && b.contains("opus") { return false }
                if a.contains("sonnet") && !b.contains("sonnet") { return true }
                return a > b
            }

        return modelIds.isEmpty ? CloudAIProvider.claude.availableModels : Array(modelIds.prefix(8))
    }

    private func fetchGeminiModels(apiKey: String) async throws -> [String] {
        let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)")!

        let request = URLRequest(url: endpoint)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CloudAIError.invalidResponse
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let models = json?["models"] as? [[String: Any]] else {
            throw CloudAIError.invalidResponse
        }

        let geminiModels = models.compactMap { model -> String? in
            guard let name = model["name"] as? String,
                  let supportedMethods = model["supportedGenerationMethods"] as? [String],
                  supportedMethods.contains("generateContent") else {
                return nil
            }
            // Extract model ID from "models/gemini-2.0-flash"
            return name.replacingOccurrences(of: "models/", with: "")
        }
        .filter { id in
            // Only include gemini models (not embedding models)
            id.contains("gemini") && !id.contains("embedding") && !id.contains("aqa")
        }
        .sorted { a, b in
            // Sort newer versions first (2.5 > 2.0 > 1.5)
            if a.contains("2.5") && !b.contains("2.5") { return true }
            if !a.contains("2.5") && b.contains("2.5") { return false }
            if a.contains("2.0") && !b.contains("2.0") { return true }
            if !a.contains("2.0") && b.contains("2.0") { return false }
            // Pro > Flash > Flash-Lite
            if a.contains("pro") && !b.contains("pro") { return true }
            if !a.contains("pro") && b.contains("pro") { return false }
            return a < b
        }

        return geminiModels.isEmpty ? CloudAIProvider.gemini.availableModels : Array(geminiModels.prefix(10))
    }

    private func fetchGroqModels(apiKey: String) async throws -> [String] {
        let endpoint = URL(string: "https://api.groq.com/openai/v1/models")!

        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            // Fallback to hardcoded if API doesn't work
            return CloudAIProvider.groq.availableModels
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let models = json?["data"] as? [[String: Any]] else {
            return CloudAIProvider.groq.availableModels
        }

        let groqModels = models.compactMap { $0["id"] as? String }
            .filter { id in
                // Filter for chat models (llama, mixtral, gemma)
                (id.contains("llama") || id.contains("mixtral") || id.contains("gemma"))
                && !id.contains("guard") // Exclude guard models
            }
            .sorted { a, b in
                // Sort by model size/quality
                if a.contains("70b") && !b.contains("70b") { return true }
                if !a.contains("70b") && b.contains("70b") { return false }
                if a.contains("90b") && !b.contains("90b") { return true }
                if !a.contains("90b") && b.contains("90b") { return false }
                return a > b
            }

        return groqModels.isEmpty ? CloudAIProvider.groq.availableModels : Array(groqModels.prefix(10))
    }

    private func fetchGrokModels(apiKey: String) async throws -> [String] {
        let endpoint = URL(string: "https://api.x.ai/v1/models")!

        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            // Fallback to hardcoded if API doesn't work
            return CloudAIProvider.grok.availableModels
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let models = json?["data"] as? [[String: Any]] else {
            return CloudAIProvider.grok.availableModels
        }

        let grokModels = models.compactMap { $0["id"] as? String }
            .filter { id in
                id.contains("grok") && !id.contains("vision") && !id.contains("image")
            }
            .sorted { a, b in
                // Sort newer versions first (4 > 3 > 2)
                if a.contains("4") && !b.contains("4") { return true }
                if !a.contains("4") && b.contains("4") { return false }
                if a.contains("3") && !b.contains("3") { return true }
                if !a.contains("3") && b.contains("3") { return false }
                return a > b
            }

        return grokModels.isEmpty ? CloudAIProvider.grok.availableModels : Array(grokModels.prefix(8))
    }

    // MARK: - Test Connection

    /// Test connection using minimal tokens to verify API key and connectivity
    /// Uses max_tokens: 1 with simple "ping" prompt for cost efficiency
    func testConnection() async throws -> Bool {
        let provider = settings.selectedProvider
        let apiKey = settings.currentAPIKey

        // Apple PCC doesn't need an API key or connection test
        if provider == .applePCC {
            return true
        }

        guard !apiKey.isEmpty else {
            throw CloudAIError.noAPIKey
        }

        // Use provider-specific minimal ping request
        switch provider {
        case .applePCC:
            // Already handled above
            break
        case .openai, .grok, .groq:
            try await pingOpenAICompatible(provider: provider, apiKey: apiKey)
        case .claude:
            try await pingClaude(apiKey: apiKey)
        case .gemini:
            try await pingGemini(apiKey: apiKey)
        }

        return true
    }

    /// Ping OpenAI-compatible APIs (OpenAI, Grok, Groq) with minimal tokens
    private func pingOpenAICompatible(provider: CloudAIProvider, apiKey: String) async throws {
        let endpoint = apiEndpoint(for: provider)

        // Use cheapest model for each provider
        let cheapModel: String
        switch provider {
        case .openai: cheapModel = "gpt-4o-mini"
        case .grok: cheapModel = "grok-2-1212"
        case .groq: cheapModel = "llama-3.1-8b-instant" // Free tier model
        default: cheapModel = provider.defaultModel
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": cheapModel,
            "messages": [["role": "user", "content": "ping"]],
            "max_tokens": 1
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CloudAIError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        // Verify response has expected structure
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard json?["choices"] != nil else {
            throw CloudAIError.invalidResponse
        }
    }

    /// Ping Claude API with minimal tokens
    private func pingClaude(apiKey: String) async throws {
        let endpoint = apiEndpoint(for: .claude)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Use cheapest Claude model
        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251015",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "ping"]]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CloudAIError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        // Verify response has expected structure
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard json?["content"] != nil else {
            throw CloudAIError.invalidResponse
        }
    }

    /// Ping Gemini API with minimal request
    private func pingGemini(apiKey: String) async throws {
        // Use cheapest Gemini model
        let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)")!

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": "ping"]]]
            ],
            "generationConfig": [
                "maxOutputTokens": 1
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CloudAIError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        // Verify response has expected structure
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard json?["candidates"] != nil else {
            throw CloudAIError.invalidResponse
        }
    }

    // MARK: - Apple PCC via Shortcuts

    /// Analyze transcript using Apple Intelligence via Shortcuts
    private func analyzeWithShortcuts(
        transcript: String,
        episodeTitle: String,
        podcastTitle: String,
        analysisType: CloudAnalysisType,
        progressCallback: ((String, Double) -> Void)? = nil
    ) async throws -> CloudAnalysisResult {
        progressCallback?("Starting Shortcuts analysis...", 0.2)

        // Build the prompt with JSON format
        let prompt = buildShortcutsPrompt(
            transcript: transcript,
            episodeTitle: episodeTitle,
            podcastTitle: podcastTitle,
            analysisType: analysisType
        )

        progressCallback?("Running shortcut...", 0.4)

        let shortcutsService = ShortcutsAIService.shared

        do {
            let rawResult = try await shortcutsService.runShortcut(input: prompt, timeout: 180)

            progressCallback?("Parsing response...", 0.8)

            // Try to parse JSON response
            var parsedSummary: ParsedSummaryResponse?
            var parsedEntities: ParsedEntitiesResponse?
            var parsedHighlights: ParsedHighlightsResponse?
            var parsedFullAnalysis: ParsedFullAnalysisResponse?
            var jsonParseWarning: String?

            // Clean the response - remove markdown code blocks if present
            let cleanedResult = cleanJSONResponse(rawResult)

            if let data = cleanedResult.data(using: .utf8) {
                switch analysisType {
                case .summary:
                    if let parsed = try? JSONDecoder().decode(ParsedSummaryResponse.self, from: data) {
                        parsedSummary = parsed
                    } else {
                        jsonParseWarning = "JSON parsing failed - showing raw response"
                    }
                case .entities:
                    if let parsed = try? JSONDecoder().decode(ParsedEntitiesResponse.self, from: data) {
                        parsedEntities = parsed
                    } else {
                        jsonParseWarning = "JSON parsing failed - showing raw response"
                    }
                case .highlights:
                    if let parsed = try? JSONDecoder().decode(ParsedHighlightsResponse.self, from: data) {
                        parsedHighlights = parsed
                    } else {
                        jsonParseWarning = "JSON parsing failed - showing raw response"
                    }
                case .fullAnalysis:
                    if let parsed = try? JSONDecoder().decode(ParsedFullAnalysisResponse.self, from: data) {
                        parsedFullAnalysis = parsed
                    } else {
                        jsonParseWarning = "JSON parsing failed - showing raw response"
                    }
                }
            }

            progressCallback?("Done", 1.0)

            // Format the raw response if JSON parsing failed
            let displayContent: String
            if jsonParseWarning != nil {
                displayContent = formatRawResponseForDisplay(rawResult)
            } else {
                displayContent = rawResult
            }

            return CloudAnalysisResult(
                type: analysisType,
                content: displayContent,
                parsedSummary: parsedSummary,
                parsedEntities: parsedEntities,
                parsedHighlights: parsedHighlights,
                parsedFullAnalysis: parsedFullAnalysis,
                provider: .applePCC,
                model: "Apple Intelligence (via Shortcuts)",
                timestamp: Date(),
                jsonParseWarning: jsonParseWarning
            )

        } catch let error as ShortcutsError {
            progressCallback?("Error", 1.0)
            throw CloudAIError.apiError(statusCode: 0, message: error.localizedDescription)
        } catch {
            progressCallback?("Error", 1.0)
            throw error
        }
    }

    /// Clean JSON response by removing markdown code blocks
    private func cleanJSONResponse(_ response: String) -> String {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code blocks
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }

        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Format raw response for human-readable display
    private func formatRawResponseForDisplay(_ response: String) -> String {
        // Try to pretty print if it's JSON
        if let data = response.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            return prettyString
        }

        // Otherwise return as-is
        return response
    }

    /// Ask a question using Apple Intelligence via Shortcuts
    private func askQuestionWithShortcuts(
        question: String,
        transcript: String,
        episodeTitle: String,
        progressCallback: ((String, Double) -> Void)? = nil
    ) async throws -> CloudQAResult {
        progressCallback?("Preparing question for Shortcuts...", 0.2)

        let languageInstruction = settings.analysisLanguage.getLanguageInstruction()

        let prompt = """
        Based on this podcast transcript, please answer the following question.

        Episode: \(episodeTitle)

        Question: \(question)

        \(languageInstruction)

        Transcript:
        \(transcript)

        Please provide a clear, detailed answer based ONLY on the information in the transcript.
        If the answer is not in the transcript, say so clearly.
        """

        progressCallback?("Running shortcut...", 0.4)

        let shortcutsService = ShortcutsAIService.shared

        do {
            let result = try await shortcutsService.runShortcut(input: prompt, timeout: 180)

            progressCallback?("Done", 1.0)

            return CloudQAResult(
                question: question,
                answer: result,
                confidence: "unknown",
                relatedTopics: nil,
                provider: .applePCC,
                model: "Apple Intelligence (via Shortcuts)",
                timestamp: Date()
            )

        } catch let error as ShortcutsError {
            progressCallback?("Error", 1.0)
            throw CloudAIError.apiError(statusCode: 0, message: error.localizedDescription)
        } catch {
            progressCallback?("Error", 1.0)
            throw error
        }
    }

    /// Build a prompt for Shortcuts analysis - matches the JSON format used by other LLMs
    private func buildShortcutsPrompt(
        transcript: String,
        episodeTitle: String,
        podcastTitle: String,
        analysisType: CloudAnalysisType
    ) -> String {
        let languageInstruction = settings.analysisLanguage.getLanguageInstruction()
        let languageLine = languageInstruction.isEmpty ? "" : "\n\nLanguage: \(languageInstruction)"

        switch analysisType {
        case .summary:
            return """
            You are an expert podcast analyst. Please analyze this podcast episode.

            Podcast: \(podcastTitle)
            Episode: \(episodeTitle)

            IMPORTANT: Return ONLY valid JSON with no additional text, markdown, or code blocks.

            Return JSON in this exact format:
            {
                "summary": "A 2-3 paragraph summary of the episode",
                "mainTopics": ["topic1", "topic2", "topic3"],
                "keyTakeaways": ["takeaway1", "takeaway2", "takeaway3"],
                "targetAudience": "Description of who would benefit from this episode",
                "engagementLevel": "high/medium/low"
            }\(languageLine)

            Transcript:
            \(transcript)
            """

        case .entities:
            return """
            You are an expert at extracting named entities from text. Please analyze this podcast episode.

            Podcast: \(podcastTitle)
            Episode: \(episodeTitle)

            IMPORTANT: Return ONLY valid JSON with no additional text, markdown, or code blocks.

            Return JSON in this exact format:
            {
                "people": ["person1", "person2"],
                "organizations": ["org1", "org2"],
                "products": ["product1", "product2"],
                "locations": ["location1", "location2"],
                "resources": ["book1", "article1"]
            }\(languageLine)

            Transcript:
            \(transcript)
            """

        case .highlights:
            return """
            You are an expert at identifying key moments and highlights in podcast episodes. Please analyze this episode.

            Podcast: \(podcastTitle)
            Episode: \(episodeTitle)

            IMPORTANT: Return ONLY valid JSON with no additional text, markdown, or code blocks.

            Return JSON in this exact format:
            {
                "highlights": ["highlight1", "highlight2", "highlight3"],
                "bestQuote": "The most memorable quote from the episode",
                "actionItems": ["action1", "action2"],
                "controversialPoints": ["point1"],
                "entertainingMoments": ["moment1"]
            }\(languageLine)

            Transcript:
            \(transcript)
            """

        case .fullAnalysis:
            return """
            You are an expert podcast analyst. Provide a comprehensive analysis of this podcast episode.

            Podcast: \(podcastTitle)
            Episode: \(episodeTitle)

            IMPORTANT: Return ONLY valid JSON with no additional text, markdown, or code blocks.

            Return JSON in this exact format:
            {
                "overview": "2-3 paragraph executive summary of the episode",
                "mainTopics": [
                    {
                        "topic": "Topic Name",
                        "summary": "Brief summary of this topic",
                        "keyPoints": ["point 1", "point 2"]
                    }
                ],
                "keyInsights": ["insight 1", "insight 2", "insight 3"],
                "notableQuotes": ["quote 1", "quote 2"],
                "actionableAdvice": ["advice 1", "advice 2"],
                "conclusion": "Overall assessment and who would benefit from this episode"
            }\(languageLine)

            Transcript:
            \(transcript)
            """
        }
    }

    // MARK: - Streaming Transcript Analysis

    /// Analyze transcript with streaming response
    func analyzeTranscriptStreaming(
        _ transcript: String,
        episodeTitle: String,
        podcastTitle: String,
        analysisType: CloudAnalysisType,
        podcastLanguage: String? = nil,
        onChunk: @escaping (String) -> Void,
        progressCallback: ((String, Double) -> Void)? = nil
    ) async throws -> CloudAnalysisResult {
        let provider = settings.selectedProvider
        let apiKey = settings.currentAPIKey
        let model = settings.currentModel

        // Handle Apple PCC via Shortcuts
        if provider == .applePCC {
            progressCallback?("Preparing for Shortcuts...", 0.2)
            return try await analyzeWithShortcuts(
                transcript: transcript,
                episodeTitle: episodeTitle,
                podcastTitle: podcastTitle,
                analysisType: analysisType,
                progressCallback: progressCallback
            )
        }

        guard !apiKey.isEmpty else {
            throw CloudAIError.noAPIKey
        }

        progressCallback?("Preparing analysis...", 0.1)

        let systemPrompt = buildSystemPrompt(for: analysisType, podcastLanguage: podcastLanguage)
        let userPrompt = buildUserPrompt(
            transcript: transcript,
            episodeTitle: episodeTitle,
            podcastTitle: podcastTitle,
            analysisType: analysisType
        )

        progressCallback?("Connecting to \(provider.displayName)...", 0.15)

        // Use higher token limit for fullAnalysis to prevent truncation
        let maxTokens = analysisType == .fullAnalysis ? 8192 : 4096

        // Use streaming for the request with progress updates
        let fullResponse = try await sendStreamingRequest(
            prompt: userPrompt,
            systemPrompt: systemPrompt,
            provider: provider,
            apiKey: apiKey,
            model: model,
            maxTokens: maxTokens,
            onChunk: { text in
                onChunk(text)
                // Update progress based on text length (estimate ~4000 chars for full response)
                let estimatedProgress = min(0.85, 0.2 + Double(text.count) / 5000.0 * 0.65)
                progressCallback?("Generating response...", estimatedProgress)
            }
        )

        progressCallback?("Parsing response...", 0.9)

        // Parse the JSON response based on analysis type
        var parsedSummary: ParsedSummaryResponse?
        var parsedEntities: ParsedEntitiesResponse?
        var parsedHighlights: ParsedHighlightsResponse?
        var parsedFullAnalysis: ParsedFullAnalysisResponse?

        switch analysisType {
        case .summary:
            parsedSummary = parseJSON(fullResponse, as: ParsedSummaryResponse.self)
        case .entities:
            parsedEntities = parseJSON(fullResponse, as: ParsedEntitiesResponse.self)
        case .highlights:
            parsedHighlights = parseJSON(fullResponse, as: ParsedHighlightsResponse.self)
        case .fullAnalysis:
            parsedFullAnalysis = parseJSON(fullResponse, as: ParsedFullAnalysisResponse.self)
        }

        progressCallback?("Done", 1.0)

        return CloudAnalysisResult(
            type: analysisType,
            content: fullResponse,
            parsedSummary: parsedSummary,
            parsedEntities: parsedEntities,
            parsedHighlights: parsedHighlights,
            parsedFullAnalysis: parsedFullAnalysis,
            provider: provider,
            model: model,
            timestamp: Date()
        )
    }

    // MARK: - Transcript Analysis

    func analyzeTranscript(
        _ transcript: String,
        episodeTitle: String,
        podcastTitle: String,
        analysisType: CloudAnalysisType,
        podcastLanguage: String? = nil,
        progressCallback: ((String, Double) -> Void)? = nil
    ) async throws -> CloudAnalysisResult {
        let provider = settings.selectedProvider
        let apiKey = settings.currentAPIKey
        let model = settings.currentModel

        guard !apiKey.isEmpty else {
            throw CloudAIError.noAPIKey
        }

        progressCallback?("Preparing analysis...", 0.1)

        let systemPrompt = buildSystemPrompt(for: analysisType, podcastLanguage: podcastLanguage)
        let userPrompt = buildUserPrompt(
            transcript: transcript,
            episodeTitle: episodeTitle,
            podcastTitle: podcastTitle,
            analysisType: analysisType
        )

        progressCallback?("Sending to \(provider.displayName)...", 0.3)

        let response = try await sendRequest(
            prompt: userPrompt,
            systemPrompt: systemPrompt,
            provider: provider,
            apiKey: apiKey,
            model: model
        )

        progressCallback?("Parsing response...", 0.8)

        // Parse the JSON response based on analysis type
        var parsedSummary: ParsedSummaryResponse?
        var parsedEntities: ParsedEntitiesResponse?
        var parsedHighlights: ParsedHighlightsResponse?
        var parsedFullAnalysis: ParsedFullAnalysisResponse?

        switch analysisType {
        case .summary:
            parsedSummary = parseJSON(response, as: ParsedSummaryResponse.self)
        case .entities:
            parsedEntities = parseJSON(response, as: ParsedEntitiesResponse.self)
        case .highlights:
            parsedHighlights = parseJSON(response, as: ParsedHighlightsResponse.self)
        case .fullAnalysis:
            parsedFullAnalysis = parseJSON(response, as: ParsedFullAnalysisResponse.self)
        }

        progressCallback?("Done", 1.0)

        return CloudAnalysisResult(
            type: analysisType,
            content: response,
            parsedSummary: parsedSummary,
            parsedEntities: parsedEntities,
            parsedHighlights: parsedHighlights,
            parsedFullAnalysis: parsedFullAnalysis,
            provider: provider,
            model: model,
            timestamp: Date()
        )
    }

    /// Parse JSON from AI response, handling markdown code blocks
    private func parseJSON<T: Decodable>(_ response: String, as type: T.Type) -> T? {
        // Extract JSON from markdown code blocks if present
        var jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove ```json ... ``` wrapper
        if jsonString.hasPrefix("```json") {
            jsonString = String(jsonString.dropFirst(7))
        } else if jsonString.hasPrefix("```") {
            jsonString = String(jsonString.dropFirst(3))
        }
        if jsonString.hasSuffix("```") {
            jsonString = String(jsonString.dropLast(3))
        }
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = jsonString.data(using: .utf8) else { return nil }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            logger.error("JSON parsing failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Question Answering

    func askQuestion(
        _ question: String,
        transcript: String,
        episodeTitle: String,
        podcastLanguage: String? = nil,
        progressCallback: ((String, Double) -> Void)? = nil
    ) async throws -> CloudQAResult {
        let provider = settings.selectedProvider
        let apiKey = settings.currentAPIKey
        let model = settings.currentModel

        // Handle Apple PCC via Shortcuts
        if provider == .applePCC {
            return try await askQuestionWithShortcuts(
                question: question,
                transcript: transcript,
                episodeTitle: episodeTitle,
                progressCallback: progressCallback
            )
        }

        guard !apiKey.isEmpty else {
            throw CloudAIError.noAPIKey
        }

        progressCallback?("Processing question...", 0.2)

        // Get language instruction based on user setting
        let languageInstruction = settings.analysisLanguage.getLanguageInstruction(podcastLanguage: podcastLanguage)
        let languageLine = languageInstruction.isEmpty ? "" : "\n\n\(languageInstruction)"

        let systemPrompt = """
        You are a helpful assistant that answers questions about podcast episodes.
        Base your answers ONLY on the provided transcript.
        If the answer is not in the transcript, say so clearly.

        Respond in the following JSON format:
        {
            "answer": "Your detailed answer to the question",
            "confidence": "high/medium/low based on how clearly the transcript addresses this",
            "relatedTopics": ["topic1", "topic2"] or null if none
        }

        IMPORTANT: Return ONLY valid JSON, no additional text.\(languageLine)
        """

        let userPrompt = """
        Episode: \(episodeTitle)

        Question: \(question)

        Transcript:
        \(transcript)
        """

        progressCallback?("Getting answer from \(provider.displayName)...", 0.5)

        let response = try await sendRequest(
            prompt: userPrompt,
            systemPrompt: systemPrompt,
            provider: provider,
            apiKey: apiKey,
            model: model
        )

        progressCallback?("Parsing response...", 0.9)

        let parsed = parseJSON(response, as: ParsedQAResponse.self)

        progressCallback?("Done", 1.0)

        return CloudQAResult(
            question: question,
            answer: parsed?.answer ?? response,
            confidence: parsed?.confidence ?? "unknown",
            relatedTopics: parsed?.relatedTopics,
            provider: provider,
            model: model,
            timestamp: Date()
        )
    }

    // MARK: - Private: Build Prompts

    private func buildSystemPrompt(for type: CloudAnalysisType, podcastLanguage: String? = nil) -> String {
        // Get language instruction based on user setting
        let languageInstruction = settings.analysisLanguage.getLanguageInstruction(podcastLanguage: podcastLanguage)
        let languageLine = languageInstruction.isEmpty ? "" : "\n\n\(languageInstruction)"

        switch type {
        case .summary:
            return """
            You are an expert podcast analyst. Your task is to create comprehensive summaries of podcast episodes.

            Provide your response in the following JSON format:
            {
                "summary": "A 2-3 paragraph summary of the episode",
                "mainTopics": ["topic1", "topic2", "topic3"],
                "keyTakeaways": ["takeaway1", "takeaway2", "takeaway3"],
                "targetAudience": "Description of who would benefit from this episode",
                "engagementLevel": "high/medium/low"
            }\(languageLine)
            """

        case .entities:
            return """
            You are an expert at extracting named entities from text.

            Provide your response in the following JSON format:
            {
                "people": ["person1", "person2"],
                "organizations": ["org1", "org2"],
                "products": ["product1", "product2"],
                "locations": ["location1", "location2"],
                "resources": ["book1", "article1"]
            }\(languageLine)
            """

        case .highlights:
            return """
            You are an expert at identifying key moments and highlights in podcast episodes.

            Provide your response in the following JSON format:
            {
                "highlights": ["highlight1", "highlight2", "highlight3"],
                "bestQuote": "The most memorable quote from the episode",
                "actionItems": ["action1", "action2"],
                "controversialPoints": ["point1"] or null,
                "entertainingMoments": ["moment1"] or null
            }\(languageLine)
            """

        case .fullAnalysis:
            return """
            You are an expert podcast analyst. Provide a comprehensive analysis of this podcast episode.

            IMPORTANT: Return ONLY valid JSON with no additional text.

            Return JSON in this exact format:
            {
                "overview": "2-3 paragraph executive summary of the episode",
                "mainTopics": [
                    {
                        "topic": "Topic Name",
                        "summary": "Brief summary of this topic",
                        "keyPoints": ["point 1", "point 2"]
                    }
                ],
                "keyInsights": ["insight 1", "insight 2", "insight 3"],
                "notableQuotes": ["quote 1", "quote 2"],
                "actionableAdvice": ["advice 1", "advice 2"] or null,
                "conclusion": "Overall assessment and who would benefit from this episode"
            }\(languageLine)
            """
        }
    }

    private func buildUserPrompt(
        transcript: String,
        episodeTitle: String,
        podcastTitle: String,
        analysisType: CloudAnalysisType
    ) -> String {
        let instruction: String
        switch analysisType {
        case .summary:
            instruction = "Please provide a comprehensive summary of this podcast episode."
        case .entities:
            instruction = "Please extract all named entities from this podcast episode."
        case .highlights:
            instruction = "Please identify the key highlights and memorable moments from this episode."
        case .fullAnalysis:
            instruction = "Please provide a complete analysis of this podcast episode."
        }

        return """
        Podcast: \(podcastTitle)
        Episode: \(episodeTitle)

        \(instruction)

        Transcript:
        \(transcript)
        """
    }

    // MARK: - Private: Send Streaming Request

    private func sendStreamingRequest(
        prompt: String,
        systemPrompt: String,
        provider: CloudAIProvider,
        apiKey: String,
        model: String,
        maxTokens: Int = 4096,
        onChunk: @escaping (String) -> Void
    ) async throws -> String {
        switch provider {
        case .applePCC:
            // Apple PCC is handled via Shortcuts, not streaming API
            throw CloudAIError.apiError(statusCode: 0, message: "Apple PCC uses Shortcuts for processing")
        case .openai, .groq, .grok:
            return try await sendOpenAIStreamingRequest(
                prompt: prompt,
                systemPrompt: systemPrompt,
                apiKey: apiKey,
                model: model,
                endpoint: apiEndpoint(for: provider),
                maxTokens: maxTokens,
                onChunk: onChunk
            )
        case .claude:
            return try await sendClaudeStreamingRequest(
                prompt: prompt,
                systemPrompt: systemPrompt,
                apiKey: apiKey,
                model: model,
                maxTokens: maxTokens,
                onChunk: onChunk
            )
        case .gemini:
            return try await sendGeminiStreamingRequest(
                prompt: prompt,
                systemPrompt: systemPrompt,
                apiKey: apiKey,
                model: model,
                maxTokens: maxTokens,
                onChunk: onChunk
            )
        }
    }

    // MARK: - OpenAI Streaming

    private func sendOpenAIStreamingRequest(
        prompt: String,
        systemPrompt: String,
        apiKey: String,
        model: String,
        endpoint: URL,
        maxTokens: Int,
        onChunk: @escaping (String) -> Void
    ) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": maxTokens,
            "stream": true
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            // Try to read error message from stream
            var errorMessage = ""
            for try await line in bytes.lines {
                errorMessage += line
                if errorMessage.count > 500 { break }
            }
            // Parse error message from JSON if possible
            if let data = errorMessage.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw CloudAIError.apiError(statusCode: httpResponse.statusCode, message: message)
            }
            throw CloudAIError.apiError(statusCode: httpResponse.statusCode, message: errorMessage.isEmpty ? "Request failed" : errorMessage)
        }

        var fullContent = ""

        for try await line in bytes.lines {
            guard line.hasPrefix("data: "), line != "data: [DONE]" else { continue }

            let jsonString = String(line.dropFirst(6))
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else {
                continue
            }

            fullContent += content
            await MainActor.run { onChunk(fullContent) }
        }

        return fullContent
    }

    // MARK: - Claude Streaming

    private func sendClaudeStreamingRequest(
        prompt: String,
        systemPrompt: String,
        apiKey: String,
        model: String,
        maxTokens: Int,
        onChunk: @escaping (String) -> Void
    ) async throws -> String {
        let endpoint = apiEndpoint(for: .claude)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "stream": true
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            // Try to read error message from stream
            var errorMessage = ""
            for try await line in bytes.lines {
                errorMessage += line
                if errorMessage.count > 500 { break }
            }
            // Parse Claude error format
            if let data = errorMessage.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw CloudAIError.apiError(statusCode: httpResponse.statusCode, message: message)
            }
            throw CloudAIError.apiError(statusCode: httpResponse.statusCode, message: errorMessage.isEmpty ? "Claude request failed" : errorMessage)
        }

        var fullContent = ""

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }

            let jsonString = String(line.dropFirst(6))
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            // Claude uses "content_block_delta" events for text streaming
            if let type = json["type"] as? String,
               type == "content_block_delta",
               let delta = json["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                fullContent += text
                await MainActor.run { onChunk(fullContent) }
            }
        }

        return fullContent
    }

    // MARK: - Gemini Streaming

    private func sendGeminiStreamingRequest(
        prompt: String,
        systemPrompt: String,
        apiKey: String,
        model: String,
        maxTokens: Int,
        onChunk: @escaping (String) -> Void
    ) async throws -> String {
        // Gemini uses streamGenerateContent endpoint
        let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?key=\(apiKey)&alt=sse")!

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": "\(systemPrompt)\n\n\(prompt)"]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": maxTokens
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            // Try to read error message from stream
            var errorMessage = ""
            for try await line in bytes.lines {
                errorMessage += line
                if errorMessage.count > 500 { break }
            }
            // Parse Gemini error format
            if let data = errorMessage.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw CloudAIError.apiError(statusCode: httpResponse.statusCode, message: message)
            }
            throw CloudAIError.apiError(statusCode: httpResponse.statusCode, message: errorMessage.isEmpty ? "Gemini request failed" : errorMessage)
        }

        var fullContent = ""

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }

            let jsonString = String(line.dropFirst(6))
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String else {
                continue
            }

            fullContent += text
            await MainActor.run { onChunk(fullContent) }
        }

        return fullContent
    }

    // MARK: - Private: Send Request

    private func sendRequest(
        prompt: String,
        systemPrompt: String,
        provider: CloudAIProvider,
        apiKey: String,
        model: String
    ) async throws -> String {
        switch provider {
        case .applePCC:
            // Apple PCC is handled via Shortcuts, not direct API
            throw CloudAIError.apiError(statusCode: 0, message: "Apple PCC uses Shortcuts for processing")
        case .openai, .groq, .grok:
            return try await sendOpenAICompatibleRequest(
                prompt: prompt,
                systemPrompt: systemPrompt,
                apiKey: apiKey,
                model: model,
                endpoint: apiEndpoint(for: provider)
            )
        case .claude:
            return try await sendClaudeRequest(
                prompt: prompt,
                systemPrompt: systemPrompt,
                apiKey: apiKey,
                model: model
            )
        case .gemini:
            return try await sendGeminiRequest(
                prompt: prompt,
                systemPrompt: systemPrompt,
                apiKey: apiKey,
                model: model
            )
        }
    }

    // MARK: - OpenAI Compatible (OpenAI, Groq, Grok)

    private func sendOpenAICompatibleRequest(
        prompt: String,
        systemPrompt: String,
        apiKey: String,
        model: String,
        endpoint: URL
    ) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": 8192  // Increased for full JSON responses
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("API error (\(httpResponse.statusCode)): \(errorBody)")
            throw CloudAIError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw CloudAIError.invalidResponse
        }

        return content
    }

    // MARK: - Claude

    private func sendClaudeRequest(
        prompt: String,
        systemPrompt: String,
        apiKey: String,
        model: String
    ) async throws -> String {
        let endpoint = apiEndpoint(for: .claude)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 8192,  // Increased for full JSON responses
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Claude API error (\(httpResponse.statusCode)): \(errorBody)")
            throw CloudAIError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw CloudAIError.invalidResponse
        }

        return text
    }

    // MARK: - Gemini

    private func sendGeminiRequest(
        prompt: String,
        systemPrompt: String,
        apiKey: String,
        model: String
    ) async throws -> String {
        let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": "\(systemPrompt)\n\n\(prompt)"]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 8192  // Increased for full JSON responses
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Gemini API error (\(httpResponse.statusCode)): \(errorBody)")
            throw CloudAIError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let candidates = json?["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw CloudAIError.invalidResponse
        }

        return text
    }
}

// MARK: - Supporting Types

enum CloudAnalysisType: String, CaseIterable {
    case summary = "Summary"
    case entities = "Entities"
    case highlights = "Highlights"
    case fullAnalysis = "Full Analysis"

    var icon: String {
        switch self {
        case .summary: return "doc.text"
        case .entities: return "person.2"
        case .highlights: return "star"
        case .fullAnalysis: return "sparkles"
        }
    }
}

struct CloudAnalysisResult {
    let type: CloudAnalysisType
    let content: String
    let parsedSummary: ParsedSummaryResponse?
    let parsedEntities: ParsedEntitiesResponse?
    let parsedHighlights: ParsedHighlightsResponse?
    let parsedFullAnalysis: ParsedFullAnalysisResponse?
    let provider: CloudAIProvider
    let model: String
    let timestamp: Date
    /// Warning message when JSON parsing fails (e.g., when using Apple Intelligence via Shortcuts)
    let jsonParseWarning: String?

    init(
        type: CloudAnalysisType,
        content: String,
        parsedSummary: ParsedSummaryResponse? = nil,
        parsedEntities: ParsedEntitiesResponse? = nil,
        parsedHighlights: ParsedHighlightsResponse? = nil,
        parsedFullAnalysis: ParsedFullAnalysisResponse? = nil,
        provider: CloudAIProvider,
        model: String,
        timestamp: Date,
        jsonParseWarning: String? = nil
    ) {
        self.type = type
        self.content = content
        self.parsedSummary = parsedSummary
        self.parsedEntities = parsedEntities
        self.parsedHighlights = parsedHighlights
        self.parsedFullAnalysis = parsedFullAnalysis
        self.provider = provider
        self.model = model
        self.timestamp = timestamp
        self.jsonParseWarning = jsonParseWarning
    }
}

struct CloudQAResult {
    let question: String
    let answer: String
    let confidence: String
    let relatedTopics: [String]?
    let provider: CloudAIProvider
    let model: String
    let timestamp: Date
}

enum CloudAIError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case networkError(Error)
    case quotaExceeded(provider: String)
    case invalidAPIKey(provider: String)
    case modelNotFound(model: String)
    case rateLimited(provider: String)
    case contextTooLong(provider: String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured. Please add your API key in Settings > AI Settings."
        case .invalidResponse:
            return "Invalid response from AI provider."
        case .apiError(let statusCode, let message):
            return parseAPIError(statusCode: statusCode, message: message)
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .quotaExceeded(let provider):
            return "API quota exceeded for \(provider). Please check your billing/usage limits or try again later."
        case .invalidAPIKey(let provider):
            return "Invalid API key for \(provider). Please check your API key in Settings > AI Settings."
        case .modelNotFound(let model):
            return "Model '\(model)' not found. Please select a different model in Settings > AI Settings."
        case .rateLimited(let provider):
            return "Too many requests to \(provider). Please wait a moment and try again."
        case .contextTooLong(let provider):
            return "Transcript too long for \(provider). Try a shorter episode or use a model with larger context window."
        }
    }

    private func parseAPIError(statusCode: Int, message: String) -> String {
        let lowercaseMessage = message.lowercased()

        switch statusCode {
        case 401:
            return "Invalid or expired API key. Please check your API key in Settings."
        case 403:
            return "Access denied. Your API key may not have permission for this model."
        case 404:
            if lowercaseMessage.contains("model") {
                return "Model not found. Please select a different model in Settings > AI Settings."
            }
            return "Resource not found. Please try again."
        case 429:
            if lowercaseMessage.contains("quota") || lowercaseMessage.contains("exceeded") {
                return "API quota exceeded. Please check your billing limits or upgrade your plan."
            }
            return "Rate limit exceeded. Please wait a moment and try again."
        case 500, 502, 503:
            return "AI service temporarily unavailable. Please try again later."
        case 400:
            if lowercaseMessage.contains("context") || lowercaseMessage.contains("token") || lowercaseMessage.contains("length") {
                return "Transcript too long. Try a shorter episode or use a model with larger context."
            }
            return "Invalid request: \(message)"
        default:
            return "API error (\(statusCode)): \(message)"
        }
    }
}
