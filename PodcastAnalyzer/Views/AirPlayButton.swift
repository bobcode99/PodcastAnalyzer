//
//  AirPlayButton.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2026/1/2.
//


import AVKit
import SwiftUI

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.backgroundColor = .clear
        picker.activeTintColor = .systemBlue // Color when active
        picker.tintColor = .secondaryLabel  // Standard color
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}