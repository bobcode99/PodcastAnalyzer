//
//  TranscriptGenerationView.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/12/17.
//


//
//  TranscriptGenerationView.swift
//  PodcastAnalyzer
//
//  View for generating and displaying episode transcripts
//

import SwiftUI
import Combine

struct TranscriptGenerationView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: TranscriptGenerationViewModel
    
    init(episode: PodcastEpisodeInfo, podcastTitle: String, localAudioPath: String?) {
        _viewModel = StateObject(wrappedValue: TranscriptGenerationViewModel(
            episode: episode,
            podcastTitle: podcastTitle,
            localAudioPath: localAudioPath
        ))
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    
                    // MARK: - Status Section
                    statusSection
                    
                    // MARK: - Transcript Content
                    if !viewModel.transcriptText.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Transcript")
                                    .font(.headline)
                                Spacer()
                                
                                // Copy button
                                Button(action: {
                                    UIPasteboard.general.string = viewModel.transcriptText
                                    viewModel.showCopySuccess = true
                                }) {
                                    Label("Copy", systemImage: "doc.on.doc")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                
                                // Share button
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
                }
                .padding()
            }
            .navigationTitle("Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .alert("Success", isPresented: $viewModel.showCopySuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Transcript copied to clipboard")
            }
            .onAppear {
                viewModel.checkTranscriptStatus()
            }
        }
    }
    
    // MARK: - Status Section
    
    @ViewBuilder
    private var statusSection: some View {
        VStack(spacing: 16) {
            switch viewModel.state {
            case .idle:
                VStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)
                    
                    Text("Ready to Generate Transcript")
                        .font(.headline)
                    
                    if !viewModel.isModelReady {
                        Text("Speech recognition model will be downloaded on first use")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    Button(action: {
                        viewModel.generateTranscript()
                    }) {
                        Label("Generate Transcript", systemImage: "text.bubble")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                }
                
            case .downloadingModel(let progress):
                VStack(spacing: 12) {
                    ProgressView(value: progress)
                        .frame(width: 200)
                    
                    Text("Downloading Speech Model")
                        .font(.headline)
                    
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                            .foregroundColor(.secondary)
                    }
                }
                
            case .completed:
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.green)
                    
                    Text("Transcript Generated")
                        .font(.headline)
                    
                    Text("Saved to Files app")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        viewModel.regenerateTranscript()
                    }) {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
                
            case .error(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.red)
                    
                    Text("Error")
                        .font(.headline)
                    
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button(action: {
                        viewModel.generateTranscript()
                    }) {
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
}

// MARK: - ViewModel

enum TranscriptState {
    case idle
    case downloadingModel(progress: Double)
    case transcribing(progress: Double)
    case completed
    case error(String)
}

@MainActor
class TranscriptGenerationViewModel: ObservableObject {
    @Published var state: TranscriptState = .idle
    @Published var transcriptText: String = ""
    @Published var showCopySuccess: Bool = false
    @Published var isModelReady: Bool = false
    
    private let episode: PodcastEpisodeInfo
    private let podcastTitle: String
    private let localAudioPath: String?
    private let fileStorage = FileStorageManager.shared
    
    var captionFileURL: URL?
    
    init(episode: PodcastEpisodeInfo, podcastTitle: String, localAudioPath: String?) {
        self.episode = episode
        self.podcastTitle = podcastTitle
        self.localAudioPath = localAudioPath
    }
    
    func checkTranscriptStatus() {
        Task {
            // Check if model is ready
            let transcriptService = TranscriptService()
            isModelReady = await transcriptService.isModelReady()
            
            // Check if transcript already exists
            let exists = await fileStorage.captionFileExists(
                for: episode.title,
                podcastTitle: podcastTitle
            )
            
            if exists {
                await loadExistingTranscript()
            }
        }
    }
    
    func generateTranscript() {
        guard let audioPath = localAudioPath else {
            state = .error("No local audio file available. Please download the episode first.")
            return
        }
        
        Task {
            do {
                let audioURL = URL(fileURLWithPath: audioPath)
                let transcriptService = TranscriptService()
                
                // Check if we need to download the model
                if !(await transcriptService.isModelReady()) {
                    state = .downloadingModel(progress: 0)
                    
                    // Setup and download model with progress
                    for await progress in await transcriptService.setupAndInstallAssets() {
                        state = .downloadingModel(progress: progress)
                    }
                }
                
                // Start transcription
                state = .transcribing(progress: 0)
                
                let srtContent = try await transcriptService.audioToSRT(inputFile: audioURL)
                
                // Save to file
                let captionURL = try await fileStorage.saveCaptionFile(
                    content: srtContent,
                    episodeTitle: episode.title,
                    podcastTitle: podcastTitle
                )
                
                self.captionFileURL = captionURL
                self.transcriptText = srtContent
                self.state = .completed
                
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }
    
    func regenerateTranscript() {
        // Delete existing transcript
        Task {
            do {
                if await fileStorage.captionFileExists(for: episode.title, podcastTitle: podcastTitle) {
                    try await fileStorage.deleteCaptionFile(for: episode.title, podcastTitle: podcastTitle)
                }
            } catch {
                print("Failed to delete existing transcript: \(error)")
            }
            
            // Generate new transcript
            await MainActor.run {
                generateTranscript()
            }
        }
    }
    
    private func loadExistingTranscript() async {
        do {
            let content = try await fileStorage.loadCaptionFile(
                for: episode.title,
                podcastTitle: podcastTitle
            )
            
            let captionURL = await fileStorage.captionFilePath(
                for: episode.title,
                podcastTitle: podcastTitle
            )
            
            await MainActor.run {
                self.transcriptText = content
                self.captionFileURL = captionURL
                self.state = .completed
            }
        } catch {
            print("Failed to load transcript: \(error)")
        }
    }
}
