//
//  DownloadState.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/12/17.
//


//
//  DownloadManager.swift
//  PodcastAnalyzer
//
//  Manages episode downloads with progress tracking
//

import Foundation
import Combine  // ✅ Add this
import os.log

enum DownloadState: Codable, Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded(localPath: String)
    case failed(error: String)
}

class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()
    
    // ✅ Use @Published instead
    @Published var downloadStates: [String: DownloadState] = [:]
    
    private var activeDownloads: [String: URLSessionDownloadTask] = [:]
    
    // ✅ Make it a lazy stored property
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.podcast.analyzer.downloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    private let logger = Logger(subsystem: "com.podcast.analyzer", category: "DownloadManager")
    private let fileStorage = FileStorageManager.shared
    
    override private init() {
        super.init()
    }
    
    // MARK: - Download Control
    
    func downloadEpisode(episode: PodcastEpisodeInfo, podcastTitle: String) {
        let episodeKey = makeKey(episode: episode.title, podcast: podcastTitle)
        
        guard let audioURLString = episode.audioURL,
              let url = URL(string: audioURLString) else {
            logger.error("Invalid audio URL for episode: \(episode.title)")
            downloadStates[episodeKey] = .failed(error: "Invalid URL")
            return
        }
        
        // Check if already downloaded
        Task {
            let exists = await fileStorage.audioFileExists(for: episode.title, podcastTitle: podcastTitle)
            if exists {
                let path = await fileStorage.audioFilePath(for: episode.title, podcastTitle: podcastTitle)
                await MainActor.run {
                    downloadStates[episodeKey] = .downloaded(localPath: path.path)
                }
                return
            }
            
            // Start download
            await MainActor.run {
                startDownload(url: url, episodeTitle: episode.title, podcastTitle: podcastTitle)
            }
        }
    }
    
    private func startDownload(url: URL, episodeTitle: String, podcastTitle: String) {
        let episodeKey = makeKey(episode: episodeTitle, podcast: podcastTitle)
        
        // Cancel existing download if any
        if let existingTask = activeDownloads[episodeKey] {
            existingTask.cancel()
        }
        
        let task = urlSession.downloadTask(with: url)
        activeDownloads[episodeKey] = task
        downloadStates[episodeKey] = .downloading(progress: 0)
        
        task.resume()
        logger.info("Started download: \(episodeTitle)")
    }
    
    func cancelDownload(episodeTitle: String, podcastTitle: String) {
        let episodeKey = makeKey(episode: episodeTitle, podcast: podcastTitle)
        
        if let task = activeDownloads[episodeKey] {
            task.cancel()
            activeDownloads.removeValue(forKey: episodeKey)
            downloadStates[episodeKey] = .notDownloaded
            logger.info("Cancelled download: \(episodeTitle)")
        }
    }
    
    func deleteDownload(episodeTitle: String, podcastTitle: String) {
        let episodeKey = makeKey(episode: episodeTitle, podcast: podcastTitle)
        
        Task {
            do {
                try await fileStorage.deleteAudioFile(for: episodeTitle, podcastTitle: podcastTitle)
                
                // Also delete captions if they exist
                if await fileStorage.captionFileExists(for: episodeTitle, podcastTitle: podcastTitle) {
                    try await fileStorage.deleteCaptionFile(for: episodeTitle, podcastTitle: podcastTitle)
                }
                
                await MainActor.run {
                    downloadStates[episodeKey] = .notDownloaded
                    logger.info("Deleted download: \(episodeTitle)")
                }
            } catch {
                logger.error("Failed to delete download: \(error.localizedDescription)")
            }
        }
    }
    
    func getDownloadState(episodeTitle: String, podcastTitle: String) -> DownloadState {
        let episodeKey = makeKey(episode: episodeTitle, podcast: podcastTitle)
        return downloadStates[episodeKey] ?? .notDownloaded
    }
    
    func getLocalPath(episodeTitle: String, podcastTitle: String) -> String? {
        let state = getDownloadState(episodeTitle: episodeTitle, podcastTitle: podcastTitle)
        if case .downloaded(let path) = state {
            return path
        }
        return nil
    }
    
    // MARK: - Helpers
    
    private func makeKey(episode: String, podcast: String) -> String {
        return "\(podcast)|\(episode)"
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let originalURL = downloadTask.originalRequest?.url else { return }
        
        // Find which episode this belongs to
        let episodeKey = activeDownloads.first(where: { $0.value == downloadTask })?.key
        guard let episodeKey = episodeKey else { return }
        
        let components = episodeKey.split(separator: "|")
        guard components.count == 2 else { return }
        
        let podcastTitle = String(components[0])
        let episodeTitle = String(components[1])
        
        Task {
            do {
                let destinationURL = try await fileStorage.saveAudioFile(
                    from: location,
                    episodeTitle: episodeTitle,
                    podcastTitle: podcastTitle
                )
                
                await MainActor.run {
                    downloadStates[episodeKey] = .downloaded(localPath: destinationURL.path)
                    activeDownloads.removeValue(forKey: episodeKey)
                    logger.info("Download completed: \(episodeTitle)")
                }
            } catch {
                await MainActor.run {
                    downloadStates[episodeKey] = .failed(error: error.localizedDescription)
                    activeDownloads.removeValue(forKey: episodeKey)
                    logger.error("Download save failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        
        // Find which episode this belongs to
        if let episodeKey = activeDownloads.first(where: { $0.value == downloadTask })?.key {
            Task { @MainActor in
                downloadStates[episodeKey] = .downloading(progress: progress)
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error else { return }
        
        // Find which episode this belongs to
        if let episodeKey = activeDownloads.first(where: { $0.value == task })?.key {
            Task { @MainActor in
                downloadStates[episodeKey] = .failed(error: error.localizedDescription)
                activeDownloads.removeValue(forKey: episodeKey)
                logger.error("Download failed: \(error.localizedDescription)")
            }
        }
    }
}
