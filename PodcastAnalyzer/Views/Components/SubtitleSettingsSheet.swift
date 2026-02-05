//
//  SubtitleSettingsSheet.swift
//  PodcastAnalyzer
//
//  Settings sheet for subtitle display and translation options
//

import SwiftUI

struct SubtitleSettingsSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var settings = SubtitleSettingsManager.shared

  var body: some View {
    NavigationStack {
      Form {
        // Display Mode Section
        Section {
          ForEach(SubtitleDisplayMode.allCases, id: \.self) { mode in
            Button {
              settings.displayMode = mode
            } label: {
              HStack {
                Label(mode.displayName, systemImage: mode.icon)
                  .foregroundStyle(.primary)
                Spacer()
                if settings.displayMode == mode {
                  Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
                }
              }
            }
          }
        } header: {
          Text("Display Mode")
        } footer: {
          Text(settings.displayMode.description)
        }

        // Translation Section
        Section {
          Picker("Target Language", selection: $settings.targetLanguage) {
            ForEach(TranslationTargetLanguage.allCases, id: \.self) { lang in
              Text(lang.displayName).tag(lang)
            }
          }

          Toggle("Auto-translate on load", isOn: $settings.autoTranslateOnLoad)
        } header: {
          Text("Translation")
        } footer: {
          if !settings.isTranslationAvailable {
            Text("Translation requires iOS 17.4 or later")
              .foregroundStyle(.orange)
          }
        }

        // Download Section
        Section {
          Toggle("Auto-download with episode", isOn: $settings.autoDownloadTranscripts)
        } header: {
          Text("RSS Transcripts")
        } footer: {
          Text("Automatically download transcripts from RSS feeds when downloading episodes")
        }

        // Info Section
        Section {
          VStack(alignment: .leading, spacing: 8) {
            Text("Transcript Sources")
              .font(.subheadline.bold())
            Text("Transcripts can come from:")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text("- RSS feed (podcast:transcript tag)")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text("- On-device speech recognition")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .padding(.vertical, 4)
        } header: {
          Text("About")
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Subtitle Settings")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            dismiss()
          }
        }
      }
    }
  }
}

#Preview {
  SubtitleSettingsSheet()
}
