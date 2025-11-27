//
//  EpisodeDetailView.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/11/28.
//

import SwiftUI

struct EpisodeDetailView: View {
    @State private var viewModel: EpisodeDetailViewModel
    
    init(episode: PodcastEpisodeInfo, fallbackImageURL: String?) {
        _viewModel = State(initialValue: EpisodeDetailViewModel(
            episode: episode,
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
                        .frame(width: 100, height: 100)
                        .cornerRadius(12)
                        .shadow(radius: 5)
                    } else {
                        Color.gray.frame(width: 100, height: 100).cornerRadius(12)
                    }
                    
                    // Meta
                    VStack(alignment: .leading, spacing: 6) {
                        if let dateString = viewModel.pubDateString {
                            Text(dateString)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Image(systemName: "clock")
                            Text("--:--")
                        }
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.top, 2)
                    }
                }
                
                // Title
                Text(viewModel.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.leading)
                
                // MARK: - Action Buttons
                HStack(spacing: 12) {
                    Button(action: {
                        viewModel.playAction()
                    }) {
                        // Change Icon based on playing state
                        Label(viewModel.isPlayingThisEpisode ? "Pause" : "Play Episode",
                              systemImage: viewModel.isPlayingThisEpisode ? "pause.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(viewModel.isPlayDisabled)

                    // Share
                    if let audioURLString = viewModel.audioURL,
                       let url = URL(string: audioURLString) {
                        ShareLink(item: url) {
                             Image(systemName: "square.and.arrow.up")
                                .font(.title2)
                                .padding(12)
                                .background(Color.gray.opacity(0.2))
                                .clipShape(Circle())
                        }
                    }
                }
                
                Divider()
                
                // MARK: - HTML Description
                VStack(alignment: .leading, spacing: 8) {
                    Text("Episode Notes")
                        .font(.headline)
                    
                    // This renders the HTMLTextView created in ViewModel
                    viewModel.descriptionView
                }
            }
            .padding()
        }
        .navigationTitle("Episode Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}
