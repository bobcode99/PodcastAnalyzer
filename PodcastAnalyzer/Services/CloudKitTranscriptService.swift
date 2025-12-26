//
//  CloudKitTranscriptService.swift
//  PodcastAnalyzer
//
//  Created by Claude Code
//  Service for managing shared transcripts in CloudKit
//

import Foundation
import CloudKit
import os.log

private let logger = Logger(subsystem: "com.podcastanalyzer", category: "CloudKitTranscriptService")

/// Service for sharing transcripts via CloudKit public database
actor CloudKitTranscriptService {

    // MARK: - Properties

    /// CloudKit container
    private let container: CKContainer

    /// Public database for shared transcripts
    private let publicDatabase: CKDatabase

    /// User defaults key for storing stats
    private let statsKey = "CloudKitTranscriptStats"

    /// Statistics tracker
    private var stats: CloudKitTranscriptStats

    // MARK: - Initialization

    init(containerIdentifier: String = "iCloud.com.podcastanalyzer") {
        self.container = CKContainer(identifier: containerIdentifier)
        self.publicDatabase = container.publicCloudDatabase

        // Load stats
        if let data = UserDefaults.standard.data(forKey: statsKey),
           let loadedStats = try? JSONDecoder().decode(CloudKitTranscriptStats.self, from: data) {
            self.stats = loadedStats
        } else {
            self.stats = CloudKitTranscriptStats()
        }
    }

    // MARK: - Availability Checking

    /// Check if CloudKit is available and user is signed in
    func checkAvailability() async -> CloudKitAvailability {
        do {
            let status = try await container.accountStatus()

            switch status {
            case .available:
                return .available

            case .noAccount:
                return .unavailable(reason: "No iCloud account. Sign in to Settings → [Your Name] → iCloud.")

            case .restricted:
                return .unavailable(reason: "iCloud access restricted. Check Settings → Screen Time.")

            case .couldNotDetermine:
                return .unavailable(reason: "Could not determine iCloud status. Please try again.")

            case .temporarilyUnavailable:
                return .unavailable(reason: "iCloud temporarily unavailable. Please try again later.")

            @unknown default:
                return .unavailable(reason: "Unknown iCloud status.")
            }
        } catch {
            logger.error("Failed to check CloudKit availability: \(error.localizedDescription)")
            return .unavailable(reason: "Error checking iCloud: \(error.localizedDescription)")
        }
    }

    /// Simple boolean check
    var isAvailable: Bool {
        get async {
            await checkAvailability().isAvailable
        }
    }

    // MARK: - Query Operations

    /// Check if transcript exists in CloudKit for given episode
    /// - Parameter episodeAudioURL: Unique episode identifier
    /// - Returns: Shared transcript if found, nil otherwise
    func findTranscript(forEpisodeURL episodeAudioURL: String) async throws -> SharedTranscript? {
        logger.info("Searching for transcript: \(episodeAudioURL)")

        let predicate = NSPredicate(format: "episodeAudioURL == %@", episodeAudioURL)
        let query = CKQuery(recordType: CloudKitRecordType.sharedTranscript, predicate: predicate)

        // Sort by creation date (newest first)
        query.sortDescriptors = [NSSortDescriptor(key: "createdDate", ascending: false)]

        do {
            let results = try await publicDatabase.records(matching: query, desiredKeys: nil, resultsLimit: 1)

            // Extract first matching record
            for (_, result) in results.matchResults {
                switch result {
                case .success(let record):
                    if let transcript = SharedTranscript(record: record) {
                        logger.info("Found transcript in CloudKit: \(transcript.episodeTitle)")
                        return transcript
                    }
                case .failure(let error):
                    logger.error("Failed to fetch record: \(error.localizedDescription)")
                }
            }

            logger.info("No transcript found in CloudKit for: \(episodeAudioURL)")
            return nil
        } catch {
            logger.error("CloudKit query failed: \(error.localizedDescription)")
            throw CloudKitError.queryFailed(error.localizedDescription)
        }
    }

    /// Search for transcripts matching podcast title
    /// - Parameter podcastTitle: Podcast name
    /// - Returns: Array of shared transcripts
    func findTranscripts(forPodcast podcastTitle: String) async throws -> [SharedTranscript] {
        let predicate = NSPredicate(format: "podcastTitle == %@", podcastTitle)
        let query = CKQuery(recordType: CloudKitRecordType.sharedTranscript, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "createdDate", ascending: false)]

        var transcripts: [SharedTranscript] = []

        do {
            let results = try await publicDatabase.records(matching: query, desiredKeys: nil, resultsLimit: 100)

            for (_, result) in results.matchResults {
                if case .success(let record) = result,
                   let transcript = SharedTranscript(record: record) {
                    transcripts.append(transcript)
                }
            }

            logger.info("Found \(transcripts.count) transcripts for podcast: \(podcastTitle)")
            return transcripts
        } catch {
            logger.error("Failed to query podcast transcripts: \(error.localizedDescription)")
            throw CloudKitError.queryFailed(error.localizedDescription)
        }
    }

    // MARK: - Download Operations

    /// Download transcript from CloudKit
    /// - Parameter transcript: Shared transcript metadata
    /// - Returns: Progress stream with final content
    func downloadTranscript(_ transcript: SharedTranscript) -> AsyncThrowingStream<DownloadProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    logger.info("Downloading transcript: \(transcript.episodeTitle)")

                    // Simulate progress (CloudKit doesn't provide granular progress for record fetch)
                    continuation.yield(DownloadProgress(progress: 0.3, content: nil))

                    // Fetch the full record again to ensure we have latest content
                    let record = try await publicDatabase.record(for: transcript.recordID)

                    continuation.yield(DownloadProgress(progress: 0.7, content: nil))

                    guard let updatedTranscript = SharedTranscript(record: record) else {
                        throw CloudKitError.invalidRecord
                    }

                    // Increment download count
                    await incrementDownloadCount(recordID: transcript.recordID)

                    // Update stats
                    await recordDownload(fileSize: updatedTranscript.fileSize)

                    continuation.yield(DownloadProgress(progress: 1.0, content: updatedTranscript.transcriptContent))
                    continuation.finish()

                    logger.info("Download completed: \(updatedTranscript.fileSize) bytes")
                } catch {
                    logger.error("Download failed: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Increment download count for a transcript (fire and forget)
    private func incrementDownloadCount(recordID: CKRecord.ID) async {
        do {
            let record = try await publicDatabase.record(for: recordID)
            let currentCount = record["downloadCount"] as? Int ?? 0
            record["downloadCount"] = currentCount + 1

            _ = try await publicDatabase.save(record)
            logger.info("Incremented download count to \(currentCount + 1)")
        } catch {
            logger.warning("Failed to increment download count: \(error.localizedDescription)")
            // Don't throw - this is non-critical
        }
    }

    // MARK: - Upload Operations

    /// Upload transcript to CloudKit
    /// - Parameter transcript: Transcript to upload
    /// - Returns: Progress stream
    func uploadTranscript(_ transcript: SharedTranscript) -> AsyncThrowingStream<UploadProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    logger.info("Uploading transcript: \(transcript.episodeTitle), size: \(transcript.fileSize) bytes")

                    continuation.yield(UploadProgress(progress: 0.2))

                    // Check if transcript already exists
                    if let existing = try await findTranscript(forEpisodeURL: transcript.episodeAudioURL) {
                        logger.info("Transcript already exists in CloudKit: \(existing.recordID)")

                        // Optionally update if newer or different
                        if existing.createdDate < transcript.createdDate {
                            logger.info("Updating existing transcript with newer version")
                            // Continue with upload to update
                        } else {
                            // Already exists and is current
                            continuation.yield(UploadProgress(progress: 1.0, recordID: existing.recordID))
                            continuation.finish()
                            return
                        }
                    }

                    continuation.yield(UploadProgress(progress: 0.5))

                    // Save to CloudKit
                    let record = transcript.toRecord()
                    let savedRecord = try await publicDatabase.save(record)

                    // Update stats
                    await recordUpload(fileSize: transcript.fileSize)

                    continuation.yield(UploadProgress(progress: 1.0, recordID: savedRecord.recordID))
                    continuation.finish()

                    logger.info("Upload completed: \(savedRecord.recordID)")
                } catch {
                    logger.error("Upload failed: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Delete transcript from CloudKit (only if user is creator)
    /// - Parameter recordID: CloudKit record ID
    func deleteTranscript(recordID: CKRecord.ID) async throws {
        do {
            _ = try await publicDatabase.deleteRecord(withID: recordID)
            logger.info("Deleted transcript: \(recordID)")
        } catch {
            logger.error("Failed to delete transcript: \(error.localizedDescription)")
            throw CloudKitError.deleteFailed(error.localizedDescription)
        }
    }

    // MARK: - Statistics

    /// Get current statistics
    func getStats() -> CloudKitTranscriptStats {
        stats
    }

    /// Record a download in stats
    private func recordDownload(fileSize: Int) {
        stats.recordDownload(fileSize: fileSize)
        saveStats()
    }

    /// Record an upload in stats
    private func recordUpload(fileSize: Int) {
        stats.recordUpload(fileSize: fileSize)
        saveStats()
    }

    /// Reset statistics
    func resetStats() {
        stats = CloudKitTranscriptStats()
        saveStats()
    }

    /// Save stats to UserDefaults
    private func saveStats() {
        if let data = try? JSONEncoder().encode(stats) {
            UserDefaults.standard.set(data, forKey: statsKey)
        }
    }

    // MARK: - Batch Operations

    /// Download multiple transcripts
    /// - Parameter episodes: Array of episode audio URLs
    /// - Returns: Dictionary mapping episode URL to transcript content
    func batchDownload(episodeURLs: [String]) async throws -> [String: String] {
        var results: [String: String] = [:]

        // Process in parallel (limit concurrency to avoid rate limits)
        try await withThrowingTaskGroup(of: (String, String?).self) { group in
            for url in episodeURLs {
                group.addTask {
                    if let transcript = try await self.findTranscript(forEpisodeURL: url) {
                        // Download content
                        var content: String?
                        for try await progress in self.downloadTranscript(transcript) {
                            if progress.progress == 1.0, let finalContent = progress.content {
                                content = finalContent
                            }
                        }
                        return (url, content)
                    }
                    return (url, nil)
                }
            }

            for try await (url, content) in group {
                if let content = content {
                    results[url] = content
                }
            }
        }

        return results
    }
}

// MARK: - Supporting Types

/// CloudKit availability status
enum CloudKitAvailability {
    case available
    case unavailable(reason: String)

    var isAvailable: Bool {
        if case .available = self {
            return true
        }
        return false
    }

    var message: String? {
        if case .unavailable(let reason) = self {
            return reason
        }
        return nil
    }
}

/// Download progress
struct DownloadProgress {
    let progress: Double        // 0.0 to 1.0
    let content: String?        // Available when progress = 1.0
}

/// Upload progress
struct UploadProgress {
    let progress: Double        // 0.0 to 1.0
    let recordID: CKRecord.ID?  // Available when progress = 1.0
}

/// CloudKit errors
enum CloudKitError: LocalizedError {
    case queryFailed(String)
    case uploadFailed(String)
    case downloadFailed(String)
    case deleteFailed(String)
    case invalidRecord
    case notAvailable(String)

    var errorDescription: String? {
        switch self {
        case .queryFailed(let msg):
            return "Query failed: \(msg)"
        case .uploadFailed(let msg):
            return "Upload failed: \(msg)"
        case .downloadFailed(let msg):
            return "Download failed: \(msg)"
        case .deleteFailed(let msg):
            return "Delete failed: \(msg)"
        case .invalidRecord:
            return "Invalid CloudKit record"
        case .notAvailable(let msg):
            return "CloudKit not available: \(msg)"
        }
    }
}
