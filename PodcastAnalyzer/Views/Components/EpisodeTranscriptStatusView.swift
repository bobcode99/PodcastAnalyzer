
import SwiftUI

struct EpisodeTranscriptStatusView: View {
    @Bindable var viewModel: EpisodeDetailViewModel

    var body: some View {
        VStack(spacing: 16) {
            switch viewModel.transcriptState {
            case .idle:
                // Check RSS transcript availability first
                if viewModel.hasRSSTranscriptAvailable {
                    VStack(spacing: 12) {
                        Image(systemName: "captions.bubble")
                            .font(.system(size: 50))
                            .foregroundStyle(.blue)
                        Text("Transcript Available").font(.headline)
                        Text("This episode has a transcript from the podcast feed.")
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button(action: { viewModel.downloadRSSTranscript() }) {
                            Label("Download Transcript", systemImage: "arrow.down.circle")
                                .font(.subheadline)
                                .padding(.horizontal, 20).padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if viewModel.isDownloadingRSSTranscript {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Downloading Transcript").font(.headline)
                            .padding(.top, 8)
                    }
                } else if viewModel.hasLocalAudio {
                    VStack(spacing: 12) {
                        Image(systemName: "waveform")
                            .font(.system(size: 50))
                            .foregroundStyle(.blue)
                        Text("Ready to Generate Transcript").font(.headline)
                        if !viewModel.isModelReady {
                            Text(
                                "Speech recognition model will be downloaded on first use"
                            )
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(
                                .center
                            )
                        }

                        // Language picker for transcript generation
                        Picker("Language", selection: Binding(
                            get: { viewModel.selectedTranscriptLanguage ?? viewModel.podcastLanguage },
                            set: { newValue in
                                viewModel.selectedTranscriptLanguage = (newValue == viewModel.podcastLanguage) ? nil : newValue
                            }
                        )) {
                            ForEach(SettingsViewModel.availableTranscriptLocales) { locale in
                                Text(locale.name).tag(locale.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(.subheadline)

                        Text("Mixed-language episodes may not transcribe accurately")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button(action: { viewModel.generateTranscript() }) {
                            Label(
                                "Generate Transcript",
                                systemImage: "text.bubble"
                            )
                            .font(.subheadline)
                            .padding(.horizontal, 20).padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 50))
                            .foregroundStyle(.secondary)
                        Text("Download Episode to Transcribe").font(.headline)
                        Text(
                            "You need to download the episode audio before generating a transcript."
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        Button(action: { viewModel.startDownload() }) {
                            Label("Download Episode", systemImage: "arrow.down.circle")
                                .font(.subheadline)
                                .padding(.horizontal, 20).padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

            case .downloadingModel(let progress):
                VStack(spacing: 12) {
                    ProgressView(value: progress) {
                        Text("Downloading Speech Model...")
                            .font(.caption)
                    }
                    .progressViewStyle(.linear)
                    .frame(width: 200)

                    Text("\(Int(progress * 100))%")
                        .font(.caption).foregroundStyle(.secondary)
                }

            case .transcribing(let progress):
                VStack(spacing: 12) {
                    ProgressView(value: progress) {
                        Text("Generating Transcript...")
                            .font(.caption)
                    }
                    .progressViewStyle(.linear)
                    .frame(width: 200)

                    Text("\(Int(progress * 100))%")
                        .font(.caption).foregroundStyle(.secondary)
                    
                }

            case .completed:
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.green)
                    Text("Transcript Ready").font(.headline)
                }

            case .error(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.red)
                    Text("Transcription Failed").font(.headline)
                    Text(message)
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    
                        Button("Try Again") {
                            viewModel.generateTranscript()
                        }
                        .buttonStyle(.bordered)
                }
            }
        }
    }
}
