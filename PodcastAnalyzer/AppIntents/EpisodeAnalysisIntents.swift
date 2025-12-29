//
//  EpisodeAnalysisIntents.swift
//  PodcastAnalyzer
//
//  App Intents for background AI analysis without app switching
//

import AppIntents
import Foundation

// MARK: - Analysis Type Enum

@available(iOS 16.0, *)
enum AnalysisTypeEnum: String, AppEnum {
    case summary = "summary"
    case tags = "tags"
    case entities = "entities"
    case highlights = "highlights"
    case question = "question"

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Analysis Type")

    static var caseDisplayRepresentations: [AnalysisTypeEnum: DisplayRepresentation] = [
        .summary: "Summary",
        .tags: "Tags & Categories",
        .entities: "Named Entities",
        .highlights: "Key Highlights",
        .question: "Answer Question"
    ]
}

// MARK: - Analyze Episode Intent

@available(iOS 16.0, *)
struct AnalyzeEpisodeIntent: AppIntent {
    static var title: LocalizedStringResource = "Analyze Episode"
    static var description: IntentDescription = IntentDescription("Analyzes podcast episode transcript using Apple Intelligence")

    // ✅ This prevents Shortcuts from opening!
    static var openAppWhenRun: Bool = false

    // Parameters
    @Parameter(title: "Episode Title")
    var episodeTitle: String

    @Parameter(title: "Transcript Text")
    var transcriptText: String

    @Parameter(title: "Analysis Type", default: .summary)
    var analysisType: AnalysisTypeEnum

    @Parameter(title: "Question (for Q&A only)", default: "")
    var question: String?

    @Parameter(title: "Language", default: "en")
    var language: String

    // Perform analysis
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard #available(iOS 26.0, *) else {
            throw AnalysisError.requiresiOS26
        }

        let service = EpisodeAnalysisService()

        // Check availability
        let availability = await service.checkAvailability()
        guard availability.isAvailable else {
            throw AnalysisError.aiUnavailable(availability.message ?? "AI not available")
        }

        let plainText = SRTParser.extractPlainText(from: transcriptText)

        switch analysisType {
        case .summary:
            let summary = try await service.generateSummary(
                from: plainText,
                episodeTitle: episodeTitle,
                language: language
            )

            let result = formatSummary(summary)
            return .result(
                value: result,
                dialog: "Here's the episode summary: \(summary.summary)"
            )

        case .tags:
            let tags = try await service.generateTags(
                from: plainText,
                episodeTitle: episodeTitle,
                language: language
            )

            let result = formatTags(tags)
            return .result(
                value: result,
                dialog: "Found \(tags.tags.count) tags"
            )

        case .entities:
            let entities = try await service.extractEntities(
                from: plainText,
                language: language
            )

            let result = formatEntities(entities)
            return .result(
                value: result,
                dialog: "Extracted entities from the episode"
            )

        case .highlights:
            let highlights = try await service.generateHighlights(
                from: plainText,
                episodeTitle: episodeTitle,
                language: language
            )

            let result = formatHighlights(highlights)
            return .result(
                value: result,
                dialog: "Here are the key highlights"
            )

        case .question:
            guard let question = question, !question.isEmpty else {
                throw AnalysisError.missingQuestion
            }

            let answer = try await service.answerQuestion(
                question,
                from: plainText,
                episodeTitle: episodeTitle,
                language: language
            )

            return .result(
                value: answer.answer,
                dialog: "The answer is: \(answer.answer)"
            )
        }
    }

    // MARK: - Formatters

    private func formatSummary(_ summary: EpisodeSummary) -> String {
        var result = "📝 Summary:\n\(summary.summary)\n\n"
        result += "📌 Main Topics:\n"
        for topic in summary.mainTopics {
            result += "• \(topic)\n"
        }
        result += "\n💡 Key Takeaways:\n"
        for takeaway in summary.keyTakeaways {
            result += "• \(takeaway)\n"
        }
        result += "\n🎯 Target Audience: \(summary.targetAudience)"
        return result
    }

    private func formatTags(_ tags: EpisodeTags) -> String {
        var result = "🏷️ Tags:\n"
        result += tags.tags.map { "#\($0)" }.joined(separator: ", ")
        result += "\n\n📂 Category: \(tags.primaryCategory)"
        result += "\n📊 Difficulty: \(tags.difficultyLevel)"
        return result
    }

    private func formatEntities(_ entities: EpisodeEntities) -> String {
        var result = ""

        if !entities.people.isEmpty {
            result += "👥 People:\n"
            for person in entities.people {
                result += "• \(person)\n"
            }
        }

        if !entities.organizations.isEmpty {
            result += "\n🏢 Organizations:\n"
            for org in entities.organizations {
                result += "• \(org)\n"
            }
        }

        if !entities.products.isEmpty {
            result += "\n📦 Products:\n"
            for product in entities.products {
                result += "• \(product)\n"
            }
        }

        return result
    }

    private func formatHighlights(_ highlights: EpisodeHighlights) -> String {
        var result = "✨ Key Highlights:\n"
        for (index, highlight) in highlights.highlights.enumerated() {
            result += "\(index + 1). \(highlight)\n"
        }
        result += "\n💬 Best Quote:\n\"\(highlights.bestQuote)\""
        return result
    }
}

// MARK: - Get Transcript Intent

@available(iOS 16.0, *)
struct GetTranscriptIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Episode Transcript"
    static var description: IntentDescription = IntentDescription("Retrieves the transcript for a podcast episode")

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Episode Title")
    var episodeTitle: String

    @Parameter(title: "Podcast Title")
    var podcastTitle: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let fileStorage = FileStorageManager.shared

        // Try to load existing transcript
        do {
            let content = try await fileStorage.loadCaptionFile(
                for: episodeTitle,
                podcastTitle: podcastTitle
            )

            let plainText = SRTParser.extractPlainText(from: content)

            return .result(
                value: plainText,
                dialog: "Found transcript with \(plainText.count) characters"
            )
        } catch {
            throw AnalysisError.transcriptNotFound
        }
    }
}

// MARK: - App Shortcuts Provider

@available(iOS 16.0, *)
struct EpisodeAnalysisShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AnalyzeEpisodeIntent(),
            phrases: [
                "Analyze episode in \(.applicationName)",
                "Get episode summary in \(.applicationName)",
                "What are the main points in \(.applicationName)"
            ],
            shortTitle: "Analyze Episode",
            systemImageName: "sparkles"
        )

        AppShortcut(
            intent: GetTranscriptIntent(),
            phrases: [
                "Get transcript in \(.applicationName)",
                "Show episode transcript in \(.applicationName)"
            ],
            shortTitle: "Get Transcript",
            systemImageName: "doc.text"
        )
    }
}

// MARK: - Errors

enum AnalysisError: LocalizedError {
    case requiresiOS26
    case aiUnavailable(String)
    case transcriptNotFound
    case missingQuestion

    var errorDescription: String? {
        switch self {
        case .requiresiOS26:
            return "This feature requires iOS 26 or later"
        case .aiUnavailable(let message):
            return "AI analysis unavailable: \(message)"
        case .transcriptNotFound:
            return "Transcript not found. Please generate it first."
        case .missingQuestion:
            return "Question is required for Q&A analysis"
        }
    }
}
