//
//  EpoisodeView.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/11/23.
//

import SwiftUI

struct EpisodeListView: View {
    let podcastModel: PodcastInfoModel

    var body: some View {
        List {
            // MARK: - Header Section
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    // Podcast Image
                    if let url = URL(string: podcastModel.podcastInfo.imageURL) {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFit()
                                } else if phase.error != nil {
                                    Color.gray // Error placeholder
                                } else {
                                    ProgressView() // Loading
                                }
                            }
                            .frame(width: 100, height: 100)
                            .cornerRadius(8)
                        } else {
                            // Fallback if URL is invalid or empty
                            Color.gray.frame(width: 100, height: 100).cornerRadius(8)
                        }
                    
                    // Title and Summary
                    VStack(alignment: .leading, spacing: 4) {
                        Text(podcastModel.podcastInfo.title)
                            .font(.headline)
                        
                        if let summary = podcastModel.podcastInfo.podcastInfoDescription {
                            Text(summary)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                        }
                    }
                }
            }
            .listRowSeparator(.hidden)
            .padding(.bottom, 10)
            
            // MARK: - Episodes List
            Section(header: Text("Episodes (\(podcastModel.podcastInfo.episodes.count))")) {
                // Note: We use id: \.title because PodcastEpisodeInfo isn't strictly Identifiable yet.
                // ideally, use a unique ID if available.
                ForEach(podcastModel.podcastInfo.episodes, id: \.title) { episode in
                    
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(episode.title)
                            .font(.body)
                            .fontWeight(.medium)
                        
                        if let date = episode.pubDate {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        
                        if let audioURL = episode.audioURL {
                            Text(audioURL)
                        }
                        
                        
                        // Example: Add a Play button visual here later
                    }
                    .padding(.vertical, 4)
                   
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(podcastModel.podcastInfo.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}


//#Preview {
//    EpisodeListView(podcastModel: new PodcastInfoModel)
//}
