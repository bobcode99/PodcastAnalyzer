import Combine
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

    let trackViewUrl: String?  // Apple episode link; nil from RSS
    let previewUrl: String?
    let episodeUrl: String?  // Audio URL from RSS <enclosure>

    let artworkUrl600: String?
    let artworkUrl160: String?

    let country: String?  // From Apple
    let language: String?  // New: From RSS <language> tag (e.g., "zh-tw")

    let genres: [String]?

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

class ApplePodcastService {

    private let baseURL = "https://itunes.apple.com"
    private let rssBaseURL = Constants.appleRSSBaseURL

    // MARK: - Top Podcasts from Apple RSS Marketing API

    /// Fetches top podcasts for a given region
    /// - Parameters:
    ///   - region: Country code (e.g., "us", "tw", "jp")
    ///   - limit: Number of podcasts to fetch (max 200)
    /// - Returns: Publisher with array of top podcasts
    func fetchTopPodcasts(region: String = "us", limit: Int = 10) -> AnyPublisher<[AppleRSSPodcast], Error> {
        let urlString = "\(rssBaseURL)/\(region)/podcasts/top/\(limit)/podcasts.json"

        guard let url = URL(string: urlString) else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }

        return URLSession.shared.dataTaskPublisher(for: url)
            .map { $0.data }
            .decode(type: AppleRSSFeedResponse.self, decoder: JSONDecoder())
            .map { $0.feed.results }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    /// Looks up a podcast's RSS feed URL from its collection ID
    func lookupPodcast(collectionId: String) -> AnyPublisher<Podcast?, Error> {
        let urlString = "\(baseURL)/lookup?id=\(collectionId)&entity=podcast"

        guard let url = URL(string: urlString) else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }

        return URLSession.shared.dataTaskPublisher(for: url)
            .map { $0.data }
            .decode(type: SearchResponse.self, decoder: JSONDecoder())
            .map { $0.results.first }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    func findAppleEpisodeUrl(
        episodeTitle: String,
        podcastCollectionId: Int,
        country: String = "tw"  // For /tw/ links
    ) -> AnyPublisher<String?, Error> {
        let encodedTitle = episodeTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://itunes.apple.com/search?term=\(encodedTitle)&entity=podcastEpisode&limit=10&country=\(country)"
        
        guard let url = URL(string: urlString) else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }
        
        return URLSession.shared.dataTaskPublisher(for: url)
            .map { $0.data }
            .decode(type: EpisodeSearchResponse.self, decoder: JSONDecoder())
            .map { response in
                // If collectionId is 0, just return the first result
                if podcastCollectionId == 0 {
                    return response.results.first?.trackViewUrl
                }
                // Otherwise, filter by podcast collectionId
                return response.results
                    .first { $0.collectionId == podcastCollectionId }?
                    .trackViewUrl
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    // Search podcasts - unchanged
    func searchPodcasts(term: String, limit: Int = 20) -> AnyPublisher<[Podcast], Error> {
        let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString =
            "\(baseURL)/search?media=podcast&entity=podcast&term=\(encoded)&limit=\(limit)"

        print(urlString)
        guard let url = URL(string: urlString) else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }

        return URLSession.shared.dataTaskPublisher(for: url)
            .map { $0.data }
            .decode(type: SearchResponse.self, decoder: JSONDecoder())
            .map { $0.results }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    // Updated: Fetch episodes from Apple (fixed to handle only podcast return without error)
    func fetchEpisodes(for collectionId: Int, limit: Int = 200) -> AnyPublisher<[Episode], Error> {
        let urlString = "\(baseURL)/lookup?id=\(collectionId)&entity=podcastEpisode&limit=\(limit)"

        print(urlString)
        guard let url = URL(string: urlString) else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }

        return URLSession.shared.dataTaskPublisher(for: url)
            .map { $0.data }
            .tryMap { data in
                // Parse as dict first (like ObjectMapper in Java to avoid direct decode errors)
                let json =
                    try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
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
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    // New: Fetch episodes from RSS feed (alternative since Apple doesn't return them)
    // Like fetching XML in Spring Boot with RestTemplate, then parsing with JAXB
    func fetchEpisodesFromRSS(feedUrl: String, limit: Int = 200) -> AnyPublisher<[Episode], Error> {
        guard let url = URL(string: feedUrl) else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }

        return URLSession.shared.dataTaskPublisher(for: url)
            .map { $0.data }
            .tryMap { data in
                let parser = RSSParser(data: data)
                let episodes = try parser.parse()
                return Array(episodes.prefix(limit))  // Limit like Pageable in Spring Data
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}

// New: RSS Parser class (like a custom XML parser service in Java)
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

// Extension to convert Combine publishers to async/await (unchanged)
extension Publisher where Output: Sendable {
    func async() async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable =
                self
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            break
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                        cancellable?.cancel()
                    },
                    receiveValue: { value in
                        continuation.resume(returning: value)
                        cancellable?.cancel()
                    }
                )
        }
    }
}
