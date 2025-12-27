//
//  EpisodeAnalysisService.swift
//  PodcastAnalyzer
//
//  Service for on-device AI quick tags using Apple Foundation Models
//  NOTE: This service is ONLY for lightweight tag generation from episode metadata
//  For full transcript analysis, use CloudAIService with user-provided API keys
//

import Foundation
import FoundationModels
import os.log

private nonisolated let logger = Logger(subsystem: "com.podcastanalyzer", category: "EpisodeAnalysisService")

/// Service for generating quick tags from episode metadata using Apple Foundation Models (iOS 26+)
/// Uses only episode title, description, duration, and release date - NOT the full transcript
/// This keeps requests well within the 4096 token context limit
@available(iOS 26.0, macOS 26.0, *)
actor EpisodeAnalysisService {

    // MARK: - Properties

    private let session: LanguageModelSession

    // MARK: - Initialization

    init() {
        self.session = LanguageModelSession(instructions: """
            You are a podcast categorization assistant. Your role is to generate relevant tags and categories
            based on episode metadata (title, description, duration, release date).

            Be concise and accurate. Generate tags that help users discover and organize episodes.
            Focus on topics, themes, genres, and content types.
            """)
    }

    // MARK: - Availability Checking

    /// Check if Foundation Models are available on this device
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

    // MARK: - Quick Tag Generation (On-Device)

    /// Generate quick tags from episode metadata (NOT the transcript)
    /// This is lightweight and fits within the on-device context limit
    /// - Parameters:
    ///   - title: Episode title
    ///   - description: Episode description (will be truncated if too long)
    ///   - podcastTitle: Name of the podcast
    ///   - duration: Episode duration in seconds (optional)
    ///   - releaseDate: Episode release date (optional)
    ///   - progressCallback: Optional callback for progress updates
    /// - Returns: Quick tags and categories
    func generateQuickTags(
        title: String,
        description: String,
        podcastTitle: String,
        duration: TimeInterval? = nil,
        releaseDate: Date? = nil,
        progressCallback: ((String, Double) -> Void)? = nil
    ) async throws -> EpisodeQuickTags {
        logger.info("Generating quick tags for: \(title)")

        progressCallback?("Preparing metadata...", 0.2)

        // Truncate description to ~500 chars to stay well within limits
        let truncatedDescription = description.count > 500
            ? String(description.prefix(500)) + "..."
            : description

        // Format duration
        let durationString: String
        if let duration = duration {
            let minutes = Int(duration) / 60
            durationString = "\(minutes) minutes"
        } else {
            durationString = "unknown duration"
        }

        // Format release date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        let releaseDateString = releaseDate.map { dateFormatter.string(from: $0) } ?? "unknown date"

        progressCallback?("Generating tags...", 0.5)

        let prompt = """
        Generate tags and categories for this podcast episode:

        Podcast: \(podcastTitle)
        Episode: \(title)
        Duration: \(durationString)
        Released: \(releaseDateString)

        Description:
        \(truncatedDescription)
        """

        let response = try await session.respond(to: prompt, generating: EpisodeQuickTags.self)

        progressCallback?("Done", 1.0)
        logger.info("Quick tags generated successfully")

        return response.content
    }

    /// Generate a brief one-line summary from episode metadata
    /// - Parameters:
    ///   - title: Episode title
    ///   - description: Episode description
    ///   - progressCallback: Optional callback for progress updates
    /// - Returns: Brief one-line summary
    func generateBriefSummary(
        title: String,
        description: String,
        progressCallback: ((String, Double) -> Void)? = nil
    ) async throws -> String {
        logger.info("Generating brief summary for: \(title)")

        progressCallback?("Creating summary...", 0.3)

        // Truncate description to ~800 chars
        let truncatedDescription = description.count > 800
            ? String(description.prefix(800)) + "..."
            : description

        let prompt = """
        Write a single sentence (max 100 words) summarizing this podcast episode based on its title and description:

        Title: \(title)
        Description: \(truncatedDescription)

        Respond with ONLY the summary sentence, nothing else.
        """

        let response = try await session.respond(to: prompt)

        progressCallback?("Done", 1.0)
        logger.info("Brief summary generated successfully")

        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
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
