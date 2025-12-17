//
//  PodcastServiceError.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/12/17.
//


import FeedKit
import Foundation
internal import XMLKit

public enum PodcastServiceError: Error, LocalizedError {
    case invalidURL
    case notRSS
    case parsingFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "The URL is malformed."
        case .notRSS: return "The feed is not an RSS feed."
        case .parsingFailed(let e): return "Parsing failed: \(e.localizedDescription)"
        }
    }
}