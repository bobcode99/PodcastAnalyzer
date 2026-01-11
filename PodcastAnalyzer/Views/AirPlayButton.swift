//
//  AirPlayButton.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2026/1/2.
//

import AVKit
import SwiftUI

#if os(iOS)
import UIKit

struct AirPlayButton: UIViewRepresentable {
  func makeUIView(context: Context) -> AVRoutePickerView {
    let picker = AVRoutePickerView()
    picker.backgroundColor = .clear
    picker.activeTintColor = .systemBlue
    picker.tintColor = .secondaryLabel
    return picker
  }

  func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

#elseif os(macOS)
import AppKit

struct AirPlayButton: NSViewRepresentable {
  func makeNSView(context: Context) -> AVRoutePickerView {
    let picker = AVRoutePickerView()
    picker.isRoutePickerButtonBordered = false
    return picker
  }

  func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}
#endif
