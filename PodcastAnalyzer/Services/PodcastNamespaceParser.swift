//
//  PodcastNamespaceParser.swift
//  PodcastAnalyzer
//
//  Parses Podcasting 2.0 namespace elements from RSS feeds
//  Reference: https://github.com/Podcastindex-org/podcast-namespace
//

import Foundation
import OSLog

/// Information about a podcast transcript from RSS
public struct TranscriptInfo: Sendable, Equatable {
  /// URL to the transcript file
  public let url: String

  /// MIME type of the transcript (e.g., "text/vtt", "application/srt", "text/plain")
  public let type: String

  /// Language of the transcript (optional)
  public let language: String?

  /// Relationship type (e.g., "captions" for closed captions)
  public let rel: String?
}

/// Parser for Podcasting 2.0 namespace elements
/// Extracts podcast:transcript tags from RSS feeds
public struct PodcastNamespaceParser: Sendable {

  public init() {}

  /// Parse RSS data to extract transcript information for each episode
  /// - Parameter data: Raw RSS XML data
  /// - Returns: Dictionary mapping episode GUIDs to their transcript info
  @MainActor
  public func parseTranscripts(from data: Data) -> [String: TranscriptInfo] {
    let parser = TranscriptXMLParser(data: data)
    return parser.parse()
  }
}

// MARK: - XML Parser Implementation

/// Internal XML parser delegate for extracting transcript tags
/// XMLParser calls delegate methods synchronously on the calling thread.
@MainActor
private final class TranscriptXMLParser: NSObject, XMLParserDelegate {

  private let data: Data
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "PodcastNamespaceParser")

  // Current parsing state
  private var currentGuid = ""
  private var currentItemGuid = ""
  private var insideItem = false

  // Results
  private var transcripts: [String: TranscriptInfo] = [:]

  // Temporary storage for current item's transcript
  private var currentItemTranscript: TranscriptInfo?

  init(data: Data) {
    self.data = data
    super.init()
  }

  func parse() -> [String: TranscriptInfo] {
    let parser = XMLParser(data: data)
    parser.delegate = self
    parser.shouldProcessNamespaces = true
    parser.shouldReportNamespacePrefixes = true

    if parser.parse() {
      return transcripts
    } else {
      logger.error("XML parsing failed: \(parser.parserError?.localizedDescription ?? "unknown")")
      return [:]
    }
  }

  // MARK: - XMLParserDelegate

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    // Handle item start
    if elementName == "item" {
      insideItem = true
      currentItemGuid = ""
      currentItemTranscript = nil
    }

    // Handle guid inside item
    if elementName == "guid" && insideItem {
      currentGuid = ""
    }

    // Handle podcast:transcript element
    // The element might come as "transcript" with namespace or "podcast:transcript"
    let isTranscriptElement =
      elementName == "transcript"
      || elementName == "podcast:transcript"
      || (namespaceURI?.contains("podcastindex.org") == true && elementName == "transcript")

    if isTranscriptElement && insideItem {
      // Extract attributes
      // VTT example: <podcast:transcript type="text/vtt" url="https://..." language="en"/>
      if let url = attributeDict["url"], let type = attributeDict["type"] {
        // Prefer VTT or SRT transcripts
        let typeLC = type.lowercased()
        let isPreferredType =
          typeLC.contains("vtt")
          || typeLC.contains("srt")
          || typeLC == "text/vtt"
          || typeLC == "application/srt"

        // Only store if we don't have one yet, or if this is a preferred type
        if currentItemTranscript == nil || isPreferredType {
          currentItemTranscript = TranscriptInfo(
            url: url,
            type: type,
            language: attributeDict["language"],
            rel: attributeDict["rel"]
          )
          logger.debug("Found transcript: type=\(type), url=\(url)")
        }
      }
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty && insideItem {
      currentGuid += trimmed
    }
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    // Store guid when closing guid element
    if elementName == "guid" && insideItem {
      currentItemGuid = currentGuid.trimmingCharacters(in: .whitespacesAndNewlines)
      currentGuid = ""
    }

    // Store transcript when closing item
    if elementName == "item" {
      if let transcript = currentItemTranscript, !currentItemGuid.isEmpty {
        transcripts[currentItemGuid] = transcript
        logger.debug("Stored transcript for guid: \(self.currentItemGuid)")
      }
      insideItem = false
      currentItemGuid = ""
      currentItemTranscript = nil
    }
  }

  func parserDidEndDocument(_ parser: XMLParser) {
    logger.info("Parsed \(self.transcripts.count) transcripts from RSS feed")
  }
}

// MARK: - Convenience Extensions

extension TranscriptInfo {
  /// Check if this is a VTT transcript
  var isVTT: Bool {
    let typeLC = type.lowercased()
    return typeLC.contains("vtt") || typeLC == "text/vtt"
  }

  /// Check if this is an SRT transcript
  var isSRT: Bool {
    let typeLC = type.lowercased()
    return typeLC.contains("srt") || typeLC == "application/srt"
  }

  /// Check if this is a plain text transcript
  var isPlainText: Bool {
    let typeLC = type.lowercased()
    return typeLC == "text/plain"
  }

  /// Get the URL as a URL object
  var urlObject: URL? {
    URL(string: url)
  }
}
