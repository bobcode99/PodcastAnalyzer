//
//  EpisodeAnalysisModels.swift
//  PodcastAnalyzer
//
//  Created by Claude Code
//  @Generable models for Apple Foundation Models structured output
//

import Foundation
import FoundationModels

// MARK: - Episode Summary

/// Structured episode summary with key insights
@Generable
struct EpisodeSummary {
    @Guide(description: "Concise 2-3 sentence summary of the main topic and key points discussed in the episode")
    var summary: String

    @Guide(description: "List of 3-5 main topics or themes discussed, in order of importance")
    var mainTopics: [String]

    @Guide(description: "List of 3-5 key takeaways or insights from the episode")
    var keyTakeaways: [String]

    @Guide(description: "Target audience who would benefit most from this episode")
    var targetAudience: String

    @Guide(description: "Estimated engagement level: 'high', 'medium', or 'low' based on content quality and structure")
    var engagementLevel: String
}

// MARK: - Episode Tags & Categories

/// Structured tags and categorization for episode
@Generable
struct EpisodeTags {
    @Guide(description: "List of 5-10 relevant keywords or tags that describe the episode content")
    var tags: [String]

    @Guide(description: "Primary category (e.g., 'Technology', 'Business', 'Education', 'Health', 'Entertainment')")
    var primaryCategory: String

    @Guide(description: "List of 1-3 secondary categories")
    var secondaryCategories: [String]

    @Guide(description: "Difficulty level: 'beginner', 'intermediate', or 'advanced'")
    var difficultyLevel: String

    @Guide(description: "List of specific technical terms, jargon, or specialized vocabulary used")
    var technicalTerms: [String]
}

// MARK: - Episode Entities

/// Named entities extracted from episode
@Generable
struct EpisodeEntities {
    @Guide(description: "List of people mentioned by name in the episode")
    var people: [String]

    @Guide(description: "List of organizations, companies, or institutions mentioned")
    var organizations: [String]

    @Guide(description: "List of products, services, or technologies discussed")
    var products: [String]

    @Guide(description: "List of locations or places mentioned")
    var locations: [String]

    @Guide(description: "List of books, articles, studies, or other resources referenced")
    var resources: [String]
}

// MARK: - Question Answering

/// Answer to a specific question about the episode
@Generable
struct EpisodeAnswer {
    @Guide(description: "Direct answer to the user's question based on the episode content")
    var answer: String

    @Guide(description: "Approximate timestamp or time range where this information appears in the episode, if identifiable (e.g., '15:30-16:45' or 'beginning of episode')")
    var timestamp: String

    @Guide(description: "Confidence level in the answer: 'high', 'medium', or 'low'")
    var confidence: String

    @Guide(description: "List of related topics or segments in the episode that provide additional context")
    var relatedTopics: [String]
}

// MARK: - Multi-Episode Analysis

/// Comparative analysis across multiple episodes
@Generable
struct MultiEpisodeAnalysis {
    @Guide(description: "Common themes or topics that appear across the provided episodes")
    var commonThemes: [String]

    @Guide(description: "How the topics or perspectives evolved across episodes")
    var evolution: String

    @Guide(description: "Unique insights or topics specific to individual episodes")
    var uniqueInsights: [String]

    @Guide(description: "Recommended order or sequence for listening to these episodes")
    var recommendedOrder: [String]

    @Guide(description: "Overall narrative or storyline connecting these episodes")
    var narrative: String
}

// MARK: - Episode Highlights

/// Key moments and highlights from the episode
@Generable
struct EpisodeHighlights {
    @Guide(description: "List of 3-5 most interesting or impactful moments in the episode")
    var highlights: [String]

    @Guide(description: "Most memorable quote or statement from the episode")
    var bestQuote: String

    @Guide(description: "Funniest or most entertaining moment, if any")
    var entertainingMoment: String?

    @Guide(description: "Most controversial or debatable point discussed")
    var controversialPoint: String?

    @Guide(description: "Action items or practical advice provided in the episode")
    var actionItems: [String]
}

// MARK: - Content Analysis

/// Detailed content analysis for episode
@Generable
struct EpisodeContentAnalysis {
    @Guide(description: "Primary speaking style: 'conversational', 'educational', 'interview', 'storytelling', etc.")
    var speakingStyle: String

    @Guide(description: "Overall tone: 'informative', 'persuasive', 'entertaining', 'inspirational', etc.")
    var tone: String

    @Guide(description: "Complexity score from 1-10, where 1 is simple and 10 is highly complex")
    var complexityScore: Int

    @Guide(description: "Estimated percentage of time spent on each main topic")
    var topicDistribution: [String: Int]

    @Guide(description: "Whether the episode has a clear structure: 'well-structured', 'moderately-structured', 'free-flowing'")
    var structure: String
}

// MARK: - Supporting Types

/// Represents the state of AI analysis
enum AnalysisState: Equatable {
    case idle
    case analyzing(progress: Double)
    case completed
    case error(String)
}

/// Type of analysis to perform
enum AnalysisType {
    case summary
    case tags
    case entities
    case highlights
    case contentAnalysis
    case question(String)
    case multiEpisode([String]) // Episode titles
}

/// Result container for any analysis
struct EpisodeAnalysisResult {
    let type: AnalysisType
    let timestamp: Date

    // Optional results based on type
    var summary: EpisodeSummary?
    var tags: EpisodeTags?
    var entities: EpisodeEntities?
    var highlights: EpisodeHighlights?
    var contentAnalysis: EpisodeContentAnalysis?
    var answer: EpisodeAnswer?
    var multiEpisodeAnalysis: MultiEpisodeAnalysis?
}
