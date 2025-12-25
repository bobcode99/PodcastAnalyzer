//
//  EpisodeAnalysisService.swift
//  PodcastAnalyzer
//
//  Created by Claude Code
//  Service for AI-powered episode analysis using Apple Foundation Models
//

import Foundation
import FoundationModels
import os.log

private let logger = Logger(subsystem: "com.podcastanalyzer", category: "EpisodeAnalysisService")

/// Service for analyzing podcast episodes using Apple Foundation Models (iOS 26+)
@available(iOS 26.0, macOS 26.0, *)
actor EpisodeAnalysisService {

    // MARK: - Properties

    private let session: LanguageModelSession
    private let maxContextTokens = 4096
    private let maxInputTokens = 3000 // Leave room for output
    private let maxOutputTokens = 1000

    // MARK: - Initialization

    init() {
        // Create session with system instructions for podcast analysis
        self.session = LanguageModelSession(instructions: """
            You are an expert podcast analyst. Your role is to analyze podcast episode transcripts and provide insightful, accurate analysis.

            Key guidelines:
            - Be concise and precise in your responses
            - Focus on factual information from the transcript
            - Identify key themes, topics, and insights
            - Provide actionable takeaways when possible
            - Maintain objectivity and avoid bias
            - If information is not in the transcript, say so
            """)
    }

    // MARK: - Availability Checking

    /// Check if Foundation Models are available on this device
    /// - Returns: Availability status with detailed reason if unavailable
    func checkAvailability() -> FoundationModelsAvailability {
        let systemModel = SystemLanguageModel.default

        switch systemModel.availability {
        case .available:
            return .available

        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(reason: "Apple Intelligence is not enabled. Please enable it in Settings → Apple Intelligence & Siri.")

        case .unavailable(.deviceNotEligible):
            return .unavailable(reason: "This device doesn't support Apple Intelligence. Requires iPhone 15 Pro or newer, or M1+ Mac/iPad.")

        case .unavailable(.modelNotReady):
            return .unavailable(reason: "The AI model is downloading. This may take a few minutes.")

        case .unavailable(_):
            return .unavailable(reason: "Apple Intelligence is currently unavailable.")
        }
    }

    /// Simple boolean check for availability
    var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    // MARK: - Summary Generation

    /// Generate comprehensive summary from episode transcript
    /// - Parameters:
    ///   - transcriptText: Full transcript text (will be chunked if needed)
    ///   - episodeTitle: Title of the episode for context
    ///   - language: Language code for token estimation (default "en")
    /// - Returns: Structured episode summary
    func generateSummary(
        from transcriptText: String,
        episodeTitle: String,
        language: String = "en"
    ) async throws -> EpisodeSummary {
        logger.info("Generating summary for episode: \(episodeTitle)")

        let chunks = SRTParser.chunkText(transcriptText, maxTokens: maxInputTokens, language: language)

        if chunks.count == 1 {
            // Single chunk - direct summarization
            return try await generateSummarySingleChunk(transcriptText, episodeTitle: episodeTitle)
        } else {
            // Multiple chunks - hierarchical summarization
            return try await generateSummaryMultiChunk(chunks, episodeTitle: episodeTitle)
        }
    }

    private func generateSummarySingleChunk(_ text: String, episodeTitle: String) async throws -> EpisodeSummary {
        let prompt = """
        Analyze this podcast episode transcript and provide a comprehensive summary.

        Episode: \(episodeTitle)

        Transcript:
        \(text)
        """

        let summary: EpisodeSummary = try await session.respond(to: prompt)
        logger.info("Summary generated successfully")
        return summary
    }

    private func generateSummaryMultiChunk(_ chunks: [String], episodeTitle: String) async throws -> EpisodeSummary {
        logger.info("Generating summary from \(chunks.count) chunks")

        // Step 1: Summarize each chunk
        var chunkSummaries: [String] = []

        for (index, chunk) in chunks.enumerated() {
            let prompt = """
            Summarize this section (part \(index + 1) of \(chunks.count)) of the podcast episode "\(episodeTitle)".
            Focus on main points and key information.

            Transcript section:
            \(chunk)
            """

            let response = try await session.respond(to: prompt)
            chunkSummaries.append(response)
        }

        // Step 2: Generate final summary from chunk summaries
        let combinedSummaries = chunkSummaries.enumerated()
            .map { "Part \($0 + 1): \($1)" }
            .joined(separator: "\n\n")

        let finalPrompt = """
        Based on these summaries of different parts of the podcast episode "\(episodeTitle)", create a comprehensive final summary.

        \(combinedSummaries)
        """

        let finalSummary: EpisodeSummary = try await session.respond(to: finalPrompt)
        logger.info("Multi-chunk summary generated successfully")
        return finalSummary
    }

    // MARK: - Tag Generation

    /// Generate tags and categorization for episode
    /// - Parameters:
    ///   - transcriptText: Full transcript text
    ///   - episodeTitle: Title of the episode
    ///   - language: Language code
    /// - Returns: Structured tags and categories
    func generateTags(
        from transcriptText: String,
        episodeTitle: String,
        language: String = "en"
    ) async throws -> EpisodeTags {
        logger.info("Generating tags for episode: \(episodeTitle)")

        // For tags, we can work with a condensed version if too long
        let effectiveText = try await condenseIfNeeded(transcriptText, targetTokens: maxInputTokens, language: language)

        let prompt = """
        Analyze this podcast episode and generate relevant tags and categorization.

        Episode: \(episodeTitle)

        Transcript:
        \(effectiveText)
        """

        let tags: EpisodeTags = try await session.respond(to: prompt)
        logger.info("Tags generated successfully")
        return tags
    }

    // MARK: - Entity Extraction

    /// Extract named entities from episode transcript
    /// - Parameters:
    ///   - transcriptText: Full transcript text
    ///   - language: Language code
    /// - Returns: Structured entities (people, organizations, etc.)
    func extractEntities(
        from transcriptText: String,
        language: String = "en"
    ) async throws -> EpisodeEntities {
        logger.info("Extracting entities from transcript")

        let effectiveText = try await condenseIfNeeded(transcriptText, targetTokens: maxInputTokens, language: language)

        let prompt = """
        Extract all named entities from this podcast transcript.
        Include people, organizations, products, locations, and resources mentioned.

        Transcript:
        \(effectiveText)
        """

        let entities: EpisodeEntities = try await session.respond(to: prompt)
        logger.info("Entities extracted successfully")
        return entities
    }

    // MARK: - Highlights Generation

    /// Generate episode highlights and key moments
    /// - Parameters:
    ///   - transcriptText: Full transcript text
    ///   - episodeTitle: Title of the episode
    ///   - language: Language code
    /// - Returns: Structured highlights
    func generateHighlights(
        from transcriptText: String,
        episodeTitle: String,
        language: String = "en"
    ) async throws -> EpisodeHighlights {
        logger.info("Generating highlights for episode: \(episodeTitle)")

        let chunks = SRTParser.chunkText(transcriptText, maxTokens: maxInputTokens, language: language)

        if chunks.count == 1 {
            return try await generateHighlightsSingleChunk(transcriptText, episodeTitle: episodeTitle)
        } else {
            return try await generateHighlightsMultiChunk(chunks, episodeTitle: episodeTitle)
        }
    }

    private func generateHighlightsSingleChunk(_ text: String, episodeTitle: String) async throws -> EpisodeHighlights {
        let prompt = """
        Identify the most interesting highlights and key moments from this podcast episode.

        Episode: \(episodeTitle)

        Transcript:
        \(text)
        """

        return try await session.respond(to: prompt)
    }

    private func generateHighlightsMultiChunk(_ chunks: [String], episodeTitle: String) async throws -> EpisodeHighlights {
        // Extract highlights from each chunk, then combine
        var allHighlights: [String] = []
        var quotes: [String] = []

        for (index, chunk) in chunks.enumerated() {
            let prompt = """
            From this section (part \(index + 1)) of "\(episodeTitle)", extract:
            - 1-2 key highlights or interesting moments
            - Any memorable quotes

            Transcript section:
            \(chunk)
            """

            let response = try await session.respond(to: prompt)
            allHighlights.append(response)
        }

        // Combine and distill
        let combined = allHighlights.joined(separator: "\n")
        let finalPrompt = """
        Based on these highlights from different parts of "\(episodeTitle)", select the overall best moments:

        \(combined)
        """

        return try await session.respond(to: finalPrompt)
    }

    // MARK: - Content Analysis

    /// Analyze episode content structure and style
    /// - Parameters:
    ///   - transcriptText: Full transcript text
    ///   - language: Language code
    /// - Returns: Structured content analysis
    func analyzeContent(
        from transcriptText: String,
        language: String = "en"
    ) async throws -> EpisodeContentAnalysis {
        logger.info("Analyzing episode content structure")

        let effectiveText = try await condenseIfNeeded(transcriptText, targetTokens: maxInputTokens, language: language)

        let prompt = """
        Analyze the speaking style, tone, complexity, and structure of this podcast episode.

        Transcript:
        \(effectiveText)
        """

        let analysis: EpisodeContentAnalysis = try await session.respond(to: prompt)
        logger.info("Content analysis completed")
        return analysis
    }

    // MARK: - Question Answering

    /// Answer a specific question about the episode
    /// - Parameters:
    ///   - question: User's question
    ///   - transcriptText: Full transcript text
    ///   - episodeTitle: Title of the episode
    ///   - language: Language code
    /// - Returns: Structured answer with confidence and timestamp
    func answerQuestion(
        _ question: String,
        from transcriptText: String,
        episodeTitle: String,
        language: String = "en"
    ) async throws -> EpisodeAnswer {
        logger.info("Answering question: \(question)")

        let chunks = SRTParser.chunkText(transcriptText, maxTokens: maxInputTokens, language: language)

        if chunks.count == 1 {
            return try await answerQuestionSingleChunk(question, text: transcriptText, episodeTitle: episodeTitle)
        } else {
            return try await answerQuestionMultiChunk(question, chunks: chunks, episodeTitle: episodeTitle)
        }
    }

    private func answerQuestionSingleChunk(_ question: String, text: String, episodeTitle: String) async throws -> EpisodeAnswer {
        let prompt = """
        Answer this question based on the podcast episode transcript.
        If the answer is not in the transcript, say so clearly.

        Episode: \(episodeTitle)
        Question: \(question)

        Transcript:
        \(text)
        """

        return try await session.respond(to: prompt)
    }

    private func answerQuestionMultiChunk(_ question: String, chunks: [String], episodeTitle: String) async throws -> EpisodeAnswer {
        // Search each chunk for relevant information
        var relevantChunks: [(index: Int, content: String)] = []

        for (index, chunk) in chunks.enumerated() {
            let searchPrompt = """
            Does this section of "\(episodeTitle)" contain information relevant to this question: "\(question)"?
            Answer with "yes" or "no" and briefly explain why.

            Transcript section:
            \(chunk)
            """

            let relevanceCheck = try await session.respond(to: searchPrompt)

            if relevanceCheck.lowercased().contains("yes") {
                relevantChunks.append((index, chunk))
            }
        }

        // If no relevant chunks found
        if relevantChunks.isEmpty {
            return EpisodeAnswer(
                answer: "The transcript does not appear to contain information relevant to this question.",
                timestamp: "N/A",
                confidence: "high",
                relatedTopics: []
            )
        }

        // Answer from relevant chunks
        let combinedRelevant = relevantChunks
            .map { "Part \($0.index + 1):\n\($0.content)" }
            .joined(separator: "\n\n")

        let answerPrompt = """
        Answer this question based on the relevant sections of "\(episodeTitle)".

        Question: \(question)

        Relevant sections:
        \(combinedRelevant)
        """

        let answer: EpisodeAnswer = try await session.respond(to: answerPrompt)
        logger.info("Question answered successfully")
        return answer
    }

    // MARK: - Multi-Episode Analysis

    /// Analyze and compare multiple episodes
    /// - Parameters:
    ///   - episodeData: Array of (title, transcript) tuples
    ///   - language: Language code
    /// - Returns: Comparative analysis across episodes
    func analyzeMultipleEpisodes(
        _ episodeData: [(title: String, transcript: String)],
        language: String = "en"
    ) async throws -> MultiEpisodeAnalysis {
        logger.info("Analyzing \(episodeData.count) episodes")

        // First, generate a summary for each episode
        var episodeSummaries: [String] = []

        for (title, transcript) in episodeData {
            let condensed = try await condenseIfNeeded(transcript, targetTokens: 1500, language: language)
            let summaryPrompt = """
            Briefly summarize the main topics and key points of this podcast episode.

            Episode: \(title)
            Transcript:
            \(condensed)
            """

            let summary = try await session.respond(to: summaryPrompt)
            episodeSummaries.append("Episode: \(title)\nSummary: \(summary)")
        }

        // Then analyze across episodes
        let combinedSummaries = episodeSummaries.joined(separator: "\n\n")
        let analysisPrompt = """
        Analyze these podcast episodes and identify:
        - Common themes across episodes
        - How topics evolved between episodes
        - Unique insights from each episode
        - Recommended listening order
        - Overall narrative connecting them

        \(combinedSummaries)
        """

        let analysis: MultiEpisodeAnalysis = try await session.respond(to: analysisPrompt)
        logger.info("Multi-episode analysis completed")
        return analysis
    }

    // MARK: - Helper Methods

    /// Condense text if it exceeds token limit by creating a summary
    private func condenseIfNeeded(_ text: String, targetTokens: Int, language: String) async throws -> String {
        let estimatedTokens = SRTParser.estimateTokenCount(for: text, language: language)

        if estimatedTokens <= targetTokens {
            return text
        }

        logger.info("Text too long (\(estimatedTokens) tokens), condensing to ~\(targetTokens) tokens")

        // Create chunks and summarize each
        let chunks = SRTParser.chunkText(text, maxTokens: targetTokens / 2, language: language)
        var condensedParts: [String] = []

        for chunk in chunks {
            let prompt = "Summarize the key information from this text:\n\(chunk)"
            let summary = try await session.respond(to: prompt)
            condensedParts.append(summary)
        }

        return condensedParts.joined(separator: "\n\n")
    }

    /// Stream response with progress updates (for future use)
    func generateSummaryWithProgress(
        from transcriptText: String,
        episodeTitle: String,
        language: String = "en"
    ) -> AsyncThrowingStream<(progress: Double, summary: EpisodeSummary?), Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    continuation.yield((progress: 0.1, summary: nil))

                    let summary = try await generateSummary(
                        from: transcriptText,
                        episodeTitle: episodeTitle,
                        language: language
                    )

                    continuation.yield((progress: 1.0, summary: summary))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Supporting Types

/// Availability status for Foundation Models
enum FoundationModelsAvailability: Equatable {
    case available
    case unavailable(reason: String)

    var isAvailable: Bool {
        if case .available = self {
            return true
        }
        return false
    }

    var message: String? {
        if case .unavailable(let reason) = self {
            return reason
        }
        return nil
    }
}
