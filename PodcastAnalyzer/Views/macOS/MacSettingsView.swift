//
//  MacSettingsView.swift
//  PodcastAnalyzer
//
//  macOS-specific settings view for Preferences window (Cmd+,)
//

#if os(macOS)
import SwiftData
import SwiftUI

struct MacSettingsView: View {
  private enum SettingsTab: Hashable, CaseIterable {
    case general, appearance, sync, playback, transcript, ai, storage

    var title: String {
      switch self {
      case .general: "General"
      case .appearance: "Appearance"
      case .sync: "Sync"
      case .playback: "Playback"
      case .transcript: "Transcript"
      case .ai: "AI"
      case .storage: "Storage"
      }
    }

    var systemImage: String {
      switch self {
      case .general: "gearshape"
      case .appearance: "paintbrush"
      case .sync: "arrow.triangle.2.circlepath"
      case .playback: "play.circle"
      case .transcript: "text.bubble"
      case .ai: "sparkles"
      case .storage: "internaldrive"
      }
    }
  }

  @State private var selection: SettingsTab = .general

  var body: some View {
    TabView(selection: $selection) {
      ForEach(SettingsTab.allCases, id: \.self) { tab in
        Tab(tab.title, systemImage: tab.systemImage, value: tab) {
          tabContent(for: tab)
        }
      }
    }
    .frame(width: 500, height: 400)
  }

  @ViewBuilder
  private func tabContent(for tab: SettingsTab) -> some View {
    switch tab {
    case .general: GeneralSettingsTab()
    case .appearance: AppearanceSettingsTab()
    case .sync: SyncSettingsTab()
    case .playback: PlaybackSettingsTab()
    case .transcript: TranscriptSettingsTab()
    case .ai: AISettingsTab()
    case .storage: StorageSettingsTab()
    }
  }
}

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
  var body: some View {
    Form {
      Section {
        HStack {
          Text("Version")
          Spacer()
          Text("1.0.0")
            .foregroundStyle(.secondary)
        }
      }
    }
    .formStyle(.grouped)
    .padding()
  }
}

// MARK: - Appearance Settings Tab

struct AppearanceSettingsTab: View {
  @State private var viewModel = SettingsViewModel()

  var body: some View {
    Form {
      Section {
        Toggle("Show Episode Artwork", isOn: Binding(
          get: { viewModel.showEpisodeArtwork },
          set: { viewModel.setShowEpisodeArtwork($0) }
        ))
      } header: {
        Text("Episode Lists")
      } footer: {
        Text("Hide artwork in episode lists to reduce memory usage.")
      }
    }
    .formStyle(.grouped)
    .padding()
  }
}

// MARK: - Sync Settings Tab

struct SyncSettingsTab: View {
  private var syncManager: BackgroundSyncManager { .shared }

  var body: some View {
    Form {
      Section {
          Toggle("Enable Background Sync", isOn: Binding(get: { syncManager.isBackgroundSyncEnabled }, set: { syncManager.isBackgroundSyncEnabled = $0 }))

        if syncManager.isBackgroundSyncEnabled {
          Toggle("New Episode Notifications", isOn: Binding(get: { syncManager.isNotificationsEnabled }, set: { syncManager.isNotificationsEnabled = $0 }))

          if let lastSync = syncManager.lastSyncDate {
            HStack {
              Text("Last Sync")
              Spacer()
              Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                .foregroundStyle(.secondary)
            }
          }

          Button("Sync Now") {
            Task {
              await syncManager.syncNow()
            }
          }
          .disabled(syncManager.isSyncing)
        }
      } header: {
        Text("Sync Settings")
      } footer: {
        Text("Automatically check for new episodes periodically while the app is running.")
      }
    }
    .formStyle(.grouped)
    .padding()
  }
}

// MARK: - Playback Settings Tab

struct PlaybackSettingsTab: View {
  @State private var viewModel = SettingsViewModel()
  private let playbackSpeeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

  var body: some View {
    Form {
      Section {
        Picker("Default Playback Speed", selection: $viewModel.defaultPlaybackSpeed) {
          ForEach(playbackSpeeds, id: \.self) { speed in
            Text(formatSpeed(speed)).tag(speed)
          }
        }
        .onChange(of: viewModel.defaultPlaybackSpeed) { _, newValue in
          viewModel.setDefaultPlaybackSpeed(newValue)
        }

        Toggle("Auto-Play Random Episode", isOn: Binding(
          get: { viewModel.autoPlayNextEpisode },
          set: { viewModel.setAutoPlayNextEpisode($0) }
        ))
      } header: {
        Text("Playback")
      } footer: {
        Text("When enabled, a random unplayed episode will play when the queue is empty.")
      }
    }
    .formStyle(.grouped)
    .padding()
  }

  private func formatSpeed(_ speed: Float) -> String {
    if speed == 1.0 {
      return "1x"
    } else if speed.truncatingRemainder(dividingBy: 1) == 0 {
      return "\(Int(speed))x"
    } else {
      return String(format: "%.2gx", speed)
    }
  }
}

// MARK: - Transcript Settings Tab

struct TranscriptSettingsTab: View {
  @State private var viewModel = SettingsViewModel()

  var body: some View {
    Form {
      Section {
        Picker("Language", selection: $viewModel.selectedTranscriptLocale) {
          ForEach(SettingsViewModel.availableTranscriptLocales) { locale in
            Text(locale.name).tag(locale.id)
          }
        }
        .onChange(of: viewModel.selectedTranscriptLocale) { _, newValue in
          viewModel.setSelectedTranscriptLocale(newValue)
        }

        HStack {
          Text("Speech Model Status")
          Spacer()
          transcriptStatusView
        }
      } header: {
        Text("Transcript Settings")
      } footer: {
        Text("Download speech models for transcript generation. Each podcast uses its own language from the RSS feed.")
      }
    }
    .formStyle(.grouped)
    .padding()
    .onAppear {
      viewModel.checkTranscriptModelStatus()
    }
  }

  @ViewBuilder
  private var transcriptStatusView: some View {
    switch viewModel.transcriptModelStatus {
    case .checking:
      HStack(spacing: 8) {
        ProgressView()
          .scaleEffect(0.7)
        Text("Checking...")
          .foregroundStyle(.secondary)
      }
    case .notDownloaded:
      HStack(spacing: 8) {
        Text("Not installed")
          .foregroundStyle(.orange)
        Button("Download") {
          viewModel.downloadTranscriptModel()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
      }
    case .downloading(let progress):
      HStack(spacing: 8) {
        ProgressView(value: progress)
          .frame(width: 80)
        Text("\(Int(progress * 100))%")
          .foregroundStyle(.secondary)
        Button {
          viewModel.cancelTranscriptDownload()
        } label: {
          Image(systemName: "xmark.circle.fill")
        }
        .buttonStyle(.plain)
      }
    case .ready:
      HStack(spacing: 4) {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
        Text("Ready")
          .foregroundStyle(.green)
      }
    case .error(let message):
      HStack(spacing: 8) {
        Text(message)
          .foregroundStyle(.red)
          .lineLimit(1)
        Button("Retry") {
          viewModel.downloadTranscriptModel()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
      }
    case .simulatorNotSupported:
      Text("Requires physical device")
        .foregroundStyle(.secondary)
    }
  }
}

// MARK: - AI Settings Tab

struct AISettingsTab: View {
  var body: some View {
    Form {
      Section {
        NavigationLink {
          AISettingsView()
        } label: {
          HStack {
            Text("Configure AI Providers")
            Spacer()
            if AISettingsManager.shared.hasConfiguredProvider {
              Text(AISettingsManager.shared.selectedProvider.displayName)
                .foregroundStyle(.secondary)
            } else {
              Text("Not configured")
                .foregroundStyle(.orange)
            }
          }
        }
      } header: {
        Text("AI Analysis")
      } footer: {
        Text("Configure cloud AI providers (OpenAI, Claude, Gemini, Grok) for transcript analysis.")
      }
    }
    .formStyle(.grouped)
    .padding()
  }
}

// MARK: - Storage Settings Tab

struct StorageSettingsTab: View {
  @Environment(\.modelContext) private var modelContext

  @State private var imageCacheSize: String = "Calculating..."
  @State private var downloadedAudioSize: String = "Calculating..."
  @State private var transcriptsSize: String = "Calculating..."
  @State private var aiAnalysisCount: Int = 0

  @State private var isClearingData = false
  @State private var clearingMessage = ""

  @State private var showClearCacheAlert = false
  @State private var showClearDownloadsAlert = false
  @State private var showClearTranscriptsAlert = false
  @State private var showClearAIAlert = false

  var body: some View {
    Form {
      Section {
        storageRow(
          icon: "photo.on.rectangle",
          iconColor: .orange,
          title: "Image Cache",
          size: imageCacheSize,
          isClearing: isClearingData && clearingMessage == "cache"
        ) {
          showClearCacheAlert = true
        }

        storageRow(
          icon: "arrow.down.circle.fill",
          iconColor: .green,
          title: "Downloaded Episodes",
          size: downloadedAudioSize,
          isClearing: isClearingData && clearingMessage == "downloads",
          isDestructive: true
        ) {
          showClearDownloadsAlert = true
        }

        storageRow(
          icon: "text.bubble",
          iconColor: .blue,
          title: "Transcripts",
          size: transcriptsSize,
          isClearing: isClearingData && clearingMessage == "transcripts",
          isDestructive: true
        ) {
          showClearTranscriptsAlert = true
        }

        storageRow(
          icon: "sparkles",
          iconColor: .purple,
          title: "AI Analysis Data",
          size: "\(aiAnalysisCount) analyses",
          isClearing: isClearingData && clearingMessage == "ai",
          isDestructive: true
        ) {
          showClearAIAlert = true
        }
      } header: {
        Text("Data Management")
      } footer: {
        Text("Clearing downloads and transcripts will free up storage space but won't affect your subscriptions.")
      }
    }
    .formStyle(.grouped)
    .padding()
    .onAppear {
      calculateStorageInfo()
    }
    .alert("Clear Image Cache", isPresented: $showClearCacheAlert) {
      Button("Cancel", role: .cancel) {}
      Button("Clear", role: .destructive) { clearImageCache() }
    } message: {
      Text("This will remove all cached images. They will be re-downloaded when needed.")
    }
    .alert("Remove All Downloads", isPresented: $showClearDownloadsAlert) {
      Button("Cancel", role: .cancel) {}
      Button("Remove All", role: .destructive) { clearAllDownloads() }
    } message: {
      Text("This will delete all downloaded episodes. You can re-download them later.")
    }
    .alert("Remove All Transcripts", isPresented: $showClearTranscriptsAlert) {
      Button("Cancel", role: .cancel) {}
      Button("Remove All", role: .destructive) { clearAllTranscripts() }
    } message: {
      Text("This will delete all generated transcripts. You can regenerate them later.")
    }
    .alert("Remove All AI Analysis", isPresented: $showClearAIAlert) {
      Button("Cancel", role: .cancel) {}
      Button("Remove All", role: .destructive) { clearAllAIAnalysis() }
    } message: {
      Text("This will delete all AI-generated summaries, entities, highlights, and Q&A history.")
    }
  }

  @ViewBuilder
  private func storageRow(
    icon: String,
    iconColor: Color,
    title: String,
    size: String,
    isClearing: Bool,
    isDestructive: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    HStack {
      Image(systemName: icon)
        .foregroundStyle(iconColor)
        .frame(width: 20)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
        Text(size)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if isClearing {
        ProgressView()
          .scaleEffect(0.7)
      } else {
        Button(isDestructive ? "Remove All" : "Clear") {
          action()
        }
        .foregroundStyle(isDestructive ? .red : .blue)
      }
    }
    .buttonStyle(.plain)
  }

  // MARK: - Storage Calculations

  private func calculateStorageInfo() {
    Task {
      let cacheSize = await calculateImageCacheSize()
      await MainActor.run { imageCacheSize = formatBytes(cacheSize) }

      let audioSize = await calculateDownloadedAudioSize()
      await MainActor.run { downloadedAudioSize = formatBytes(audioSize) }

      let captionsSize = await calculateTranscriptsSize()
      await MainActor.run { transcriptsSize = formatBytes(captionsSize) }

      let analysisCount = countAIAnalyses()
      await MainActor.run { aiAnalysisCount = analysisCount }
    }
  }

  private func calculateImageCacheSize() async -> Int64 {
    // FileManager enumeration must be done synchronously in Swift 6
    // Use nonisolated helper to avoid async context restrictions
    Self.enumerateDirectorySize(at: "ImageCache", in: .cachesDirectory)
  }

  private nonisolated static func enumerateDirectorySize(at subpath: String, in searchPath: FileManager.SearchPathDirectory) -> Int64 {
    let fileManager = FileManager.default
    let baseDir = fileManager.urls(for: searchPath, in: .userDomainMask)[0]
    let targetDir = baseDir.appendingPathComponent(subpath)

    guard let enumerator = fileManager.enumerator(at: targetDir, includingPropertiesForKeys: [.fileSizeKey])
    else { return 0 }

    var totalSize: Int64 = 0
    for case let fileURL as URL in enumerator {
      if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
        totalSize += Int64(size)
      }
    }
    return totalSize
  }

  private func calculateDownloadedAudioSize() async -> Int64 {
    await FileStorageManager.shared.calculateTotalAudioSize()
  }

  private func calculateTranscriptsSize() async -> Int64 {
    // Reuse the same nonisolated helper for Captions directory
    Self.enumerateDirectorySize(at: "Captions", in: .documentDirectory)
  }

  private func countAIAnalyses() -> Int {
    let descriptor = FetchDescriptor<EpisodeAIAnalysis>()
    return (try? modelContext.fetchCount(descriptor)) ?? 0
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }

  // MARK: - Clear Actions

  private func clearImageCache() {
    isClearingData = true
    clearingMessage = "cache"

    Task {
      ImageCacheManager.shared.clearAllCache()
      isClearingData = false
      clearingMessage = ""
      imageCacheSize = "0 bytes"
    }
  }

  private func clearAllDownloads() {
    isClearingData = true
    clearingMessage = "downloads"

    Task {
      let descriptor = FetchDescriptor<EpisodeDownloadModel>(
        predicate: #Predicate { $0.localAudioPath != nil }
      )

      if let downloadedEpisodes = try? modelContext.fetch(descriptor) {
        for episode in downloadedEpisodes {
          if let localPath = episode.localAudioPath {
            try? FileManager.default.removeItem(atPath: localPath)
          }
          episode.localAudioPath = nil
          episode.downloadedDate = nil
          episode.fileSize = 0
        }
        try? modelContext.save()
      }

      await FileStorageManager.shared.clearAllAudioFiles()

      await MainActor.run {
        isClearingData = false
        clearingMessage = ""
        downloadedAudioSize = "0 bytes"
      }
    }
  }

  private func clearAllTranscripts() {
    isClearingData = true
    clearingMessage = "transcripts"

    Task {
      let descriptor = FetchDescriptor<EpisodeDownloadModel>(
        predicate: #Predicate { $0.captionPath != nil }
      )

      if let episodesWithCaptions = try? modelContext.fetch(descriptor) {
        for episode in episodesWithCaptions {
          episode.captionPath = nil
        }
        try? modelContext.save()
      }

      await FileStorageManager.shared.clearAllCaptionFiles()

      await MainActor.run {
        isClearingData = false
        clearingMessage = ""
        transcriptsSize = "0 bytes"
      }
    }
  }

  private func clearAllAIAnalysis() {
    isClearingData = true
    clearingMessage = "ai"

    Task {
      let descriptor = FetchDescriptor<EpisodeAIAnalysis>()
      if let analyses = try? modelContext.fetch(descriptor) {
        for analysis in analyses {
          modelContext.delete(analysis)
        }
        try? modelContext.save()
      }

      let tagsDescriptor = FetchDescriptor<EpisodeQuickTagsModel>()
      if let tags = try? modelContext.fetch(tagsDescriptor) {
        for tag in tags {
          modelContext.delete(tag)
        }
        try? modelContext.save()
      }

      await MainActor.run {
        isClearingData = false
        clearingMessage = ""
        aiAnalysisCount = 0
      }
    }
  }
}

#Preview {
  MacSettingsView()
}

#endif
