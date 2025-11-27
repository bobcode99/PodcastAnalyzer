//
//  AudioManager.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/11/28.
//


import Foundation
import AVFoundation

@Observable
class AudioManager {
    static let shared = AudioManager() // Singleton
    
    var player: AVPlayer?
    var isPlaying: Bool = false
    var currentUrlString: String? = nil
    
    private init() {
        // Configure audio session to play even if switch is on silent
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
    }
    
    func play(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        
        // If clicking the same song, toggle pause/play
        if currentUrlString == urlString, let player = player {
            if isPlaying {
                player.pause()
                isPlaying = false
            } else {
                player.play()
                isPlaying = true
            }
            return
        }
        
        // New song
        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        player?.play()
        
        currentUrlString = urlString
        isPlaying = true
    }
    
    func stop() {
        player?.pause()
        player = nil
        isPlaying = false
        currentUrlString = nil
    }
}