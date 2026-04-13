//
//  HTMLTextView.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/11/28.
//

import SwiftUI

struct HTMLTextView: View {
    let attributedString: NSAttributedString
    var linkTimestamps: Bool = false

    var body: some View {
        if let swiftAttributedString = convertToSwiftAttributedString() {
            Text(swiftAttributedString)
                .tint(.blue)
        } else {
            Text(attributedString.string)
        }
    }

    private func convertToSwiftAttributedString() -> AttributedString? {
        #if os(macOS)
        guard var result = try? AttributedString(attributedString, including: \.appKit) else { return nil }
        #else
        guard var result = try? AttributedString(attributedString, including: \.uiKit) else { return nil }
        #endif
        if linkTimestamps {
            result = TimestampUtils.addTimestampLinks(to: result)
        }
        return result
    }
}
