//
//  HTMLTextView.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/11/28.
//

import SwiftUI
import Combine 
struct HTMLTextView: View {
    let attributedString: NSAttributedString
    
    var body: some View {
        // We use a conditional check to determine which attribute scope to use.
        // iOS = UIKit, macOS = AppKit.
        if let swiftAttributedString = convertToSwiftAttributedString() {
            Text(swiftAttributedString)
                .tint(.blue)
        } else {
            // Fallback if conversion fails
            Text(attributedString.string)
        }
    }
    
    /// Helper function to handle platform-specific conversion
    private func convertToSwiftAttributedString() -> AttributedString? {
        #if os(macOS)
        // On macOS, use the AppKit scope
        return try? AttributedString(attributedString, including: \.appKit)
        #else
        // On iOS, use the UIKit scope
        return try? AttributedString(attributedString, including: \.uiKit)
        #endif
    }
}
