//
//  EpisodeDetailViewModel.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/11/28.
//

import SwiftUI
import ZMarkupParser

@Observable
final class EpisodeDetailViewModel {
    
    var descriptionView: AnyView = AnyView(
        Text("Loading...").foregroundColor(.secondary)
    )
    
    private let episode: PodcastEpisodeInfo
    private let fallbackImageURL: String?
    
    // Reference the singleton
    private let audioManager = AudioManager.shared
    
    init(episode: PodcastEpisodeInfo, fallbackImageURL: String?) {
        self.episode = episode
        self.fallbackImageURL = fallbackImageURL
        parseDescription()
    }
    
    var title: String { episode.title }
    
    var pubDateString: String? {
        episode.pubDate?.formatted(date: .long, time: .omitted)
    }
    
    var imageURLString: String {
        episode.imageURL ?? fallbackImageURL ?? ""
    }
    
    var audioURL: String? { episode.audioURL }
    var isPlayDisabled: Bool { episode.audioURL == nil }
    
    // Check if THIS episode is currently playing
    var isPlayingThisEpisode: Bool {
        return audioManager.isPlaying && audioManager.currentUrlString == episode.audioURL
    }
    
    func playAction() {
        guard let url = episode.audioURL else { return }
        print("Toggle Play/Pause: \(url)")
        audioManager.play(urlString: url)
    }
    
    // MARK: - ZMarkupParser Logic
    private func parseDescription() {
        let html = episode.podcastEpisodeDescription ?? ""
        
        guard !html.isEmpty else {
            descriptionView = AnyView(
                Text("No description available.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            )
            return
        }
        
        // 1. Define Style
        let rootStyle = MarkupStyle(
            font: MarkupStyleFont(size: 16),
            foregroundColor: MarkupStyleColor(color: UIColor.label) // Adapts to Dark/Light mode
        )
        
        // 2. Build Parser
        let parser = ZHTMLParserBuilder.initWithDefault()
            .set(rootStyle: rootStyle)
            .build()
        
        Task {
            // 3. Render
            // render(html) returns NSAttributedString synchronously (fast enough for background task)
            let attributedString = parser.render(html)
            
            await MainActor.run {
                // 4. Pass to our Helper View
                self.descriptionView = AnyView(
                    HTMLTextView(attributedString: attributedString)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                )
            }
        }
    }
}
