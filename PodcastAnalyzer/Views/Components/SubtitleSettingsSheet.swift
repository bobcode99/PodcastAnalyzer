//
//  SubtitleSettingsSheet.swift
//  PodcastAnalyzer
//
//  Settings sheet for subtitle display and translation options
//

import SwiftUI

struct SubtitleSettingsSheet: View {
  @Environment(\.dismiss) private var dismiss
  private var settings: SubtitleSettingsManager { .shared }

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
