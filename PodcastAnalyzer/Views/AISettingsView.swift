//
//  AISettingsView.swift
//  PodcastAnalyzer
//
//  Settings UI for configuring Cloud AI providers (BYOK)
//

import SwiftUI

struct AISettingsView: View {
    @State private var settings = AISettingsManager.shared
    @State private var showingTestResult = false
    @State private var testResultMessage = ""
    @State private var testResultSuccess = false
    @State private var isTesting = false

    // Dynamic model fetching
    @State private var fetchedModels: [CloudAIProvider: [String]] = [:]
    @State private var isFetchingModels = false
    @State private var modelFetchError: String?

    // On-device AI availability
    @State private var onDeviceAvailability: FoundationModelsAvailability = .unavailable(reason: "Checking...")

    var body: some View {
        Form {
            // MARK: - Provider Selection
            Section {
                Picker("AI Provider", selection: $settings.selectedProvider) {
                    ForEach(CloudAIProvider.allCases, id: \.self) { provider in
                        Label(provider.displayName, systemImage: provider.iconName)
                            .tag(provider)
                    }
                }
                .onChange(of: settings.selectedProvider) { _, newProvider in
                    // Auto-fetch models when provider changes if API key exists
                    let apiKey = settings.apiKey(for: newProvider)
                    if !apiKey.isEmpty && fetchedModels[newProvider] == nil {
                        fetchModels(for: newProvider)
                    }
                }

                if let url = settings.selectedProvider.apiKeyURL {
                    Link(destination: url) {
                        HStack {
                            Text("Get \(settings.selectedProvider.displayName) API Key")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                        }
                    }
                }

                Text(settings.selectedProvider.pricingNote)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Cloud AI Provider")
            } footer: {
                Text("Cloud AI is used for full transcript analysis. You provide your own API key (BYOK).")
            }

            // MARK: - API Key Input (for providers that need it)
            if settings.selectedProvider.requiresAPIKey {
                Section {
                    apiKeyField(for: settings.selectedProvider)

                    // Model selection with refresh button
                    HStack {
                        modelPicker(for: settings.selectedProvider)

                        // Refresh models button
                        Button(action: { fetchModels(for: settings.selectedProvider) }) {
                            if isFetchingModels {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .disabled(settings.currentAPIKey.isEmpty || isFetchingModels)
                        .buttonStyle(.borderless)
                    }

                    // Model fetch status
                    if isFetchingModels {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Fetching available models...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if let error = modelFetchError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    } else if let models = fetchedModels[settings.selectedProvider], !models.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("\(models.count) models available")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Test connection button
                    Button(action: testConnection) {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "checkmark.circle")
                            }
                            Text("Test Connection")
                        }
                    }
                    .disabled(settings.currentAPIKey.isEmpty || isTesting)
                } header: {
                    Text("\(settings.selectedProvider.displayName) Configuration")
                } footer: {
                    Text("Tap the refresh button to fetch the latest available models from the API.")
                }
            }

            // MARK: - Apple PCC Configuration
            if settings.selectedProvider == .applePCC {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("No API key needed!")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }

                        Text("Apple Intelligence via Shortcuts uses Apple's Private Cloud Compute for AI analysis. Your data is processed securely on Apple's servers.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Shortcut name configuration
                    HStack {
                        Text("Shortcut Name")
                        Spacer()
                        TextField("Shortcut Name", text: Binding(
                            get: { ShortcutsAIService.shared.shortcutName },
                            set: { ShortcutsAIService.shared.shortcutName = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        .multilineTextAlignment(.trailing)
                    }

                    Button(action: {
                        ShortcutsAIService.shared.openShortcutsApp()
                    }) {
                        HStack {
                            Image(systemName: "square.on.square")
                            Text("Open Shortcuts App")
                        }
                    }
                } header: {
                    Text("Shortcut Configuration")
                } footer: {
                    Text("Enter the exact name of your shortcut. The app will run this shortcut automatically.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Setup Instructions:")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        VStack(alignment: .leading, spacing: 4) {
                            instructionRow(number: 1, text: "Open the Shortcuts app")
                            instructionRow(number: 2, text: "Create a new shortcut")
                            instructionRow(number: 3, text: "Add 'Get Clipboard' action")
                            instructionRow(number: 4, text: "Add 'Summarize' or 'Ask ChatGPT' action")
                            instructionRow(number: 5, text: "Set output to 'Text'")
                            instructionRow(number: 6, text: "Add 'Copy to Clipboard' action")
                            instructionRow(number: 7, text: "Name it exactly as configured above")
                        }
                    }

                    // Tip about Ask Every Time
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.yellow)
                            Text("Pro Tip")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        Text("Use 'Ask Every Time' for the Model parameter to choose between Apple Intelligence (PCC), ChatGPT, or other models each time you run the shortcut.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(8)

                    // How it works
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("How It Works")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        Text("When you analyze a transcript, the app will automatically run your shortcut, wait for it to complete, and display the result. No manual copy/paste needed!")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                } header: {
                    Text("Setup Instructions")
                }
            }

            // MARK: - Analysis Language
            Section {
                Picker("Response Language", selection: $settings.analysisLanguage) {
                    ForEach(AnalysisLanguage.allCases, id: \.self) { language in
                        Label {
                            VStack(alignment: .leading) {
                                Text(language.displayName)
                            }
                        } icon: {
                            Image(systemName: language.icon)
                        }
                        .tag(language)
                    }
                }
                .pickerStyle(.navigationLink)

                // Show current language preview
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text(settings.analysisLanguage.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Analysis Language")
            } footer: {
                Text("Controls the language of AI-generated summaries, highlights, and other analysis results.")
            }

            // MARK: - Other Provider Keys (Collapsed)
            Section {
                DisclosureGroup("Configure Other Providers") {
                    ForEach(CloudAIProvider.allCases.filter { $0 != settings.selectedProvider }, id: \.self) { provider in
                        VStack(alignment: .leading, spacing: 8) {
                            Label(provider.displayName, systemImage: provider.iconName)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            apiKeyField(for: provider)

                            if !settings.apiKey(for: provider).isEmpty {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Key configured")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Divider()
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("Additional Providers")
            }

            // MARK: - On-Device AI Info
            Section {
                HStack {
                    Image(systemName: "apple.intelligence")
                        .foregroundColor(.blue)
                    VStack(alignment: .leading) {
                        Text("Apple Foundation Models")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Used for quick tags & categorization (no API key needed)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Show actual availability status
                HStack {
                    if onDeviceAvailability.isAvailable {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Available and ready")
                            .font(.caption)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(onDeviceAvailability.message ?? "Not available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("On-Device AI")
            } footer: {
                Text("On-device AI handles simple tasks like generating tags from episode titles. No internet required, completely private.")
            }

            // MARK: - Context Window Info
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("On-Device")
                        Spacer()
                        Text("~4,096 tokens")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text(settings.selectedProvider.displayName)
                        Spacer()
                        Text("\(formatNumber(settings.selectedProvider.contextWindowSize)) tokens")
                            .foregroundColor(.secondary)
                    }
                }
                .font(.subheadline)
            } header: {
                Text("Context Window Comparison")
            } footer: {
                Text("Larger context windows allow analyzing longer transcripts in a single request, resulting in better quality summaries.")
            }
        }
        .navigationTitle("AI Settings")
        .alert(testResultSuccess ? "Success" : "Error", isPresented: $showingTestResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(testResultMessage)
        }
        .onAppear {
            // Auto-fetch models if API key exists
            let provider = settings.selectedProvider
            let apiKey = settings.apiKey(for: provider)
            if !apiKey.isEmpty && fetchedModels[provider] == nil {
                fetchModels(for: provider)
            }

            // Check on-device AI availability
            checkOnDeviceAvailability()
        }
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func apiKeyField(for provider: CloudAIProvider) -> some View {
        let binding = Binding<String>(
            get: { settings.apiKey(for: provider) },
            set: { newValue in
                settings.setAPIKey(newValue, for: provider)
                // Auto-fetch models when API key is entered
                if !newValue.isEmpty && provider == settings.selectedProvider {
                    fetchModels(for: provider)
                }
            }
        )

        SecureField("\(provider.displayName) API Key", text: binding)
            .textContentType(.password)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
    }

    @ViewBuilder
    private func modelPicker(for provider: CloudAIProvider) -> some View {
        let binding: Binding<String> = {
            switch provider {
            case .applePCC:
                return .constant("Apple Intelligence")
            case .openai:
                return $settings.selectedOpenAIModel
            case .claude:
                return $settings.selectedClaudeModel
            case .gemini:
                return $settings.selectedGeminiModel
            case .groq:
                return $settings.selectedGroqModel
            case .grok:
                return $settings.selectedGrokModel
            }
        }()

        // Use fetched models if available, otherwise use hardcoded defaults
        let models = fetchedModels[provider] ?? provider.availableModels

        Picker("Model", selection: binding) {
            ForEach(models, id: \.self) { model in
                Text(model).tag(model)
            }
        }
    }

    // MARK: - Actions

    private func fetchModels(for provider: CloudAIProvider) {
        let apiKey = settings.apiKey(for: provider)
        guard !apiKey.isEmpty else { return }

        isFetchingModels = true
        modelFetchError = nil

        Task {
            do {
                let service = CloudAIService.shared
                let models = try await service.fetchAvailableModels(for: provider, apiKey: apiKey)

                await MainActor.run {
                    fetchedModels[provider] = models
                    isFetchingModels = false

                    // If current model is not in the list, select the first available
                    let currentModel: String
                    switch provider {
                    case .applePCC: currentModel = "Apple Intelligence"
                    case .openai: currentModel = settings.selectedOpenAIModel
                    case .claude: currentModel = settings.selectedClaudeModel
                    case .gemini: currentModel = settings.selectedGeminiModel
                    case .groq: currentModel = settings.selectedGroqModel
                    case .grok: currentModel = settings.selectedGrokModel
                    }

                    if !models.contains(currentModel), let firstModel = models.first {
                        switch provider {
                        case .applePCC: break  // No model selection for Apple PCC
                        case .openai: settings.selectedOpenAIModel = firstModel
                        case .claude: settings.selectedClaudeModel = firstModel
                        case .gemini: settings.selectedGeminiModel = firstModel
                        case .groq: settings.selectedGroqModel = firstModel
                        case .grok: settings.selectedGrokModel = firstModel
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    modelFetchError = "Could not fetch models. Using defaults."
                    isFetchingModels = false
                    // Keep using hardcoded models
                    fetchedModels[provider] = provider.availableModels
                }
            }
        }
    }

    private func testConnection() {
        isTesting = true

        Task {
            do {
                let service = CloudAIService.shared
                _ = try await service.testConnection()

                await MainActor.run {
                    testResultSuccess = true
                    testResultMessage = "Connection successful!\n\nProvider: \(settings.selectedProvider.displayName)\nModel: \(settings.currentModel)"
                    showingTestResult = true
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResultSuccess = false
                    testResultMessage = "Connection failed: \(error.localizedDescription)"
                    showingTestResult = true
                    isTesting = false
                }
            }
        }
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.blue)
                .frame(width: 20, alignment: .leading)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func checkOnDeviceAvailability() {
        if #available(iOS 26.0, macOS 26.0, *) {
            Task {
                let service = AppleFoundationModelsService()
                let availability = await service.checkAvailability()

                await MainActor.run {
                    onDeviceAvailability = availability
                }
            }
        } else {
            onDeviceAvailability = .unavailable(reason: "Requires iOS 26+ / macOS 26+")
        }
    }
}

#Preview {
    NavigationStack {
        AISettingsView()
    }
}
