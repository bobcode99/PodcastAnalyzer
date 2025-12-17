//
//  Switcher.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/12/17.
//

import SwiftUI
import ZMarkupParser

// 👇 ADD THIS
#if os(macOS)
import AppKit // For NSColor
#else
import UIKit // For UIColor
#endif
