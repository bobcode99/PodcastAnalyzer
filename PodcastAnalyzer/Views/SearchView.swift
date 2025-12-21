//
//  SearchView.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/11/23.
//

import SwiftUI

struct SearchView: View {

  var body: some View {
    Image(systemName: "magnifyingglass").resizable().frame(
      width: 100,
      height: 100
    ).foregroundStyle(Color.yellow)

  }
}
#Preview {
  SearchView()
}
