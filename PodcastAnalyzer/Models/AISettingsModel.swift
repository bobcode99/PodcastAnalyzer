//
//  AISettingsModel.swift
//  PodcastAnalyzer
//
//  Settings for AI providers (Cloud APIs with BYOK)
//

import Foundation
import SwiftUI

// MARK: - Analysis Language Setting

enum AnalysisLanguage: String, CaseIterable, Codable {
    case deviceLanguage = "Device Language"
    case english = "English"
    case matchPodcast = "Match Podcast"

    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .deviceLanguage: return "iphone"
        case .english: return "globe.americas"
        case .matchPodcast: return "waveform"
        }
    }

    var description: String {
        switch self {
        case .deviceLanguage: return "Use your device's language settings"
        case .english: return "Always respond in English"
        case .matchPodcast: return "Match the podcast's language"
        }
    }

    /// Returns the language instruction to include in AI prompts
    func getLanguageInstruction(podcastLanguage: String? = nil) -> String {
        switch self {
        case .deviceLanguage:
            let preferredLanguage = Locale.preferredLanguages.first ?? "en"
            let languageName = Locale.current.localizedString(forLanguageCode: preferredLanguage) ?? "English"
            return "IMPORTANT: Respond in \(languageName)."
        case .english:
            return "IMPORTANT: Respond in English."
        case .matchPodcast:
            if let podcastLang = podcastLanguage, !podcastLang.isEmpty {
                let languageName = Locale.current.localizedString(forLanguageCode: podcastLang) ?? podcastLang
                return "IMPORTANT: Respond in \(languageName) (the podcast's language)."
            }
            return "" // No instruction if podcast language unknown
        }
    }
}

// MARK: - Cloud AI Provider

enum CloudAIProvider: String, CaseIterable, Codable, Sendable {
    case applePCC = "Apple PCC"  // Apple Private Cloud Compute via Shortcuts
    case openai = "OpenAI"
    case claude = "Claude"
    case gemini = "Gemini"
    case groq = "Groq"
    case grok = "Grok"

    var displayName: String {
        switch self {
        case .applePCC: return "Apple Intelligence"
        default: return rawValue
        }
    }

    var iconName: String {
        switch self {
        case .applePCC: return "apple.intelligence"
        case .openai: return "brain.head.profile"
        case .claude: return "sparkles"
        case .gemini: return "diamond"
        case .groq: return "hare"          // Fast like a rabbit
        case .grok: return "bolt"
        }
    }

    var apiKeyURL: URL? {
        switch self {
        case .applePCC: return nil  // No API key needed
        case .openai: return URL(string: "https://platform.openai.com/api-keys")
        case .claude: return URL(string: "https://console.anthropic.com/settings/keys")
        case .gemini: return URL(string: "https://aistudio.google.com/app/apikey")
        case .groq: return URL(string: "https://console.groq.com/keys")
        case .grok: return URL(string: "https://console.x.ai/")
        }
    }

    var requiresAPIKey: Bool {
        self != .applePCC
    }

    var defaultModel: String {
        switch self {
        case .applePCC: return "Apple Intelligence"
        case .openai: return "gpt-4o-mini"
        case .claude: return "claude-sonnet-4-5-20250929"
        case .gemini: return "gemini-2.0-flash"
        case .groq: return "llama-3.3-70b-versatile"
        case .grok: return "grok-2-1212"
        }
    }

    var availableModels: [String] {
        switch self {
        // Apple Intelligence via Shortcuts
        case .applePCC: return ["Apple Intelligence"]
        // OpenAI models (Dec 2025)
        case .openai: return [
            "gpt-4o-mini",           // Fast, cheap
            "gpt-4o",                // Flagship multimodal
            "gpt-4.1-mini",          // Newer, better coding
            "gpt-4.1"                // Latest, 1M context
        ]
        // Claude models (Dec 2025) - Claude 3.x deprecated
        case .claude: return [
            "claude-sonnet-4-5-20250929",  // Best balance (recommended)
            "claude-haiku-4-5-20251015",   // Fast, cheap
            "claude-opus-4-5-20251101"     // Most capable
        ]
        // Gemini models (Dec 2025) - Gemini 1.5 DEPRECATED (returns 404!)
        case .gemini: return [
            "gemini-2.0-flash",      // Fast, free tier (recommended)
            "gemini-2.5-flash-lite", // Ultra fast, cheap
            "gemini-2.5-flash",      // Better quality
            "gemini-2.5-pro"         // Best quality
        ]
        // Groq models (Dec 2025) - Ultra fast inference, free tier!
        case .groq: return [
            "llama-3.3-70b-versatile",   // Best quality (recommended)
            "llama-3.1-8b-instant",      // Ultra fast, free tier
            "llama-3.2-90b-vision-preview", // Vision capable
            "mixtral-8x7b-32768",        // Good for long context
            "gemma2-9b-it"               // Google's Gemma on Groq
        ]
        // Grok models (Dec 2025)
        case .grok: return [
            "grok-2-1212",           // Stable, good quality
            "grok-3-mini",           // Faster
            "grok-3-beta",           // More capable
            "grok-4-fast-non-reasoning"  // Latest, 2M context
        ]
        }
    }

    var contextWindowSize: Int {
        switch self {
        case .applePCC: return 128_000  // Apple PCC via Shortcuts - large context
        case .openai: return 128_000
        case .claude: return 200_000
        case .gemini: return 1_000_000
        case .groq: return 128_000      // Varies by model
        case .grok: return 128_000
        }
    }

    var pricingNote: String {
        switch self {
        case .applePCC: return "Free! Uses Apple Intelligence via Shortcuts"
        case .openai: return "gpt-4o-mini: $0.15/1M input tokens"
        case .claude: return "Haiku: $0.25/1M input tokens"
        case .gemini: return "Flash: Free tier available!"
        case .groq: return "Free tier available! Ultra-fast inference"
        case .grok: return "grok-beta: $5/1M input tokens"
        }
    }

    /// Whether this provider uses Shortcuts for AI processing
    var usesShortcuts: Bool {
        self == .applePCC
    }
}

// MARK: - AI Settings Manager

@Observable
final class AISettingsManager {
    static let shared = AISettingsManager()

    // MARK: - Stored Properties

    var selectedProvider: CloudAIProvider {
        didSet { saveSettings() }
    }

    var openAIKey: String {
        didSet { saveToKeychain(key: openAIKey, for: .openai) }
    }

    var claudeKey: String {
        didSet { saveToKeychain(key: claudeKey, for: .claude) }
    }

    var geminiKey: String {
        didSet { saveToKeychain(key: geminiKey, for: .gemini) }
    }

    var grokKey: String {
        didSet { saveToKeychain(key: grokKey, for: .grok) }
    }

    var groqKey: String {
        didSet { saveToKeychain(key: groqKey, for: .groq) }
    }

    var selectedOpenAIModel: String {
        didSet { saveSettings() }
    }

    var selectedClaudeModel: String {
        didSet { saveSettings() }
    }

    var selectedGeminiModel: String {
        didSet { saveSettings() }
    }

    var selectedGrokModel: String {
        didSet { saveSettings() }
    }

    var selectedGroqModel: String {
        didSet { saveSettings() }
    }

    var analysisLanguage: AnalysisLanguage {
        didSet { saveSettings() }
    }

    // MARK: - Initialization

    private init() {
        // Load provider selection
        if let providerString = UserDefaults.standard.string(forKey: "ai_selected_provider"),
           let provider = CloudAIProvider(rawValue: providerString) {
            self.selectedProvider = provider
        } else {
            self.selectedProvider = .gemini // Default to Gemini (has free tier)
        }

        // Load model selections
        self.selectedOpenAIModel = UserDefaults.standard.string(forKey: "ai_openai_model") ?? CloudAIProvider.openai.defaultModel
        self.selectedClaudeModel = UserDefaults.standard.string(forKey: "ai_claude_model") ?? CloudAIProvider.claude.defaultModel
        self.selectedGeminiModel = UserDefaults.standard.string(forKey: "ai_gemini_model") ?? CloudAIProvider.gemini.defaultModel
        self.selectedGrokModel = UserDefaults.standard.string(forKey: "ai_grok_model") ?? CloudAIProvider.grok.defaultModel
        self.selectedGroqModel = UserDefaults.standard.string(forKey: "ai_groq_model") ?? CloudAIProvider.groq.defaultModel

        // Load analysis language setting
        if let languageString = UserDefaults.standard.string(forKey: "ai_analysis_language"),
           let language = AnalysisLanguage(rawValue: languageString) {
            self.analysisLanguage = language
        } else {
            self.analysisLanguage = .deviceLanguage // Default
        }

        // Load API keys from Keychain (use static method to avoid 'self' issue)
        self.openAIKey = Self.loadKeyFromKeychain(for: .openai)
        self.claudeKey = Self.loadKeyFromKeychain(for: .claude)
        self.geminiKey = Self.loadKeyFromKeychain(for: .gemini)
        self.grokKey = Self.loadKeyFromKeychain(for: .grok)
        self.groqKey = Self.loadKeyFromKeychain(for: .groq)
    }

    // MARK: - Computed Properties

    var hasConfiguredProvider: Bool {
        // Apple PCC doesn't need an API key
        if selectedProvider == .applePCC {
            return true
        }
        return !currentAPIKey.isEmpty
    }

    var currentAPIKey: String {
        switch selectedProvider {
        case .applePCC: return ""  // No API key needed
        case .openai: return openAIKey
        case .claude: return claudeKey
        case .gemini: return geminiKey
        case .groq: return groqKey
        case .grok: return grokKey
        }
    }

    var currentModel: String {
        switch selectedProvider {
        case .applePCC: return "Apple Intelligence"
        case .openai: return selectedOpenAIModel
        case .claude: return selectedClaudeModel
        case .gemini: return selectedGeminiModel
        case .groq: return selectedGroqModel
        case .grok: return selectedGrokModel
        }
    }

    func apiKey(for provider: CloudAIProvider) -> String {
        switch provider {
        case .applePCC: return ""  // No API key needed
        case .openai: return openAIKey
        case .claude: return claudeKey
        case .gemini: return geminiKey
        case .groq: return groqKey
        case .grok: return grokKey
        }
    }

    func setAPIKey(_ key: String, for provider: CloudAIProvider) {
        switch provider {
        case .applePCC: break  // No API key needed
        case .openai: openAIKey = key
        case .claude: claudeKey = key
        case .gemini: geminiKey = key
        case .groq: groqKey = key
        case .grok: grokKey = key
        }
    }

    // MARK: - Persistence

    private func saveSettings() {
        UserDefaults.standard.set(selectedProvider.rawValue, forKey: "ai_selected_provider")
        UserDefaults.standard.set(selectedOpenAIModel, forKey: "ai_openai_model")
        UserDefaults.standard.set(selectedClaudeModel, forKey: "ai_claude_model")
        UserDefaults.standard.set(selectedGeminiModel, forKey: "ai_gemini_model")
        UserDefaults.standard.set(selectedGrokModel, forKey: "ai_grok_model")
        UserDefaults.standard.set(selectedGroqModel, forKey: "ai_groq_model")
        UserDefaults.standard.set(analysisLanguage.rawValue, forKey: "ai_analysis_language")
    }

    // MARK: - Keychain Helpers

    private static func keychainKeyName(for provider: CloudAIProvider) -> String {
        "com.podcastanalyzer.apikey.\(provider.rawValue.lowercased())"
    }

    private func saveToKeychain(key: String, for provider: CloudAIProvider) {
        let keychainKey = Self.keychainKeyName(for: provider)
        let data = key.data(using: .utf8)!

        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new if not empty
        if !key.isEmpty {
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: keychainKey,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
            ]
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private static func loadKeyFromKeychain(for provider: CloudAIProvider) -> String {
        let keychainKey = keychainKeyName(for: provider)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8) ?? ""
        }
        return ""
    }
}
