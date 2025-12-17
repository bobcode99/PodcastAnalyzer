//
//  FileStorageError.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/12/17.
//


//
//  FileStorageManager.swift
//  PodcastAnalyzer
//
//  Manages file storage for podcast audio, images, and captions
//

import Foundation
import os.log

enum FileStorageError: LocalizedError {
    case invalidURL
    case fileNotFound
    case saveFailed(Error)
    case deleteFailed(Error)
    case directoryCreationFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid file URL"
        case .fileNotFound:
            return "File not found"
        case .saveFailed(let error):
            return "Failed to save file: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete file: \(error.localizedDescription)"
        case .directoryCreationFailed(let error):
            return "Failed to create directory: \(error.localizedDescription)"
        }
    }
}

actor FileStorageManager {
    static let shared = FileStorageManager()
    
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.podcast.analyzer", category: "FileStorage")
    
    // MARK: - Directory Structure
    
    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private var libraryDirectory: URL {
        fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
    }
    
    // Audio files in Library (app-managed, won't appear in Files app)
    private var audioDirectory: URL {
        libraryDirectory.appendingPathComponent("Audio", isDirectory: true)
    }
    
    // Captions/SRT files in Documents (user can access via Files app)
    private var captionsDirectory: URL {
        documentsDirectory.appendingPathComponent("Captions", isDirectory: true)
    }
    
    // Temporary downloads
    private var tempDirectory: URL {
        fileManager.temporaryDirectory.appendingPathComponent("Downloads", isDirectory: true)
    }
    
    private init() {
        Task {
            await createDirectories()
        }
    }
    
    // MARK: - Directory Management
    
    private func createDirectories() {
        let directories = [audioDirectory, captionsDirectory, tempDirectory]
        
        for directory in directories {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                logger.info("Created directory: \(directory.path)")
            } catch {
                logger.error("Failed to create directory \(directory.path): \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Audio File Management
    
    /// Generates a unique filename for an episode's audio file
    func audioFileName(for episodeTitle: String, podcastTitle: String) -> String {
        let sanitized = sanitizeFileName("\(podcastTitle)_\(episodeTitle)")
        return "\(sanitized).m4a"
    }
    
    /// Gets the full path for an audio file
    func audioFilePath(for episodeTitle: String, podcastTitle: String) -> URL {
        audioDirectory.appendingPathComponent(audioFileName(for: episodeTitle, podcastTitle: podcastTitle))
    }
    
    /// Checks if audio file exists
    func audioFileExists(for episodeTitle: String, podcastTitle: String) -> Bool {
        let path = audioFilePath(for: episodeTitle, podcastTitle: podcastTitle)
        return fileManager.fileExists(atPath: path.path)
    }
    
    /// Saves downloaded audio file
    func saveAudioFile(from sourceURL: URL, episodeTitle: String, podcastTitle: String) throws -> URL {
        // Ensure audio directory exists
        if !fileManager.fileExists(atPath: self.audioDirectory.path) {
            do {
                try fileManager.createDirectory(at: self.audioDirectory, withIntermediateDirectories: true)
                logger.info("Created audio directory: \(self.audioDirectory.path)")
            } catch {
                logger.error("Failed to create audio directory: \(error.localizedDescription)")
                throw FileStorageError.directoryCreationFailed(error)
            }
        }

        let destinationURL = audioFilePath(for: episodeTitle, podcastTitle: podcastTitle)

        // Remove existing file if present
        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: destinationURL)
        }

        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            logger.info("Saved audio file: \(destinationURL.lastPathComponent)")
            return destinationURL
        } catch {
            logger.error("Failed to save audio: \(error.localizedDescription)")
            throw FileStorageError.saveFailed(error)
        }
    }
    
    /// Deletes audio file
    func deleteAudioFile(for episodeTitle: String, podcastTitle: String) throws {
        let path = audioFilePath(for: episodeTitle, podcastTitle: podcastTitle)
        
        guard fileManager.fileExists(atPath: path.path) else {
            throw FileStorageError.fileNotFound
        }
        
        do {
            try fileManager.removeItem(at: path)
            logger.info("Deleted audio file: \(path.lastPathComponent)")
        } catch {
            logger.error("Failed to delete audio: \(error.localizedDescription)")
            throw FileStorageError.deleteFailed(error)
        }
    }
    
    // MARK: - Caption File Management
    
    /// Generates filename for captions
    func captionFileName(for episodeTitle: String, podcastTitle: String) -> String {
        let sanitized = sanitizeFileName("\(podcastTitle)_\(episodeTitle)")
        return "\(sanitized).srt"
    }
    
    /// Gets the full path for a caption file
    func captionFilePath(for episodeTitle: String, podcastTitle: String) -> URL {
        captionsDirectory.appendingPathComponent(captionFileName(for: episodeTitle, podcastTitle: podcastTitle))
    }
    
    /// Checks if caption file exists
    func captionFileExists(for episodeTitle: String, podcastTitle: String) -> Bool {
        let path = captionFilePath(for: episodeTitle, podcastTitle: podcastTitle)
        return fileManager.fileExists(atPath: path.path)
    }
    
    /// Saves caption/SRT file
    func saveCaptionFile(content: String, episodeTitle: String, podcastTitle: String) throws -> URL {
        // Ensure captions directory exists
        if !fileManager.fileExists(atPath: self.captionsDirectory.path) {
            do {
                try fileManager.createDirectory(at: self.captionsDirectory, withIntermediateDirectories: true)
                logger.info("Created captions directory: \(self.captionsDirectory.path)")
            } catch {
                logger.error("Failed to create captions directory: \(error.localizedDescription)")
                throw FileStorageError.directoryCreationFailed(error)
            }
        }

        let destinationURL = captionFilePath(for: episodeTitle, podcastTitle: podcastTitle)

        do {
            try content.write(to: destinationURL, atomically: true, encoding: .utf8)
            logger.info("Saved caption file: \(destinationURL.lastPathComponent)")
            return destinationURL
        } catch {
            logger.error("Failed to save caption: \(error.localizedDescription)")
            throw FileStorageError.saveFailed(error)
        }
    }
    
    /// Loads caption file content
    func loadCaptionFile(for episodeTitle: String, podcastTitle: String) throws -> String {
        let path = captionFilePath(for: episodeTitle, podcastTitle: podcastTitle)
        
        guard fileManager.fileExists(atPath: path.path) else {
            throw FileStorageError.fileNotFound
        }
        
        do {
            return try String(contentsOf: path, encoding: .utf8)
        } catch {
            logger.error("Failed to load caption: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Deletes caption file
    func deleteCaptionFile(for episodeTitle: String, podcastTitle: String) throws {
        let path = captionFilePath(for: episodeTitle, podcastTitle: podcastTitle)
        
        guard fileManager.fileExists(atPath: path.path) else {
            throw FileStorageError.fileNotFound
        }
        
        do {
            try fileManager.removeItem(at: path)
            logger.info("Deleted caption file: \(path.lastPathComponent)")
        } catch {
            logger.error("Failed to delete caption: \(error.localizedDescription)")
            throw FileStorageError.deleteFailed(error)
        }
    }
    
    // MARK: - Storage Info
    
    /// Gets total size of stored audio files
    func getTotalAudioSize() -> Int64 {
        guard let enumerator = fileManager.enumerator(at: audioDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = resourceValues.fileSize else {
                continue
            }
            totalSize += Int64(fileSize)
        }
        
        return totalSize
    }
    
    /// Formats bytes to human-readable string
    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - Helpers
    
    private func sanitizeFileName(_ fileName: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return fileName
            .components(separatedBy: invalidCharacters)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespaces)
    }
}