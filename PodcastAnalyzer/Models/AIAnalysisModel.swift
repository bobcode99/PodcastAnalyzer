//
//  AIAnalysisModel.swift
//  PodcastAnalyzer
//
//  SwiftData models for persisting AI analysis results
//

import Foundation
import SwiftData

// MARK: - Episode AI Analysis (Cloud)

@Model
final class EpisodeAIAnalysis {
    // Link to episode
    var episodeAudioURL: String
    var episodeTitle: String
    var podcastTitle: String

    // Summary analysis
    var summaryText: String?
    var summaryMainTopics: [String]?
    var summaryKeyTakeaways: [String]?
    var summaryTargetAudience: String?
    var summaryEngagementLevel: String?
    var summaryProvider: String?
    var summaryModel: String?
    var summaryGeneratedAt: Date?

    // Entities analysis
    var entitiesPeople: [String]?
    var entitiesOrganizations: [String]?
    var entitiesProducts: [String]?
    var entitiesLocations: [String]?
    var entitiesResources: [String]?
    var entitiesProvider: String?
    var entitiesModel: String?
    var entitiesGeneratedAt: Date?

    // Highlights analysis
    var highlightsList: [String]?
    var highlightsBestQuote: String?
    var highlightsActionItems: [String]?
    var highlightsControversialPoints: [String]?
    var highlightsEntertainingMoments: [String]?
    var highlightsProvider: String?
    var highlightsModel: String?
    var highlightsGeneratedAt: Date?

    // Full analysis (markdown/text)
    var fullAnalysisText: String?
    var fullAnalysisProvider: String?
    var fullAnalysisModel: String?
    var fullAnalysisGeneratedAt: Date?

    // Q&A history (stored as JSON)
    var qaHistoryJSON: String?

    // Timestamps
    var createdAt: Date
    var updatedAt: Date

    init(
        episodeAudioURL: String,
        episodeTitle: String,
        podcastTitle: String
    ) {
        self.episodeAudioURL = episodeAudioURL
        self.episodeTitle = episodeTitle
        self.podcastTitle = podcastTitle
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: - Convenience Methods

    var hasSummary: Bool { summaryText != nil }
    var hasEntities: Bool { entitiesPeople != nil || entitiesOrganizations != nil }
    var hasHighlights: Bool { highlightsList != nil }
    var hasFullAnalysis: Bool { fullAnalysisText != nil }

    // Q&A history as array
    var qaHistory: [(question: String, answer: String, timestamp: Date)] {
        get {
            guard let json = qaHistoryJSON,
                  let data = json.data(using: .utf8),
                  let array = try? JSONDecoder().decode([QAEntry].self, from: data) else {
                return []
            }
            return array.map { ($0.question, $0.answer, $0.timestamp) }
        }
        set {
            let entries = newValue.map { QAEntry(question: $0.question, answer: $0.answer, timestamp: $0.timestamp) }
            if let data = try? JSONEncoder().encode(entries),
               let json = String(data: data, encoding: .utf8) {
                qaHistoryJSON = json
            }
        }
    }

    func addQA(question: String, answer: String) {
        var history = qaHistory
        history.append((question: question, answer: answer, timestamp: Date()))
        qaHistory = history
        updatedAt = Date()
    }
}

// Helper for Q&A serialization
private struct QAEntry: Codable {
    let question: String
    let answer: String
    let timestamp: Date
}

// MARK: - Episode Quick Tags (On-Device)

@Model
final class EpisodeQuickTagsModel {
    // Link to episode
    var episodeAudioURL: String
    var episodeTitle: String

    // Tags data
    var tags: [String]
    var primaryCategory: String
    var secondaryCategory: String?
    var contentType: String
    var difficulty: String

    // Brief summary
    var briefSummary: String?

    // Timestamps
    var generatedAt: Date

    init(
        episodeAudioURL: String,
        episodeTitle: String,
        tags: [String],
        primaryCategory: String,
        secondaryCategory: String?,
        contentType: String,
        difficulty: String,
        briefSummary: String? = nil
    ) {
        self.episodeAudioURL = episodeAudioURL
        self.episodeTitle = episodeTitle
        self.tags = tags
        self.primaryCategory = primaryCategory
        self.secondaryCategory = secondaryCategory
        self.contentType = contentType
        self.difficulty = difficulty
        self.briefSummary = briefSummary
        self.generatedAt = Date()
    }
}

// MARK: - Parsed Response Types (for JSON parsing)

/// Parsed summary response from cloud AI
struct ParsedSummaryResponse: Codable {
    let summary: String
    let mainTopics: [String]
    let keyTakeaways: [String]
    let targetAudience: String
    let engagementLevel: String
}

/// Parsed entities response from cloud AI
struct ParsedEntitiesResponse: Codable {
    let people: [String]
    let organizations: [String]
    let products: [String]
    let locations: [String]
    let resources: [String]
}

/// Parsed highlights response from cloud AI
struct ParsedHighlightsResponse: Codable {
    let highlights: [String]
    let bestQuote: String
    let actionItems: [String]
    let controversialPoints: [String]?
    let entertainingMoments: [String]?
}

/// Parsed Q&A response from cloud AI
struct ParsedQAResponse: Codable {
    let answer: String
    let confidence: String
    let relatedTopics: [String]?
}

/// Parsed full analysis response from cloud AI
struct ParsedFullAnalysisResponse: Codable {
    let overview: String
    let mainTopics: [TopicDetail]
    let keyInsights: [String]
    let notableQuotes: [String]
    let actionableAdvice: [String]?
    let conclusion: String

    struct TopicDetail: Codable {
        let topic: String
        let summary: String
        let keyPoints: [String]
    }
}
