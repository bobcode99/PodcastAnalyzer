//
//  CloudKitTranscriptModels.swift
//  PodcastAnalyzer
//
//  Created by Claude Code
//  CloudKit models for shared transcript cache
//

import Foundation
import CloudKit

// MARK: - CloudKit Record Types

/// Record type names for CloudKit
enum CloudKitRecordType {
    static let sharedTranscript = "SharedTranscript"
}

// MARK: - Shared Transcript Model

/// Represents a transcript stored in CloudKit public database
struct SharedTranscript {

    // MARK: - Properties

    /// Unique identifier for this transcript
    let recordID: CKRecord.ID

    /// Episode identifier (audio URL serves as unique ID)
    let episodeAudioURL: String

    /// Episode title for display
    let episodeTitle: String

    /// Podcast title for display
    let podcastTitle: String

    /// Language of the transcript
    let language: String

    /// SRT file content
    let transcriptContent: String

    /// Audio duration in seconds (for validation)
    let audioDuration: TimeInterval

    /// When this transcript was created
    let createdDate: Date

    /// User who created this transcript (anonymized)
    let creatorID: String

    /// Number of times this transcript has been downloaded by other users
    var downloadCount: Int

    /// Version of transcription engine used (for future compatibility)
    let transcriptionVersion: String

    /// File size in bytes
    var fileSize: Int {
        transcriptContent.data(using: .utf8)?.count ?? 0
    }

    // MARK: - CloudKit Conversion

    /// Initialize from CloudKit record
    init?(record: CKRecord) {
        guard let episodeAudioURL = record["episodeAudioURL"] as? String,
              let episodeTitle = record["episodeTitle"] as? String,
              let podcastTitle = record["podcastTitle"] as? String,
              let language = record["language"] as? String,
              let transcriptContent = record["transcriptContent"] as? String,
              let audioDuration = record["audioDuration"] as? Double,
              let createdDate = record["createdDate"] as? Date,
              let creatorID = record["creatorID"] as? String,
              let transcriptionVersion = record["transcriptionVersion"] as? String
        else {
            return nil
        }

        self.recordID = record.recordID
        self.episodeAudioURL = episodeAudioURL
        self.episodeTitle = episodeTitle
        self.podcastTitle = podcastTitle
        self.language = language
        self.transcriptContent = transcriptContent
        self.audioDuration = audioDuration
        self.createdDate = createdDate
        self.creatorID = creatorID
        self.downloadCount = record["downloadCount"] as? Int ?? 0
        self.transcriptionVersion = transcriptionVersion
    }

    /// Convert to CloudKit record
    func toRecord() -> CKRecord {
        let record = CKRecord(recordType: CloudKitRecordType.sharedTranscript, recordID: recordID)

        record["episodeAudioURL"] = episodeAudioURL
        record["episodeTitle"] = episodeTitle
        record["podcastTitle"] = podcastTitle
        record["language"] = language
        record["transcriptContent"] = transcriptContent
        record["audioDuration"] = audioDuration
        record["createdDate"] = createdDate
        record["creatorID"] = creatorID
        record["downloadCount"] = downloadCount
        record["transcriptionVersion"] = transcriptionVersion

        return record
    }

    /// Initialize for new upload
    init(
        episodeAudioURL: String,
        episodeTitle: String,
        podcastTitle: String,
        language: String,
        transcriptContent: String,
        audioDuration: TimeInterval
    ) {
        // Use episodeAudioURL as record name for uniqueness
        let recordName = episodeAudioURL.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        self.recordID = CKRecord.ID(recordName: recordName)

        self.episodeAudioURL = episodeAudioURL
        self.episodeTitle = episodeTitle
        self.podcastTitle = podcastTitle
        self.language = language
        self.transcriptContent = transcriptContent
        self.audioDuration = audioDuration
        self.createdDate = Date()
        self.creatorID = "anonymous" // Privacy: don't expose actual user ID
        self.downloadCount = 0
        self.transcriptionVersion = "1.0" // Update when transcription engine changes
    }
}

// MARK: - Transcript Cache Metadata

/// Metadata about cached transcripts
struct TranscriptCacheMetadata: Codable {
    /// Episode audio URL (unique identifier)
    let episodeAudioURL: String

    /// When transcript was cached locally
    let cachedDate: Date

    /// Source of transcript
    let source: TranscriptSource

    /// CloudKit record ID if from cloud
    let cloudKitRecordID: String?

    /// Language
    let language: String

    /// File path to local SRT file
    let localFilePath: String?

    enum TranscriptSource: String, Codable {
        case localGeneration = "local"      // Generated on this device
        case cloudKitDownload = "cloudkit"  // Downloaded from CloudKit
        case manual = "manual"              // Manually imported
    }
}

// MARK: - CloudKit Sync Status

/// Represents CloudKit sync status for UI
enum CloudKitSyncStatus: Equatable {
    case disabled                           // User disabled CloudKit sync
    case notAvailable                       // CloudKit not available
    case idle                               // Ready but not syncing
    case checking(episodeTitle: String)     // Checking if transcript exists
    case downloading(progress: Double)      // Downloading transcript
    case uploading(progress: Double)        // Uploading transcript
    case completed(source: TranscriptCacheMetadata.TranscriptSource)
    case failed(error: String)

    var isActive: Bool {
        switch self {
        case .checking, .downloading, .uploading:
            return true
        default:
            return false
        }
    }
}

// MARK: - CloudKit Statistics

/// Statistics about CloudKit transcript sharing
struct CloudKitTranscriptStats: Codable {
    /// Total transcripts downloaded from CloudKit
    var totalDownloaded: Int = 0

    /// Total transcripts uploaded to CloudKit
    var totalUploaded: Int = 0

    /// Total time saved by using cached transcripts (estimated seconds)
    var timeSavedSeconds: TimeInterval = 0

    /// Total data downloaded (bytes)
    var dataDownloaded: Int = 0

    /// Total data uploaded (bytes)
    var dataUploaded: Int = 0

    /// Last sync date
    var lastSyncDate: Date?

    /// Estimated time saved per episode (average)
    static let estimatedTimePerEpisode: TimeInterval = 120 // 2 minutes average

    mutating func recordDownload(fileSize: Int) {
        totalDownloaded += 1
        dataDownloaded += fileSize
        timeSavedSeconds += Self.estimatedTimePerEpisode
        lastSyncDate = Date()
    }

    mutating func recordUpload(fileSize: Int) {
        totalUploaded += 1
        dataUploaded += fileSize
        lastSyncDate = Date()
    }

    var formattedTimeSaved: String {
        let minutes = Int(timeSavedSeconds / 60)
        if minutes < 60 {
            return "\(minutes) minutes"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
    }

    var formattedDataDownloaded: String {
        ByteCountFormatter.string(fromByteCount: Int64(dataDownloaded), countStyle: .file)
    }

    var formattedDataUploaded: String {
        ByteCountFormatter.string(fromByteCount: Int64(dataUploaded), countStyle: .file)
    }
}
