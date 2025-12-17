//
//  MiniPlayerBar.swift
//  PodcastAnalyzer
//
//  Mini player bar at bottom (like Apple Podcasts)
//

import SwiftUI
import Combine

struct MiniPlayerBar: View {
    @StateObject private var viewModel = MiniPlayerViewModel()
    @State private var showFullPlayer = false
    
    var body: some View {
        if viewModel.isVisible {
            VStack(spacing: 0) {
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 2)
                        
                        Rectangle()
                            .fill(Color.blue)
                            .frame(
                                width: geometry.size.width * CGFloat(viewModel.progress),
                                height: 2
                            )
                    }
                }
                .frame(height: 2)
                
                // Main content
                HStack(spacing: 12) {
                    // Artwork
                    if let imageURL = viewModel.imageURL {
                        AsyncImage(url: imageURL) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Color.gray
                            }
                        }
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 50, height: 50)
                            .overlay(
                                Image(systemName: "music.note")
                                    .foregroundColor(.white)
                            )
                    }
                    
                    // Episode info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.episodeTitle)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        
                        Text(viewModel.podcastTitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // Play/Pause button
                    Button(action: {
                        viewModel.togglePlayPause()
                    }) {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                    .padding(.trailing, 8)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Color(uiColor: .systemBackground)
                        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: -2)
                )
                .onTapGesture {
                    showFullPlayer = true
                }
            }
            .frame(height: 70) // Fixed height
            .fullScreenCover(isPresented: $showFullPlayer) {
                if let episode = viewModel.currentEpisode {
                    PlayerView(
                        episode: PodcastEpisodeInfo(
                            title: episode.title,
                            podcastEpisodeDescription: nil,
                            pubDate: nil,
                            audioURL: episode.audioURL,
                            imageURL: episode.imageURL
                        ),
                        podcastTitle: episode.podcastTitle,
                        audioURL: episode.audioURL,
                        imageURL: episode.imageURL
                    )
                }
            }
        }
    }
}


// MARK: - Preview

#Preview {
    MiniPlayerBar()
}
