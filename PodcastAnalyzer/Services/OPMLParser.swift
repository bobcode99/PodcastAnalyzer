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

  /// Generates an OPML 2.0 document from a list of podcast subscriptions.
  static func export(podcasts: [PodcastInfo]) -> String {
    var lines: [String] = []
    lines.append(#"<?xml version="1.0" encoding="UTF-8"?>"#)
    lines.append(#"<opml version="2.0">"#)
    lines.append("  <head>")
    lines.append("    <title>Podcast Subscriptions</title>")
    lines.append("  </head>")
    lines.append("  <body>")
    for podcast in podcasts where !podcast.rssUrl.isEmpty {
      let title = xmlEscape(podcast.title)
      let url = xmlEscape(podcast.rssUrl)
      lines.append(#"    <outline type="rss" text="\#(title)" xmlUrl="\#(url)"/>"#)
    }
    lines.append("  </body>")
    lines.append("</opml>")
    return lines.joined(separator: "\n")
  }

  private static func xmlEscape(_ string: String) -> String {
    string
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
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
