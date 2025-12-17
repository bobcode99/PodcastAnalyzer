//
//  EpisodeDetailView.swift
//  PodcastAnalyzer
//
//  Updated to show full-screen player
//

import SwiftUI
import SwiftData

struct EpisodeDetailView: View {
    @State private var viewModel: EpisodeDetailViewModel
    @Environment(\.modelContext) private var modelContext
    
    // Player state
    @State private var showFullPlayer = false
    @State private var showTranscriptSheet = false
    
    init(episode: PodcastEpisodeInfo, podcastTitle: String, fallbackImageURL: String?) {
        _viewModel = State(initialValue: EpisodeDetailViewModel(
            episode: episode,
            podcastTitle: podcastTitle,
            fallbackImageURL: fallbackImageURL
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // MARK: - Top Header
                HStack(alignment: .top, spacing: 16) {
                    // Image
                    if let url = URL(string: viewModel.imageURLString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFit()
                            case .failure:
                                Color.gray
                            case .empty:
                                ProgressView()
                            @unknown default:
                                Color.gray
                            }
                        }
                        .frame(width: 120, height: 120)
                        .cornerRadius(12)
                        .shadow(radius: 5)
                    } else {
                        Color.gray.frame(width: 120, height: 120).cornerRadius(12)
                    }
                    
                    // Meta
                    VStack(alignment: .leading, spacing: 8) {
                        if let dateString = viewModel.pubDateString {
                            Text(dateString)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        // Download status/button
                        downloadButton
                    }
                }
                
                // Title
                Text(viewModel.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.leading)
                
                // MARK: - Play Button (Opens Full Player)
                Button(action: {
                    showFullPlayer = true
                }) {
                    Label("Play Episode", systemImage: "play.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(viewModel.isPlayDisabled)
                
                // Mini player if episode is currently playing
                if viewModel.isPlayingThisEpisode {
                    miniPlayer
                }
                
                Divider()
                
                // MARK: - Transcript Button
                if viewModel.hasLocalAudio {
                    Button(action: {
                        showTranscriptSheet = true
                    }) {
                        Label("Generate/View Transcript", systemImage: "text.bubble")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                }
                
                Divider()
                
                // MARK: - HTML Description
                VStack(alignment: .leading, spacing: 8) {
                    Text("Episode Notes")
                        .font(.headline)
                    
                    viewModel.descriptionView
                }
            }
            .padding()
        }
        .navigationTitle("Episode Details")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showFullPlayer) {
            PlayerView(
                episode: viewModel.episode,
                podcastTitle: viewModel.podcastTitle,
                audioURL: viewModel.playbackURL,
                imageURL: viewModel.imageURLString
            )
        }
        .sheet(isPresented: $showTranscriptSheet) {
            TranscriptGenerationView(
                episode: viewModel.episode,
                podcastTitle: viewModel.podcastTitle,
                localAudioPath: viewModel.localAudioPath
            )
        }
        .onAppear {
            viewModel.setModelContext(modelContext)
        }
    }
    
    // MARK: - Mini Player (When Playing)
    
    @ViewBuilder
    private var miniPlayer: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "waveform")
                    .foregroundColor(.blue)
                Text("Now Playing")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: {
                    showFullPlayer = true
                }) {
                    Text("Open Player")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            // Progress bar
            ProgressView(value: viewModel.currentTime, total: viewModel.duration)
                .tint(.blue)
            
            HStack {
                Text(formatTime(viewModel.currentTime))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatTime(viewModel.duration))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Download Button
    
    @ViewBuilder
    private var downloadButton: some View {
        switch viewModel.downloadState {
        case .notDownloaded:
            Button(action: {
                viewModel.startDownload()
            }) {
                Label("Download", systemImage: "arrow.down.circle")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.blue)
            
        case .downloading(let progress):
            VStack(spacing: 4) {
                ProgressView(value: progress)
                    .frame(width: 80)
                Text("\(Int(progress * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Button("Cancel") {
                    viewModel.cancelDownload()
                }
                .font(.caption2)
                .foregroundColor(.red)
            }
            
        case .downloaded:
            Button(action: {
                viewModel.deleteDownload()
            }) {
                Label("Delete", systemImage: "trash")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            
        case .failed(let error):
            VStack(spacing: 4) {
                Text("Failed")
                    .font(.caption)
                    .foregroundColor(.red)
                Button("Retry") {
                    viewModel.startDownload()
                }
                .font(.caption2)
            }
        }
    }
    
    // MARK: - Helper
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
