//
//  EpisodeDownloadModel.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/12/17.
//


//
//  EpisodeDownloadModel.swift
//  PodcastAnalyzer
//
//  SwiftData model to track downloads and playback state
//

import Foundation
import SwiftData

@Model
class EpisodeDownloadModel {
    @Attribute(.unique) var id: String
    
    var episodeTitle: String
    var podcastTitle: String
    var audioURL: String
    var localAudioPath: String?
    var captionPath: String?
    
    // Playback state
    var lastPlaybackPosition: TimeInterval
    var isCompleted: Bool
    var lastPlayedDate: Date?
    
    // Download metadata
    var downloadedDate: Date?
    var fileSize: Int64
    
    init(
        episodeTitle: String,
        podcastTitle: String,
        audioURL: String,
        localAudioPath: String? = nil,
        captionPath: String? = nil,
        lastPlaybackPosition: TimeInterval = 0,
        isCompleted: Bool = false,
        lastPlayedDate: Date? = nil,
        downloadedDate: Date? = nil,
        fileSize: Int64 = 0
    ) {
        self.id = "\(podcastTitle)|\(episodeTitle)"
        self.episodeTitle = episodeTitle
        self.podcastTitle = podcastTitle
        self.audioURL = audioURL
        self.localAudioPath = localAudioPath
        self.captionPath = captionPath
        self.lastPlaybackPosition = lastPlaybackPosition
        self.isCompleted = isCompleted
        self.lastPlayedDate = lastPlayedDate
        self.downloadedDate = downloadedDate
        self.fileSize = fileSize
    }
}