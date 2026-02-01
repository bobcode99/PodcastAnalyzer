//
//  TranscriptGenerationView.swift
//  PodcastAnalyzer
//
//  View for generating and displaying episode transcripts
//

import SwiftData
import SwiftUI

#if os(iOS)
import UIKit
#endif

struct TranscriptGenerationView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @State private var viewModel: TranscriptGenerationViewModel

  init(episode: PodcastEpisodeInfo, podcastTitle: String, localAudioPath: String?) {
    _viewModel = State(
      initialValue: TranscriptGenerationViewModel(
        episode: episode,
        podcastTitle: podcastTitle,
        localAudioPath: localAudioPath
      ))
  }

  var body: some View {
    @Bindable var viewModel = viewModel
    NavigationStack {
      ScrollView {
        VStack(spacing: 20) {
          statusSection

          if !viewModel.transcriptText.isEmpty {
            transcriptContentSection
          }
        }
        .padding()
      }
      .navigationTitle("Transcript")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") { dismiss() }
        }
      }
      .alert("Success", isPresented: $viewModel.showCopySuccess) {
        Button("OK", role: .cancel) {}
      } message: {
        Text("Transcript copied to clipboard")
      }
      .onAppear {
        self.viewModel.setModelContext(modelContext)
        self.viewModel.checkTranscriptStatus()
      }
    }
  }

  @ViewBuilder
  private var transcriptContentSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Transcript")
          .font(.headline)
        Spacer()

        Button(action: {
          PlatformClipboard.string = viewModel.transcriptText
          viewModel.showCopySuccess = true
        }) {
          Label("Copy", systemImage: "doc.on.doc")
            .font(.caption)
        }
        .buttonStyle(.bordered)

        if let url = viewModel.captionFileURL {
          ShareLink(item: url) {
            Label("Share", systemImage: "square.and.arrow.up")
              .font(.caption)
          }
          .buttonStyle(.bordered)
        }
      }

      Text(viewModel.transcriptText)
        .font(.body)
        .textSelection(.enabled)
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
  }

  @ViewBuilder
  private var statusSection: some View {
    VStack(spacing: 16) {
      switch viewModel.state {
      case .idle:
        idleStateView

      case .downloadingModel(let progress):
        VStack(spacing: 12) {
          ProgressView(value: progress)
            .frame(width: 200)
          Text("Downloading Speech Model")
            .font(.headline)
          Text("\(Int(progress * 100))%")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

      case .transcribing(let progress):
        VStack(spacing: 12) {
          ProgressView()
            .scaleEffect(1.5)
          Text("Generating Transcript...")
            .font(.headline)
          if progress > 0 {
            Text("Processing audio...")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

      case .completed:
        VStack(spacing: 12) {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 50))
            .foregroundStyle(.green)
          Text("Transcript Generated")
            .font(.headline)
          Text("Saved to Files app")
            .font(.caption)
            .foregroundStyle(.secondary)
          Button(action: { viewModel.regenerateTranscript() }) {
            Label("Regenerate", systemImage: "arrow.clockwise")
          }
          .buttonStyle(.bordered)
        }

      case .error(let message):
        VStack(spacing: 12) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 50))
            .foregroundStyle(.red)
          Text("Error")
            .font(.headline)
          Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
          Button(action: { viewModel.generateTranscript() }) {
            Label("Retry", systemImage: "arrow.clockwise")
          }
          .buttonStyle(.bordered)
        }
      }
    }
    .frame(maxWidth: .infinity)
    .padding()
    .background(Color.gray.opacity(0.1))
    .cornerRadius(12)
  }

  @ViewBuilder
  private var idleStateView: some View {
    VStack(spacing: 12) {
      Image(systemName: "waveform")
        .font(.system(size: 50))
        .foregroundStyle(.blue)

      Text("Ready to Generate Transcript")
        .font(.headline)

      if !viewModel.isModelReady {
        Text("Speech recognition model will be downloaded on first use")
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }

      Button(action: { viewModel.generateTranscript() }) {
        Label("Generate Transcript", systemImage: "text.bubble")
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
      }
      .buttonStyle(.borderedProminent)
    }
  }
}
