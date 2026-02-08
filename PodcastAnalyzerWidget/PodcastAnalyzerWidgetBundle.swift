//
//  PodcastAnalyzerWidgetBundle.swift
//  PodcastAnalyzerWidget
//
//  Created by Bob on 2026/1/25.
//

import WidgetKit
import SwiftUI

@main
struct PodcastAnalyzerWidgetBundle: WidgetBundle {
    var body: some Widget {
        PodcastAnalyzerWidget()
        NowPlayingWidget()
    }
}
