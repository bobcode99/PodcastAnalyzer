//
//  HTMLTextView.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/11/28.
//


import SwiftUI

struct HTMLTextView: View {
    let attributedString: NSAttributedString
    
    var body: some View {
        // Convert NSAttributedString (UIKit) to AttributedString (SwiftUI)
        // This preserves the hyperlinks created by ZMarkupParser
        if let swiftAttributedString = try? AttributedString(attributedString, including: \.uiKit) {
            Text(swiftAttributedString)
                .tint(.blue) // Color for links
        } else {
            // Fallback
            Text(attributedString.string)
        }
    }
}