//
//  RSSCacheService.swift
//  PodcastAnalyzer
//
//  Caches RSS feed data to avoid re-downloading the same podcast feed.
//

import Foundation

actor RSSCacheService {
    static let shared = RSSCacheService()

    private let rssService = PodcastRssService()
    private let cacheDirectory: URL
    private let cacheExpiration: TimeInterval = 60 * 30 // 30 minutes
    private let maxMemoryCacheSize = 20 // Max number of podcasts in memory

    // In-memory cache for quick access (LRU-like with size limit)
    private var memoryCache: [String: CachedPodcast] = [:]
    private var cacheAccessOrder: [String] = [] // Track access order for LRU eviction

    private struct CachedPodcast {
        let podcastInfo: PodcastInfo
        let timestamp: Date
    }

    private init() {
        // Create cache directory in Caches folder
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDir.appendingPathComponent("RSSCache", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Fetches podcast info, using cache if available and not expired
    func fetchPodcast(from rssUrl: String, forceRefresh: Bool = false) async throws -> PodcastInfo {
        let cacheKey = makeCacheKey(from: rssUrl)

        // Check memory cache first
        if !forceRefresh, let cached = memoryCache[cacheKey], !isExpired(cached.timestamp) {
            return cached.podcastInfo
        }

        // Check file cache
        if !forceRefresh, let cached = loadFromFileCache(cacheKey: cacheKey) {
            memoryCache[cacheKey] = CachedPodcast(podcastInfo: cached, timestamp: Date())
            return cached
        }

        // Fetch from network
        let podcastInfo = try await rssService.fetchPodcast(from: rssUrl)

        // Save to cache
        saveToCache(podcastInfo: podcastInfo, cacheKey: cacheKey)

        return podcastInfo
    }

    /// Clears the cache for a specific RSS URL
    func clearCache(for rssUrl: String) {
        let cacheKey = makeCacheKey(from: rssUrl)
        memoryCache.removeValue(forKey: cacheKey)
        cacheAccessOrder.removeAll { $0 == cacheKey }

        let fileURL = cacheDirectory.appendingPathComponent("\(cacheKey).json")
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Clears all cached RSS feeds
    func clearAllCache() {
        memoryCache.removeAll()
        cacheAccessOrder.removeAll()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Private Helpers

    private func makeCacheKey(from url: String) -> String {
        // Create a safe filename from URL
        let data = Data(url.utf8)
        return data.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .prefix(100)
            .description
    }

    private func isExpired(_ timestamp: Date) -> Bool {
        Date().timeIntervalSince(timestamp) > cacheExpiration
    }

    private func loadFromFileCache(cacheKey: String) -> PodcastInfo? {
        let fileURL = cacheDirectory.appendingPathComponent("\(cacheKey).json")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        // Check file modification date for expiration
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let modDate = attrs[.modificationDate] as? Date,
           isExpired(modDate) {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }

        guard let data = try? Data(contentsOf: fileURL),
              let cached = try? JSONDecoder().decode(PodcastInfo.self, from: data) else {
            return nil
        }

        return cached
    }

    private func saveToCache(podcastInfo: PodcastInfo, cacheKey: String) {
        // Update access order (move to end if exists, or add)
        cacheAccessOrder.removeAll { $0 == cacheKey }
        cacheAccessOrder.append(cacheKey)

        // Evict oldest entries if over size limit
        while cacheAccessOrder.count > maxMemoryCacheSize {
            if let oldestKey = cacheAccessOrder.first {
                cacheAccessOrder.removeFirst()
                memoryCache.removeValue(forKey: oldestKey)
            }
        }

        // Save to memory
        memoryCache[cacheKey] = CachedPodcast(podcastInfo: podcastInfo, timestamp: Date())

        // Save to file
        let fileURL = cacheDirectory.appendingPathComponent("\(cacheKey).json")
        if let data = try? JSONEncoder().encode(podcastInfo) {
            try? data.write(to: fileURL)
        }
    }
}
