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
    var episodeAudioURL: String = ""
    var episodeTitle: String = ""
    var podcastTitle: String = ""

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
    var highlightsBestQuoteTimestamp: String?
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
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

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

    // Q&A history as CloudQAResult array
    var qaHistory: [CloudQAResult] {
        get {
            guard let json = qaHistoryJSON,
                  let data = json.data(using: .utf8),
                  let array = try? JSONDecoder().decode([QAEntry].self, from: data) else {
                return []
            }
            return array.map { $0.toCloudQAResult() }
        }
        set {
            let entries = newValue.map { QAEntry(from: $0) }
            if let data = try? JSONEncoder().encode(entries),
               let json = String(data: data, encoding: .utf8) {
                qaHistoryJSON = json
            }
        }
    }

    func addQA(_ result: CloudQAResult) {
        var history = qaHistory
        history.append(result)
        qaHistory = history
        updatedAt = Date()
    }
}

// Helper for Q&A serialization - includes all fields from CloudQAResult
// Marked as Sendable for Swift 6 concurrency safety
struct QAEntry: Codable, Sendable {
    let question: String
    let answer: String
    let confidence: String
    let relatedTopics: [String]?
    let sources: [String]?
    let providerRawValue: String
    let model: String
    let timestamp: Date
    let jsonParseWarning: String?

    nonisolated init(from result: CloudQAResult) {
        self.question = result.question
        self.answer = result.answer
        self.confidence = result.confidence
        self.relatedTopics = result.relatedTopics
        self.sources = result.sources
        self.providerRawValue = result.provider.rawValue
        self.model = result.model
        self.timestamp = result.timestamp
        self.jsonParseWarning = result.jsonParseWarning
    }

    /// Convert back to CloudQAResult - nonisolated for use from any context
    nonisolated func toCloudQAResult() -> CloudQAResult {
        let provider = CloudAIProvider(rawValue: providerRawValue) ?? .gemini
        return CloudQAResult(
            question: question,
            answer: answer,
            confidence: confidence,
            relatedTopics: relatedTopics,
            sources: sources,
            provider: provider,
            model: model,
            timestamp: timestamp,
            jsonParseWarning: jsonParseWarning
        )
    }

    // Legacy initializer for backward compatibility with old data
    init(question: String, answer: String, timestamp: Date) {
        self.question = question
        self.answer = answer
        self.confidence = "unknown"
        self.relatedTopics = nil
        self.sources = nil
        self.providerRawValue = CloudAIProvider.gemini.rawValue
        self.model = "Unknown"
        self.timestamp = timestamp
        self.jsonParseWarning = nil
    }
}

// MARK: - Episode Quick Tags (On-Device)

@Model
final class EpisodeQuickTagsModel {
    // Link to episode
    var episodeAudioURL: String = ""
    var episodeTitle: String = ""

    // Tags data
    var tags: [String] = []
    var primaryCategory: String = ""
    var secondaryCategory: String?
    var contentType: String = ""
    var difficulty: String = ""

    // Brief summary
    var briefSummary: String?

    // Timestamps
    var generatedAt: Date = Date()

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

// MARK: - Timestamped Quote

/// A quote with an optional timestamp for playback seeking
nonisolated struct TimestampedQuote: Codable, Sendable {
    let text: String
    let timestamp: String?

    var timeInSeconds: TimeInterval? {
        guard let ts = timestamp else { return nil }
        return TimestampUtils.parseToSeconds(ts)
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
    let bestQuote: TimestampedQuote
    let actionItems: [String]
    let controversialPoints: [String]?
    let entertainingMoments: [String]?

    /// Backward-compatible memberwise init (SwiftData restore uses plain String)
    init(
        highlights: [String],
        bestQuote: String,
        bestQuoteTimestamp: String? = nil,
        actionItems: [String],
        controversialPoints: [String]?,
        entertainingMoments: [String]?
    ) {
        self.highlights = highlights
        self.bestQuote = TimestampedQuote(text: bestQuote, timestamp: bestQuoteTimestamp)
        self.actionItems = actionItems
        self.controversialPoints = controversialPoints
        self.entertainingMoments = entertainingMoments
    }

    /// Decode from JSON — handles both object and plain string for bestQuote
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        highlights = try container.decode([String].self, forKey: .highlights)
        actionItems = try container.decode([String].self, forKey: .actionItems)
        controversialPoints = try container.decodeIfPresent([String].self, forKey: .controversialPoints)
        entertainingMoments = try container.decodeIfPresent([String].self, forKey: .entertainingMoments)

        // Try object first, fall back to plain string
        if let quote = try? container.decode(TimestampedQuote.self, forKey: .bestQuote) {
            bestQuote = quote
        } else if let text = try? container.decode(String.self, forKey: .bestQuote) {
            bestQuote = TimestampedQuote(text: text, timestamp: nil)
        } else {
            bestQuote = TimestampedQuote(text: "", timestamp: nil)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case highlights, bestQuote, actionItems, controversialPoints, entertainingMoments
    }
}

/// Parsed Q&A response from cloud AI
struct ParsedQAResponse: Codable {
    let answer: String
    let confidence: String
    let relatedTopics: [String]?
    let sources: [String]?
}

/// Parsed full analysis response from cloud AI
struct ParsedFullAnalysisResponse: Codable {
    let overview: String
    let mainTopics: [TopicDetail]
    let keyInsights: [String]
    let notableQuotes: [TimestampedQuote]
    let actionableAdvice: [String]?
    let conclusion: String

    struct TopicDetail: Codable {
        let topic: String
        let summary: String
        let keyPoints: [String]
    }

    /// Decode from JSON — handles both [TimestampedQuote] and [String] for notableQuotes
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        overview = try container.decode(String.self, forKey: .overview)
        mainTopics = try container.decode([TopicDetail].self, forKey: .mainTopics)
        keyInsights = try container.decode([String].self, forKey: .keyInsights)
        actionableAdvice = try container.decodeIfPresent([String].self, forKey: .actionableAdvice)
        conclusion = try container.decode(String.self, forKey: .conclusion)

        // Try [TimestampedQuote] first, fall back to [String]
        if let quotes = try? container.decode([TimestampedQuote].self, forKey: .notableQuotes) {
            notableQuotes = quotes
        } else if let strings = try? container.decode([String].self, forKey: .notableQuotes) {
            notableQuotes = strings.map { TimestampedQuote(text: $0, timestamp: nil) }
        } else {
            notableQuotes = []
        }
    }

    private enum CodingKeys: String, CodingKey {
        case overview, mainTopics, keyInsights, notableQuotes, actionableAdvice, conclusion
    }
}
