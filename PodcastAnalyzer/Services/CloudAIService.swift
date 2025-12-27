//
//  CloudAIService.swift
//  PodcastAnalyzer
//
//  Service for cloud-based AI analysis using user-provided API keys (BYOK)
//  Supports OpenAI, Claude, Gemini, and Grok
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.podcastanalyzer", category: "CloudAIService")

// MARK: - Cloud AI Service

actor CloudAIService {
    static let shared = CloudAIService()

    private let settings = AISettingsManager.shared

    // MARK: - API Endpoints

    private func apiEndpoint(for provider: CloudAIProvider) -> URL {
        switch provider {
        case .openai:
            return URL(string: "https://api.openai.com/v1/chat/completions")!
        case .claude:
            return URL(string: "https://api.anthropic.com/v1/messages")!
        case .gemini:
            return URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!
        case .grok:
            return URL(string: "https://api.x.ai/v1/chat/completions")!
        }
    }

    // MARK: - Fetch Available Models

    /// Fetch available models from the provider's API
    func fetchAvailableModels(for provider: CloudAIProvider, apiKey: String) async throws -> [String] {
        switch provider {
        case .openai:
            return try await fetchOpenAIModels(apiKey: apiKey)
        case .claude:
            return try await fetchClaudeModels(apiKey: apiKey)
        case .gemini:
            return try await fetchGeminiModels(apiKey: apiKey)
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

        var request = URLRequest(url: endpoint)

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

    func testConnection() async throws -> Bool {
        let provider = settings.selectedProvider
        let apiKey = settings.currentAPIKey

        guard !apiKey.isEmpty else {
            throw CloudAIError.noAPIKey
        }

        let testPrompt = "Say 'Hello' in one word."

        _ = try await sendRequest(
            prompt: testPrompt,
            systemPrompt: "You are a helpful assistant.",
            provider: provider,
            apiKey: apiKey,
            model: settings.currentModel
        )

        return true
    }

    // MARK: - Transcript Analysis

    func analyzeTranscript(
        _ transcript: String,
        episodeTitle: String,
        podcastTitle: String,
        analysisType: CloudAnalysisType,
        progressCallback: ((String, Double) -> Void)? = nil
    ) async throws -> CloudAnalysisResult {
        let provider = settings.selectedProvider
        let apiKey = settings.currentAPIKey
        let model = settings.currentModel

        guard !apiKey.isEmpty else {
            throw CloudAIError.noAPIKey
        }

        progressCallback?("Preparing analysis...", 0.1)

        let systemPrompt = buildSystemPrompt(for: analysisType)
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

        progressCallback?("Processing response...", 0.9)

        return CloudAnalysisResult(
            type: analysisType,
            content: response,
            provider: provider,
            model: model,
            timestamp: Date()
        )
    }

    // MARK: - Question Answering

    func askQuestion(
        _ question: String,
        transcript: String,
        episodeTitle: String,
        progressCallback: ((String, Double) -> Void)? = nil
    ) async throws -> String {
        let provider = settings.selectedProvider
        let apiKey = settings.currentAPIKey
        let model = settings.currentModel

        guard !apiKey.isEmpty else {
            throw CloudAIError.noAPIKey
        }

        progressCallback?("Processing question...", 0.2)

        let systemPrompt = """
        You are a helpful assistant that answers questions about podcast episodes.
        Base your answers ONLY on the provided transcript.
        If the answer is not in the transcript, say so clearly.
        Include approximate timestamps when possible.
        Be concise but thorough.
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

        progressCallback?("Done", 1.0)

        return response
    }

    // MARK: - Private: Build Prompts

    private func buildSystemPrompt(for type: CloudAnalysisType) -> String {
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
            }
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
            }
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
            }
            """

        case .fullAnalysis:
            return """
            You are an expert podcast analyst. Provide a comprehensive analysis of this podcast episode.

            Include:
            1. Executive Summary (2-3 paragraphs)
            2. Main Topics Discussed (bulleted list)
            3. Key Takeaways (bulleted list)
            4. Notable Quotes
            5. People/Organizations Mentioned
            6. Action Items or Recommendations
            7. Target Audience
            8. Overall Assessment

            Format your response in clear sections with headers.
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

    // MARK: - Private: Send Request

    private func sendRequest(
        prompt: String,
        systemPrompt: String,
        provider: CloudAIProvider,
        apiKey: String,
        model: String
    ) async throws -> String {
        switch provider {
        case .openai, .grok:
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

    // MARK: - OpenAI Compatible (OpenAI, Grok)

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
            "max_tokens": 4096
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
            "max_tokens": 4096,
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
                "maxOutputTokens": 4096
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
    let provider: CloudAIProvider
    let model: String
    let timestamp: Date
}

enum CloudAIError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured. Please add your API key in Settings > AI Settings."
        case .invalidResponse:
            return "Invalid response from AI provider."
        case .apiError(let statusCode, let message):
            return "API error (\(statusCode)): \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
