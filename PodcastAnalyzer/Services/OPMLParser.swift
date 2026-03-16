//
//  OPMLParser.swift
//  PodcastAnalyzer
//
//  Parses OPML subscription files exported from Apple Podcasts and other apps.
//  Returns the list of RSS feed URLs found in the file.
//

import Foundation

struct OPMLParser {
  /// Parses OPML data and returns all RSS feed URLs found within.
  static func parse(data: Data) -> [String] {
    let delegate = OPMLXMLDelegate()
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    parser.parse()
    return delegate.rssURLs
  }
}

// MARK: - Private XML delegate

private final class OPMLXMLDelegate: NSObject, XMLParserDelegate {
  var rssURLs: [String] = []

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName _: String?,
    attributes: [String: String] = [:]
  ) {
    guard
      elementName.lowercased() == "outline",
      attributes["type"]?.lowercased() == "rss",
      let xmlUrl = attributes["xmlUrl"],
      !xmlUrl.isEmpty
    else { return }

    rssURLs.append(xmlUrl)
  }
}
