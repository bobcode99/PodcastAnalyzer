//
//  TranslationLanguagePickerSheet.swift
//  PodcastAnalyzer
//
//  Language picker sheet for selecting translation target language
//

import SwiftUI

struct TranslationLanguagePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Set of language codes that have cached translations available
    let availableTranslations: Set<String>

    /// Current translation status
    let translationStatus: TranslationStatus

    /// Callback when a language is selected
    let onSelectLanguage: (TranslationTargetLanguage) -> Void

    @State private var settings = SubtitleSettingsManager.shared

    var body: some View {
        NavigationStack {
            List {
                // Currently selected default language section
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Default Language")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(settings.targetLanguage.displayName)
                                .font(.headline)
                        }

                        Spacer()

                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelectLanguage(settings.targetLanguage)
                        dismiss()
                    }
                } header: {
                    Text("Quick Translate")
                } footer: {
                    Text("Tap to translate to your default language. Change the default in Settings.")
                }

                // All available languages
                Section {
                    ForEach(TranslationTargetLanguage.allCases.filter { $0 != .deviceLanguage }, id: \.self) { language in
                        languageRow(for: language)
                    }
                } header: {
                    Text("All Languages")
                }
            }
            .navigationTitle("Translate To")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func languageRow(for language: TranslationTargetLanguage) -> some View {
        let langCode = language.languageIdentifier
        let hasTranslation = availableTranslations.contains(langCode)
        let isTranslatingThisLanguage = isCurrentlyTranslating(language)

        Button {
            onSelectLanguage(language)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(language.displayName)
                        .foregroundStyle(.primary)

                    if hasTranslation {
                        Text("Cached")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                Spacer()

                if isTranslatingThisLanguage {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Translating...")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                } else if hasTranslation {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .disabled(isTranslatingThisLanguage)
    }

    private func isCurrentlyTranslating(_ language: TranslationTargetLanguage) -> Bool {
        guard case .translating = translationStatus else { return false }
        // Check if the current translation target matches this language
        let currentTarget = settings.targetLanguage
        return currentTarget == language
    }
}

#Preview {
    TranslationLanguagePickerSheet(
        availableTranslations: ["zh-Hant", "ja"],
        translationStatus: .idle,
        onSelectLanguage: { _ in }
    )
}
