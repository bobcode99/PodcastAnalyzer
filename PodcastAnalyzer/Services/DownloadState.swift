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

    // Store original URLs to get proper file extensions
    private var originalURLs: [String: URL] = [:]

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
        // Note: We can't restore state here because FileStorageManager is an actor
        // State will be checked lazily when getDownloadState is called
    }

    // MARK: - State Restoration

    /// Synchronously checks if audio file exists on disk
    /// Returns the path if found, nil otherwise
    private func checkAudioFileExistsSynchronously(episodeTitle: String, podcastTitle: String) -> String? {
        let fm = FileManager.default
        let libraryDir = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let audioDir = libraryDir.appendingPathComponent("Audio", isDirectory: true)

        // Sanitize filename same way as FileStorageManager
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        let baseFileName = "\(podcastTitle)_\(episodeTitle)"
            .components(separatedBy: invalidCharacters)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespaces)

        let possibleExtensions = ["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus"]

        for ext in possibleExtensions {
            let path = audioDir.appendingPathComponent("\(baseFileName).\(ext)")
            if fm.fileExists(atPath: path.path) {
                return path.path
            }
        }
        return nil
    }

    /// Checks if a file exists on disk and updates state accordingly
    private func checkAndRestoreState(episodeTitle: String, podcastTitle: String) {
        let episodeKey = makeKey(episode: episodeTitle, podcast: podcastTitle)

        // Only check if we don't already have a state
        guard downloadStates[episodeKey] == nil || downloadStates[episodeKey] == .notDownloaded else {
            return
        }

        // Try synchronous check first for immediate response
        if let path = checkAudioFileExistsSynchronously(episodeTitle: episodeTitle, podcastTitle: podcastTitle) {
            downloadStates[episodeKey] = .downloaded(localPath: path)
            return
        }

        // Fallback to async check
        Task {
            let exists = await fileStorage.audioFileExists(for: episodeTitle, podcastTitle: podcastTitle)
            if exists {
                let path = await fileStorage.audioFilePath(for: episodeTitle, podcastTitle: podcastTitle)
                await MainActor.run {
                    downloadStates[episodeKey] = .downloaded(localPath: path.path)
                }
            }
        }
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
        originalURLs[episodeKey] = url  // Store original URL for file extension
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

        // If we don't have a state, check disk to restore it
        // Use DispatchQueue.main.async to avoid publishing during view updates
        if downloadStates[episodeKey] == nil {
            // Do synchronous check only, defer async check
            if let path = checkAudioFileExistsSynchronously(episodeTitle: episodeTitle, podcastTitle: podcastTitle) {
                // Schedule the state update for next run loop to avoid "publishing during view update"
                DispatchQueue.main.async { [weak self] in
                    self?.downloadStates[episodeKey] = .downloaded(localPath: path)
                }
                return .downloaded(localPath: path)
            }
        }

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
        // Find which episode this belongs to
        let episodeKey = activeDownloads.first(where: { $0.value == downloadTask })?.key
        guard let episodeKey = episodeKey else { return }

        let components = episodeKey.split(separator: "|")
        guard components.count == 2 else { return }

        let podcastTitle = String(components[0])
        let episodeTitle = String(components[1])

        // Get the original URL for proper file extension
        let originalURL = originalURLs[episodeKey] ?? downloadTask.originalRequest?.url
        let fileExtension = originalURL?.pathExtension ?? "mp3"

        // CRITICAL: URLSession will delete the temp file as soon as this method returns!
        // We must copy it synchronously to our own location first
        let tempDirectory = FileManager.default.temporaryDirectory
        let ourTempFile = tempDirectory.appendingPathComponent(UUID().uuidString + ".\(fileExtension)")

        do {
            // Copy the file synchronously before delegate returns
            try FileManager.default.copyItem(at: location, to: ourTempFile)
            logger.info("Copied download to temp location: \(ourTempFile.lastPathComponent)")

            // Now move it to final destination asynchronously
            Task {
                do {
                    let destinationURL = try await fileStorage.saveAudioFile(
                        from: ourTempFile,
                        episodeTitle: episodeTitle,
                        podcastTitle: podcastTitle
                    )

                    // Clean up our temp file (may already be moved)
                    try? FileManager.default.removeItem(at: ourTempFile)

                    await MainActor.run {
                        self.downloadStates[episodeKey] = .downloaded(localPath: destinationURL.path)
                        self.activeDownloads.removeValue(forKey: episodeKey)
                        self.originalURLs.removeValue(forKey: episodeKey)
                        self.logger.info("Download completed: \(episodeTitle)")
                    }
                } catch {
                    // Clean up our temp file on error
                    try? FileManager.default.removeItem(at: ourTempFile)

                    await MainActor.run {
                        self.downloadStates[episodeKey] = .failed(error: error.localizedDescription)
                        self.activeDownloads.removeValue(forKey: episodeKey)
                        self.originalURLs.removeValue(forKey: episodeKey)
                        self.logger.error("Download save failed: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            // Failed to copy to our temp location
            logger.error("Failed to copy download to temp: \(error.localizedDescription)")
            Task { @MainActor in
                self.downloadStates[episodeKey] = .failed(error: "Failed to copy temp file: \(error.localizedDescription)")
                self.activeDownloads.removeValue(forKey: episodeKey)
                self.originalURLs.removeValue(forKey: episodeKey)
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
