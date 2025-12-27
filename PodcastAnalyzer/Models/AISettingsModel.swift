//
//  AISettingsModel.swift
//  PodcastAnalyzer
//
//  Settings for AI providers (Cloud APIs with BYOK)
//

import Foundation
import SwiftUI

// MARK: - Cloud AI Provider

enum CloudAIProvider: String, CaseIterable, Codable {
    case openai = "OpenAI"
    case claude = "Claude"
    case gemini = "Gemini"
    case grok = "Grok"

    var displayName: String { rawValue }

    var iconName: String {
        switch self {
        case .openai: return "brain.head.profile"
        case .claude: return "sparkles"
        case .gemini: return "diamond"
        case .grok: return "bolt"
        }
    }

    var apiKeyURL: URL? {
        switch self {
        case .openai: return URL(string: "https://platform.openai.com/api-keys")
        case .claude: return URL(string: "https://console.anthropic.com/settings/keys")
        case .gemini: return URL(string: "https://aistudio.google.com/app/apikey")
        case .grok: return URL(string: "https://console.x.ai/")
        }
    }

    var defaultModel: String {
        switch self {
        case .openai: return "gpt-4o-mini"
        case .claude: return "claude-sonnet-4-5-20250929"
        case .gemini: return "gemini-2.0-flash"
        case .grok: return "grok-2-1212"
        }
    }

    var availableModels: [String] {
        switch self {
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
        case .openai: return 128_000
        case .claude: return 200_000
        case .gemini: return 1_000_000
        case .grok: return 128_000
        }
    }

    var pricingNote: String {
        switch self {
        case .openai: return "gpt-4o-mini: $0.15/1M input tokens"
        case .claude: return "Haiku: $0.25/1M input tokens"
        case .gemini: return "Flash: Free tier available!"
        case .grok: return "grok-beta: $5/1M input tokens"
        }
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

        // Load API keys from Keychain (use static method to avoid 'self' issue)
        self.openAIKey = Self.loadKeyFromKeychain(for: .openai)
        self.claudeKey = Self.loadKeyFromKeychain(for: .claude)
        self.geminiKey = Self.loadKeyFromKeychain(for: .gemini)
        self.grokKey = Self.loadKeyFromKeychain(for: .grok)
    }

    // MARK: - Computed Properties

    var hasConfiguredProvider: Bool {
        !currentAPIKey.isEmpty
    }

    var currentAPIKey: String {
        switch selectedProvider {
        case .openai: return openAIKey
        case .claude: return claudeKey
        case .gemini: return geminiKey
        case .grok: return grokKey
        }
    }

    var currentModel: String {
        switch selectedProvider {
        case .openai: return selectedOpenAIModel
        case .claude: return selectedClaudeModel
        case .gemini: return selectedGeminiModel
        case .grok: return selectedGrokModel
        }
    }

    func apiKey(for provider: CloudAIProvider) -> String {
        switch provider {
        case .openai: return openAIKey
        case .claude: return claudeKey
        case .gemini: return geminiKey
        case .grok: return grokKey
        }
    }

    func setAPIKey(_ key: String, for provider: CloudAIProvider) {
        switch provider {
        case .openai: openAIKey = key
        case .claude: claudeKey = key
        case .gemini: geminiKey = key
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
