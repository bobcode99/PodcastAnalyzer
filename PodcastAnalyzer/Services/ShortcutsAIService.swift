//
//  ShortcutsAIService.swift
//  PodcastAnalyzer
//
//  Service for invoking Apple Shortcuts for AI analysis
//  Runs shortcuts directly with x-callback-url and gets results back
//

import Combine
import Foundation
import UIKit
import os.log

private let logger = Logger(subsystem: "com.podcastanalyzer", category: "ShortcutsAIService")

// MARK: - Shortcuts AI Service

@MainActor
class ShortcutsAIService: ObservableObject {
    static let shared = ShortcutsAIService()

    @Published var isProcessing = false
    @Published var lastResult: String?
    @Published var lastError: String?
    @Published var shortcutName: String {
        didSet {
            UserDefaults.standard.set(shortcutName, forKey: "shortcuts_ai_name")
        }
    }

    // Continuation for async/await support
    private var pendingContinuation: CheckedContinuation<String, Error>?
    private var timeoutTask: Task<Void, Never>?

    // Default shortcut name
    static let defaultShortcutName = "Podcast AI Analysis"

    private init() {
        self.shortcutName = UserDefaults.standard.string(forKey: "shortcuts_ai_name")
            ?? Self.defaultShortcutName
        setupNotificationObserver()
    }

    // MARK: - Setup

    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            forName: .shortcutsAnalysisCompleted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let result = notification.userInfo?["result"] as? String else { return }
            Task { @MainActor [self] in
                self.handleResult(result)
            }
        }
    }

    // MARK: - URL Callback Handling

    /// Call this from SceneDelegate/AppDelegate when receiving a URL
    func handleURL(_ url: URL) {
        logger.info("Received callback URL: \(url.absoluteString)")

        guard url.scheme == "podcastanalyzer" else { return }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }

        if url.host == "shortcut-result" {
            // Parse result from URL
            if let resultItem = components.queryItems?.first(where: { $0.name == "result" }),
               let result = resultItem.value?.removingPercentEncoding {
                handleResult(result)
            } else if let outputItem = components.queryItems?.first(where: { $0.name == "output" }),
                      let result = outputItem.value?.removingPercentEncoding {
                handleResult(result)
            }
        } else if url.host == "shortcut-error" {
            if let errorItem = components.queryItems?.first(where: { $0.name == "error" }),
               let error = errorItem.value?.removingPercentEncoding {
                handleError(error)
            }
        } else if url.host == "x-callback-url" {
            // Handle x-callback-url format
            handleXCallbackURL(url)
        }
    }

    private func handleXCallbackURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }

        // The path indicates success, error, or cancel
        switch url.path {
        case "/success":
            if let output = components.queryItems?.first(where: { $0.name == "result" || $0.name == "output" })?.value?.removingPercentEncoding {
                handleResult(output)
            } else {
                // Try to get from clipboard as fallback
                if let clipboardContent = UIPasteboard.general.string {
                    handleResult(clipboardContent)
                }
            }
        case "/error":
            let errorMsg = components.queryItems?.first(where: { $0.name == "errorMessage" })?.value?.removingPercentEncoding ?? "Shortcut failed"
            handleError(errorMsg)
        case "/cancel":
            handleError("Shortcut was cancelled")
        default:
            // Try clipboard fallback
            if let clipboardContent = UIPasteboard.general.string {
                handleResult(clipboardContent)
            }
        }
    }

    private func handleResult(_ result: String) {
        logger.info("Received shortcut result: \(result.prefix(100))...")
        isProcessing = false
        lastResult = result
        lastError = nil
        timeoutTask?.cancel()
        pendingContinuation?.resume(returning: result)
        pendingContinuation = nil
    }

    private func handleError(_ error: String) {
        logger.error("Shortcut error: \(error)")
        isProcessing = false
        lastError = error
        timeoutTask?.cancel()
        pendingContinuation?.resume(throwing: ShortcutsError.shortcutFailed(error))
        pendingContinuation = nil
    }

    // MARK: - Run Shortcut Directly

    /// Runs the configured shortcut with input and waits for result
    func runShortcut(
        input: String,
        timeout: TimeInterval = 120
    ) async throws -> String {
        isProcessing = true
        lastError = nil

        // For long input, use clipboard
        let useClipboard = input.count > 2000

        if useClipboard {
            UIPasteboard.general.string = input
        }

        // Build URL with x-callback-url
        let encodedName = shortcutName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? shortcutName
        let successURL = "podcastanalyzer://x-callback-url/success"
        let errorURL = "podcastanalyzer://x-callback-url/error"
        let cancelURL = "podcastanalyzer://x-callback-url/cancel"

        var urlString: String
        if useClipboard {
            // Shortcut should use "Get Clipboard" action
            urlString = "shortcuts://x-callback-url/run-shortcut?name=\(encodedName)"
            urlString += "&x-success=\(successURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? successURL)"
            urlString += "&x-error=\(errorURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? errorURL)"
            urlString += "&x-cancel=\(cancelURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cancelURL)"
        } else {
            let encodedInput = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            urlString = "shortcuts://x-callback-url/run-shortcut?name=\(encodedName)&input=text&text=\(encodedInput)"
            urlString += "&x-success=\(successURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? successURL)"
            urlString += "&x-error=\(errorURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? errorURL)"
            urlString += "&x-cancel=\(cancelURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cancelURL)"
        }

        guard let url = URL(string: urlString) else {
            throw ShortcutsError.invalidURL
        }

        logger.info("Running shortcut: \(self.shortcutName)")

        // Use withCheckedThrowingContinuation for async/await
        return try await withCheckedThrowingContinuation { continuation in
            self.pendingContinuation = continuation

            // Set timeout
            self.timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if self.pendingContinuation != nil {
                    self.isProcessing = false
                    self.pendingContinuation?.resume(throwing: ShortcutsError.timeout)
                    self.pendingContinuation = nil
                }
            }

            // Open the shortcut URL
            UIApplication.shared.open(url) { success in
                if !success {
                    self.isProcessing = false
                    self.timeoutTask?.cancel()
                    self.pendingContinuation?.resume(throwing: ShortcutsError.failedToOpen)
                    self.pendingContinuation = nil
                }
            }
        }
    }

    // MARK: - Analyze Transcript

    /// Analyze transcript using Shortcuts with Apple Intelligence
    func analyzeTranscript(
        transcript: String,
        episodeTitle: String,
        podcastTitle: String,
        analysisType: CloudAnalysisType,
        timeout: TimeInterval = 180
    ) async throws -> CloudAnalysisResult {
        let prompt = buildPrompt(
            transcript: transcript,
            episodeTitle: episodeTitle,
            podcastTitle: podcastTitle,
            analysisType: analysisType
        )

        let result = try await runShortcut(input: prompt, timeout: timeout)

        return CloudAnalysisResult(
            type: analysisType,
            content: result,
            parsedSummary: nil,
            parsedEntities: nil,
            parsedHighlights: nil,
            parsedFullAnalysis: nil,
            provider: .applePCC,
            model: "Apple Intelligence (via Shortcuts)",
            timestamp: Date()
        )
    }

    // MARK: - Build Prompts

    private func buildPrompt(
        transcript: String,
        episodeTitle: String,
        podcastTitle: String,
        analysisType: CloudAnalysisType
    ) -> String {
        let settings = AISettingsManager.shared
        let languageInstruction = settings.analysisLanguage.getLanguageInstruction()

        switch analysisType {
        case .summary:
            return """
            Please provide a comprehensive summary of this podcast episode.

            Podcast: \(podcastTitle)
            Episode: \(episodeTitle)

            \(languageInstruction)

            Transcript:
            \(transcript)

            Provide:
            1. A 2-3 paragraph summary
            2. Main topics discussed (bullet points)
            3. Key takeaways (bullet points)
            4. Who would benefit from this episode
            """

        case .entities:
            return """
            Please extract all named entities from this podcast episode.

            Podcast: \(podcastTitle)
            Episode: \(episodeTitle)

            \(languageInstruction)

            Transcript:
            \(transcript)

            List:
            1. People mentioned (names, roles if known)
            2. Organizations or companies
            3. Products or services
            4. Locations
            5. Books, articles, or resources mentioned
            """

        case .highlights:
            return """
            Please identify the key highlights from this podcast episode.

            Podcast: \(podcastTitle)
            Episode: \(episodeTitle)

            \(languageInstruction)

            Transcript:
            \(transcript)

            Provide:
            1. Top 5 highlights or key moments
            2. The best quote from the episode
            3. Any action items mentioned
            4. Interesting or surprising facts
            """

        case .fullAnalysis:
            return """
            Please provide a complete analysis of this podcast episode.

            Podcast: \(podcastTitle)
            Episode: \(episodeTitle)

            \(languageInstruction)

            Transcript:
            \(transcript)

            Provide:
            1. Executive Summary (2-3 paragraphs)
            2. Main Topics Discussed
            3. Key Insights and Learnings
            4. Notable Quotes
            5. Actionable Advice
            6. People and Organizations Mentioned
            7. Conclusion
            """
        }
    }

    // MARK: - Helpers

    func openShortcutsApp() {
        if let url = URL(string: "shortcuts://") {
            UIApplication.shared.open(url)
        }
    }

    func createShortcutURL() -> URL? {
        // Deep link to create a new shortcut
        URL(string: "shortcuts://create-shortcut")
    }

    /// Check if Shortcuts app is available
    var isShortcutsAvailable: Bool {
        guard let url = URL(string: "shortcuts://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
}

// MARK: - Shortcuts Errors

enum ShortcutsError: LocalizedError {
    case shortcutNotFound(name: String)
    case failedToOpen
    case noResult
    case timeout
    case cancelled
    case invalidURL
    case shortcutFailed(String)

    var errorDescription: String? {
        switch self {
        case .shortcutNotFound(let name):
            return "Shortcut '\(name)' not found. Please create it in the Shortcuts app."
        case .failedToOpen:
            return "Failed to open Shortcuts app. Please make sure it's installed."
        case .noResult:
            return "No result received from the shortcut."
        case .timeout:
            return "Shortcut took too long to respond. Please try again."
        case .cancelled:
            return "Shortcut was cancelled."
        case .invalidURL:
            return "Invalid shortcut URL."
        case .shortcutFailed(let message):
            return "Shortcut failed: \(message)"
        }
    }
}

// Note: Notification.Name extensions are defined in PodcastAppIntents.swift
