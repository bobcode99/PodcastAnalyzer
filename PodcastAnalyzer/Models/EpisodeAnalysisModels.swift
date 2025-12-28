//
//  EpisodeAnalysisModels.swift
//  PodcastAnalyzer
//
//  Models for AI-powered episode analysis
//  - On-device (Apple Foundation Models): Quick tags from metadata only
//  - Cloud (BYOK): Full transcript analysis via user-provided API keys
//

import Foundation
import FoundationModels

// MARK: - On-Device Models (Quick Tags from Metadata)

/// Quick tags generated from episode metadata (title, description, duration)
/// Used by on-device Foundation Models - lightweight operation within 4096 token limit
@Generable
struct EpisodeQuickTags {
    @Guide(description: "List of 5-8 relevant keywords or tags based on the episode title and description")
    var tags: [String]

    @Guide(description: "Primary category: 'Technology', 'Business', 'Education', 'Health', 'Entertainment', 'News', 'Sports', 'Science', 'Arts', 'Society'")
    var primaryCategory: String

    @Guide(description: "One secondary category if applicable")
    var secondaryCategory: String?

    @Guide(description: "Content type: 'interview', 'solo', 'panel', 'documentary', 'tutorial', 'news', 'storytelling'")
    var contentType: String

    @Guide(description: "Estimated difficulty: 'beginner', 'intermediate', 'advanced'")
    var difficulty: String
}

// MARK: - Analysis State

/// Represents the state of AI analysis (works for both on-device and cloud)
enum AnalysisState: Equatable {
    case idle
    case analyzing(progress: Double, message: String)
    case completed
    case error(String)

    /// Convenience initializer
    static func analyzing(progress: Double) -> AnalysisState {
        .analyzing(progress: progress, message: "Analyzing...")
    }

    /// Get the progress value if in analyzing state
    var progress: Double? {
        if case .analyzing(let progress, _) = self {
            return progress
        }
        return nil
    }

    /// Get the message if in analyzing state
    var analysisMessage: String? {
        if case .analyzing(_, let message) = self {
            return message
        }
        return nil
    }

    /// Check if currently analyzing
    var isAnalyzing: Bool {
        if case .analyzing = self {
            return true
        }
        return false
    }
}

// MARK: - Cloud Analysis Tab Selection

/// Tabs available for cloud-based transcript analysis
enum CloudAnalysisTab: String, CaseIterable, Identifiable {
    case summary = "Summary"
    case entities = "Entities"
    case highlights = "Highlights"
    case fullAnalysis = "Full Analysis"
    case askQuestion = "Ask"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .summary: return "doc.text"
        case .entities: return "person.2"
        case .highlights: return "star"
        case .fullAnalysis: return "sparkles"
        case .askQuestion: return "questionmark.bubble"
        }
    }

    var description: String {
        switch self {
        case .summary: return "Episode summary with key topics and takeaways"
        case .entities: return "People, organizations, and products mentioned"
        case .highlights: return "Key moments and notable quotes"
        case .fullAnalysis: return "Comprehensive analysis of the entire episode"
        case .askQuestion: return "Ask questions about the episode content"
        }
    }

    /// Convert to CloudAnalysisType for the service
    var analysisType: CloudAnalysisType? {
        switch self {
        case .summary: return .summary
        case .entities: return .entities
        case .highlights: return .highlights
        case .fullAnalysis: return .fullAnalysis
        case .askQuestion: return nil // Q&A is handled separately
        }
    }
}

// MARK: - Cached Analysis Results

/// Container for cached cloud analysis results
struct CachedCloudAnalysis {
    var summary: CloudAnalysisResult?
    var entities: CloudAnalysisResult?
    var highlights: CloudAnalysisResult?
    var fullAnalysis: CloudAnalysisResult?
    var questionAnswers: [CloudQAResult] = []

    /// Check if a specific analysis type has been completed
    func hasResult(for type: CloudAnalysisType) -> Bool {
        switch type {
        case .summary: return summary != nil
        case .entities: return entities != nil
        case .highlights: return highlights != nil
        case .fullAnalysis: return fullAnalysis != nil
        }
    }

    /// Get result for a specific type
    func result(for type: CloudAnalysisType) -> CloudAnalysisResult? {
        switch type {
        case .summary: return summary
        case .entities: return entities
        case .highlights: return highlights
        case .fullAnalysis: return fullAnalysis
        }
    }

    /// Clear all cached results
    mutating func clearAll() {
        summary = nil
        entities = nil
        highlights = nil
        fullAnalysis = nil
        questionAnswers = []
    }
}

// MARK: - Quick Tags Cache

/// Container for cached on-device quick tags
struct CachedQuickTags {
    var tags: EpisodeQuickTags?
    var briefSummary: String?
    var generatedAt: Date?

    var hasContent: Bool {
        tags != nil || briefSummary != nil
    }

    mutating func clear() {
        tags = nil
        briefSummary = nil
        generatedAt = nil
    }
}
