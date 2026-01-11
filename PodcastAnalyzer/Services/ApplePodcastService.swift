import Foundation

struct SearchResponse: Decodable {
    let resultCount: Int
    let results: [Podcast]
}

struct EpisodeSearchResponse: Decodable {
    let resultCount: Int
    let results: [Episode]
}
// Podcast struct - unchanged, from search with direct fields
struct Podcast: Decodable, Identifiable, Sendable {
    var id: UUID { UUID() }  // ← computed, no warning
    let collectionId: Int  // Like @Id in JPA
    let collectionName: String
    let artistName: String
    let artworkUrl100: String?  // Optional, like String in Java (nullable)
    let feedUrl: String?  // RSS feed URL
    let contentAdvisoryRating: String?  // e.g., "Explicit"
    let genres: [String]?  // Like List<String> in Java
}
/// Genre object from Apple API
struct EpisodeGenre: Decodable, Sendable {
    let name: String
    let id: String
}

struct Episode: Decodable, Identifiable, Sendable {
    var id: UUID { UUID() }  // ← computed, no warning
    let wrapperType: String?
    let kind: String?

    let trackId: Int?  // Optional now; nil from RSS
    let trackName: String
    let description: String?
    let shortDescription: String?

    let releaseDate: String?
    let trackTimeMillis: Int?

    let contentAdvisoryRating: String?

    let trackViewUrl: String?  // Apple episode link
    let previewUrl: String?
    let episodeUrl: String?  // Audio URL

    let artworkUrl600: String?
    let artworkUrl160: String?

    let country: String?
    let language: String?

    let genres: [EpisodeGenre]?  // Fixed: Array of genre objects, not strings

    let collectionId: Int?
    let collectionName: String?

    let episodeGuid: String?
    let closedCaptioning: String?
    let episodeContentType: String?
    let episodeFileExtension: String?
}
// MARK: - Apple RSS Top Podcasts Response Models

struct AppleRSSFeedResponse: Decodable {
    let feed: AppleRSSFeed
}

struct AppleRSSFeed: Decodable {
    let title: String
    let country: String
    let updated: String
    let results: [AppleRSSPodcast]
}

struct AppleRSSPodcast: Decodable, Identifiable {
    let id: String
    let artistName: String
    let name: String
    let artworkUrl100: String
    let url: String  // iTunes link
    let genres: [AppleRSSGenre]?
    let contentAdvisoryRating: String?
}

struct AppleRSSGenre: Decodable {
    let genreId: String
    let name: String
    let url: String
}

// MARK: - Apple Podcast Service (Swift 6 async/await)

class ApplePodcastService: Sendable {

    private let baseURL = "https://itunes.apple.com"
    private let rssBaseURL = Constants.appleRSSBaseURL

    // MARK: - Top Podcasts from Apple RSS Marketing API

    /// Fetches top podcasts for a given region
    /// - Parameters:
    ///   - region: Country code (e.g., "us", "tw", "jp")
    ///   - limit: Number of podcasts to fetch (max 200)
    /// - Returns: Array of top podcasts
    func fetchTopPodcasts(region: String = "us", limit: Int = 10) async throws -> [AppleRSSPodcast] {
        let urlString = "\(rssBaseURL)/\(region)/podcasts/top/\(limit)/podcasts.json"

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(AppleRSSFeedResponse.self, from: data)
        return response.feed.results
    }

    /// Looks up a podcast's RSS feed URL from its collection ID
    func lookupPodcast(collectionId: String) async throws -> Podcast? {
        let urlString = "\(baseURL)/lookup?id=\(collectionId)&entity=podcast"

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        return response.results.first
    }

    /// Finds the Apple Podcasts episode link by matching the episode GUID
    /// - Parameters:
    ///   - episodeTitle: Episode title for search query
    ///   - episodeGuid: The RSS feed GUID to match against Apple's episodeGuid
    ///   - country: Country code for the search (default: "tw")
    /// - Returns: The Apple episode URL or nil
    func getAppleEpisodeLink(
        episodeTitle: String,
        episodeGuid: String?,
        country: String = "tw"
    ) async throws -> String? {
        let encoded = episodeTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://itunes.apple.com/search?term=\(encoded)&entity=podcastEpisode&limit=15&country=\(country)"

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(EpisodeSearchResponse.self, from: data)

        // Priority 1: Match by episodeGuid
        if let guid = episodeGuid,
           let match = response.results.first(where: { $0.episodeGuid == guid }) {
            return match.trackViewUrl
        }
        // Fallback: return first result
        return response.results.first?.trackViewUrl
    }

    // Search podcasts
    func searchPodcasts(term: String, limit: Int = 20) async throws -> [Podcast] {
        let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString =
            "\(baseURL)/search?media=podcast&entity=podcast&term=\(encoded)&limit=\(limit)"

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        return response.results
    }

    // Fetch episodes from Apple (fixed to handle only podcast return without error)
    func fetchEpisodes(for collectionId: Int, limit: Int = 200) async throws -> [Episode] {
        let urlString = "\(baseURL)/lookup?id=\(collectionId)&entity=podcastEpisode&limit=\(limit)"

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        // Parse as dict first (like ObjectMapper in Java to avoid direct decode errors)
        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        guard let results = json?["results"] as? [[String: Any]] else {
            throw URLError(.badServerResponse)
        }

        var episodes: [Episode] = []
        for item in results.dropFirst() {  // Skip first (podcast); like filtering in a Java stream
            let itemData = try JSONSerialization.data(withJSONObject: item, options: [])
            let episode = try JSONDecoder().decode(Episode.self, from: itemData)
            episodes.append(episode)
        }
        return episodes
    }

    // Fetch episodes from RSS feed (alternative since Apple doesn't return them)
    func fetchEpisodesFromRSS(feedUrl: String, limit: Int = 200) async throws -> [Episode] {
        guard let url = URL(string: feedUrl) else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let parser = RSSParser(data: data)
        let episodes = try parser.parse()
        return Array(episodes.prefix(limit))
    }
}

// MARK: - RSS Parser class (like a custom XML parser service in Java)

class RSSParser: NSObject, XMLParserDelegate {

    private let data: Data
    private var episodes: [Episode] = []

    private var currentElement = ""
    private var currentTitle = ""
    private var currentDescription = ""
    private var currentPubDate = ""
    private var currentDuration = ""
    private var currentEnclosureUrl = ""
    private var currentGuid = ""
    private var language = ""  // From channel <language>

    init(data: Data) {
        self.data = data
    }

    func parse() throws -> [Episode] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        if parser.parse() {
            return episodes
        } else if let error = parser.parserError {
            throw error
        } else {
            throw URLError(.cannotParseResponse)
        }
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        if elementName == "item" {
            currentTitle = ""
            currentDescription = ""
            currentPubDate = ""
            currentDuration = ""
            currentEnclosureUrl = ""
            currentGuid = ""
        } else if elementName == "enclosure" {
            currentEnclosureUrl = attributeDict["url"] ?? ""
        } else if elementName == "itunes:duration" {
            currentDuration = ""
        } else if elementName == "language" {
            language = ""
        } else if elementName == "guid" {
            currentGuid = ""
        } else if elementName == "description" {
            currentDescription = ""
        }  // Add more for other fields if needed
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }

        switch currentElement {
        case "title": currentTitle += trimmed
        case "description": currentDescription += trimmed
        case "pubDate": currentPubDate += trimmed
        case "itunes:duration": currentDuration += trimmed
        case "guid": currentGuid += trimmed
        case "language": language += trimmed
        default: break
        }
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "item" {
            // Parse duration to millis (like string parsing in Java)
            var millis: Int? = nil
            if !currentDuration.isEmpty {
                if let sec = Int(currentDuration) {
                    millis = sec * 1000
                } else {
                    let parts = currentDuration.split(separator: ":")
                    if parts.count == 3, let h = Int(parts[0]), let m = Int(parts[1]),
                        let s = Int(parts[2])
                    {
                        millis = (h * 3600 + m * 60 + s) * 1000
                    } else if parts.count == 2, let m = Int(parts[0]), let s = Int(parts[1]) {
                        millis = (m * 60 + s) * 1000
                    }
                }
            }

            let episode = Episode(
                wrapperType: "podcastEpisode",
                kind: "podcast-episode",
                trackId: nil,  // No Apple ID
                trackName: currentTitle,
                description: currentDescription,
                shortDescription: nil,
                releaseDate: currentPubDate,
                trackTimeMillis: millis,
                contentAdvisoryRating: nil,
                trackViewUrl: nil,  // No Apple link available from RSS
                previewUrl: nil,
                episodeUrl: currentEnclosureUrl,
                artworkUrl600: nil,
                artworkUrl160: nil,
                country: nil,
                language: language,  // From RSS
                genres: nil,
                collectionId: nil,
                collectionName: nil,
                episodeGuid: currentGuid,
                closedCaptioning: nil,
                episodeContentType: nil,
                episodeFileExtension: nil
            )
            episodes.append(episode)
        }
    }
}
