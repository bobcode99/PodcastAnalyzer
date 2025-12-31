import SwiftData
import SwiftUI
import UserNotifications

#if os(iOS)
import UIKit
#endif

struct SettingsView: View {
  @StateObject private var viewModel = SettingsViewModel()
  @StateObject private var syncManager = BackgroundSyncManager.shared
  @Environment(\.modelContext) var modelContext
  @State private var showAddFeedSheet = false

  // Data management state
  @State private var showClearCacheConfirmation = false
  @State private var showClearDownloadsConfirmation = false
  @State private var showClearTranscriptsConfirmation = false
  @State private var showClearAIAnalysisConfirmation = false
  @State private var isClearingData = false
  @State private var clearingMessage = ""

  // Storage info
  @State private var imageCacheSize: String = "Calculating..."
  @State private var downloadedAudioSize: String = "Calculating..."
  @State private var transcriptsSize: String = "Calculating..."
  @State private var aiAnalysisCount: Int = 0

  private let playbackSpeeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

  var body: some View {
    NavigationStack {
      List {
        // MARK: - Sync & Notifications Section
        Section {
          Toggle(isOn: $syncManager.isBackgroundSyncEnabled) {
            HStack {
              Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundColor(.blue)
                .frame(width: 24)
              VStack(alignment: .leading, spacing: 2) {
                Text("Background Sync")
                if let lastSync = syncManager.lastSyncDate {
                  Text("Last: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
              }
            }
          }

          Toggle(isOn: $syncManager.isNotificationsEnabled) {
            HStack {
              Image(systemName: "bell.badge")
                .foregroundColor(.orange)
                .frame(width: 24)
              VStack(alignment: .leading, spacing: 2) {
                Text("New Episode Notifications")
                notificationStatusText
              }
            }
          }
          .disabled(!syncManager.isBackgroundSyncEnabled)

          if syncManager.isBackgroundSyncEnabled {
            Button(action: {
              Task {
                await syncManager.syncNow()
              }
            }) {
              HStack {
                Image(systemName: "arrow.clockwise")
                  .foregroundColor(.green)
                  .frame(width: 24)
                Text("Sync Now")
                Spacer()
                if syncManager.isSyncing {
                  ProgressView()
                    .scaleEffect(0.8)
                }
              }
            }
            .disabled(syncManager.isSyncing)
          }
        } header: {
          Text("Sync & Notifications")
        } footer: {
          Text("Automatically check for new episodes every 5 minutes")
        }

        // MARK: - Subscriptions Section
        Section {
          Button(action: {
            showAddFeedSheet = true
          }) {
            HStack {
              Image(systemName: "plus.circle.fill")
                .foregroundColor(.blue)
                .font(.title2)
              Text("Add RSS Feed")
                .foregroundColor(.primary)
              Spacer()
              Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
            }
          }
        } header: {
          Text("Subscriptions")
        } footer: {
          Text("Add podcasts by pasting their RSS feed URL")
        }

        // MARK: - Playback Section
        Section {
          Picker(selection: $viewModel.defaultPlaybackSpeed) {
            ForEach(playbackSpeeds, id: \.self) { speed in
              Text(formatSpeed(speed)).tag(speed)
            }
          } label: {
            HStack {
              Image(systemName: "gauge.with.dots.needle.33percent")
                .foregroundColor(.blue)
                .frame(width: 24)
              Text("Default Speed")
            }
          }
          .onChange(of: viewModel.defaultPlaybackSpeed) { _, newValue in
            viewModel.setDefaultPlaybackSpeed(newValue)
          }
        } header: {
          Text("Playback")
        } footer: {
          Text("New episodes will start at this speed")
        }

        // MARK: - Transcript Section
        Section {
          // Language picker
          Picker(selection: $viewModel.selectedTranscriptLocale) {
            ForEach(SettingsViewModel.availableTranscriptLocales) { locale in
              Text(locale.name).tag(locale.id)
            }
          } label: {
            HStack {
              Image(systemName: "globe")
                .foregroundColor(.blue)
                .frame(width: 24)
              Text("Language")
            }
          }
          .onChange(of: viewModel.selectedTranscriptLocale) { _, newValue in
            viewModel.setSelectedTranscriptLocale(newValue)
          }

          // Speech model status
          HStack {
            Image(systemName: "text.bubble")
              .foregroundColor(.blue)
              .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
              Text("Speech Model")
              transcriptStatusText
            }

            Spacer()

            transcriptActionButton
          }
        } header: {
          Text("Transcript")
        } footer: {
          Text(
            "Download speech models here. When generating transcripts, each podcast uses its own language from the RSS feed."
          )
        }

        // MARK: - AI Settings Section
        Section {
          NavigationLink {
            AISettingsView()
          } label: {
            HStack {
              Image(systemName: "sparkles")
                .foregroundColor(.purple)
                .frame(width: 24)
              Text("AI Settings")
              Spacer()
              if AISettingsManager.shared.hasConfiguredProvider {
                Text(AISettingsManager.shared.selectedProvider.displayName)
                  .font(.caption)
                  .foregroundColor(.secondary)
              } else {
                Text("Not configured")
                  .font(.caption)
                  .foregroundColor(.orange)
              }
            }
          }
        } header: {
          Text("AI Analysis")
        } footer: {
          Text("Configure cloud AI providers (OpenAI, Claude, Gemini, Grok) for transcript analysis")
        }

        // MARK: - Data Management Section
        Section {
          // Clear Image Cache
          Button(action: {
            showClearCacheConfirmation = true
          }) {
            HStack {
              Image(systemName: "photo.on.rectangle")
                .foregroundColor(.orange)
                .frame(width: 24)
              VStack(alignment: .leading, spacing: 2) {
                Text("Image Cache")
                Text(imageCacheSize)
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
              Spacer()
              if isClearingData && clearingMessage == "cache" {
                ProgressView()
                  .scaleEffect(0.8)
              } else {
                Text("Clear")
                  .font(.subheadline)
                  .foregroundColor(.blue)
              }
            }
          }
          .disabled(isClearingData)

          // Clear All Downloads
          Button(action: {
            showClearDownloadsConfirmation = true
          }) {
            HStack {
              Image(systemName: "arrow.down.circle.fill")
                .foregroundColor(.green)
                .frame(width: 24)
              VStack(alignment: .leading, spacing: 2) {
                Text("Downloaded Episodes")
                Text(downloadedAudioSize)
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
              Spacer()
              if isClearingData && clearingMessage == "downloads" {
                ProgressView()
                  .scaleEffect(0.8)
              } else {
                Text("Remove All")
                  .font(.subheadline)
                  .foregroundColor(.red)
              }
            }
          }
          .disabled(isClearingData)

          // Clear All Transcripts
          Button(action: {
            showClearTranscriptsConfirmation = true
          }) {
            HStack {
              Image(systemName: "text.bubble")
                .foregroundColor(.blue)
                .frame(width: 24)
              VStack(alignment: .leading, spacing: 2) {
                Text("Transcripts")
                Text(transcriptsSize)
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
              Spacer()
              if isClearingData && clearingMessage == "transcripts" {
                ProgressView()
                  .scaleEffect(0.8)
              } else {
                Text("Remove All")
                  .font(.subheadline)
                  .foregroundColor(.red)
              }
            }
          }
          .disabled(isClearingData)

          // Clear All AI Analysis
          Button(action: {
            showClearAIAnalysisConfirmation = true
          }) {
            HStack {
              Image(systemName: "sparkles")
                .foregroundColor(.purple)
                .frame(width: 24)
              VStack(alignment: .leading, spacing: 2) {
                Text("AI Analysis Data")
                Text("\(aiAnalysisCount) analyses")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
              Spacer()
              if isClearingData && clearingMessage == "ai" {
                ProgressView()
                  .scaleEffect(0.8)
              } else {
                Text("Remove All")
                  .font(.subheadline)
                  .foregroundColor(.red)
              }
            }
          }
          .disabled(isClearingData)
        } header: {
          Text("Data Management")
        } footer: {
          Text("Clearing downloads and transcripts will free up storage space but won't affect your subscriptions")
        }

        // MARK: - About Section
        Section {
          HStack {
            Image(systemName: "info.circle")
              .foregroundColor(.blue)
              .frame(width: 24)
            Text("Version")
            Spacer()
            Text("1.0.0")
              .foregroundColor(.secondary)
          }
        } header: {
          Text("About")
        }
      }
      #if os(iOS)
      .listStyle(.insetGrouped)
      #else
      .listStyle(.sidebar)
      #endif
      .navigationTitle("Settings")
      .platformToolbarTitleDisplayMode()
      .sheet(isPresented: $showAddFeedSheet) {
        AddFeedView(viewModel: viewModel, modelContext: modelContext) {
          showAddFeedSheet = false
        }
      }
      .onAppear {
        viewModel.loadFeeds(modelContext: modelContext)
        viewModel.checkTranscriptModelStatus()
        calculateStorageInfo()
      }
      // Clear cache confirmation
      .confirmationDialog(
        "Clear Image Cache",
        isPresented: $showClearCacheConfirmation,
        titleVisibility: .visible
      ) {
        Button("Clear Cache", role: .destructive) {
          clearImageCache()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("This will remove all cached images. They will be re-downloaded when needed.")
      }
      // Clear downloads confirmation
      .confirmationDialog(
        "Remove All Downloads",
        isPresented: $showClearDownloadsConfirmation,
        titleVisibility: .visible
      ) {
        Button("Remove All Downloads", role: .destructive) {
          clearAllDownloads()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("This will delete all downloaded episodes. You can re-download them later.")
      }
      // Clear transcripts confirmation
      .confirmationDialog(
        "Remove All Transcripts",
        isPresented: $showClearTranscriptsConfirmation,
        titleVisibility: .visible
      ) {
        Button("Remove All Transcripts", role: .destructive) {
          clearAllTranscripts()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("This will delete all generated transcripts. You can regenerate them later.")
      }
      // Clear AI analysis confirmation
      .confirmationDialog(
        "Remove All AI Analysis",
        isPresented: $showClearAIAnalysisConfirmation,
        titleVisibility: .visible
      ) {
        Button("Remove All AI Analysis", role: .destructive) {
          clearAllAIAnalysis()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("This will delete all AI-generated summaries, entities, highlights, and Q&A history.")
      }
    }
  }

  // MARK: - Storage Calculation

  private func calculateStorageInfo() {
    Task {
      // Calculate image cache size
      let cacheSize = await calculateImageCacheSize()
      await MainActor.run {
        imageCacheSize = formatBytes(cacheSize)
      }

      // Calculate downloaded audio size
      let audioSize = await calculateDownloadedAudioSize()
      await MainActor.run {
        downloadedAudioSize = formatBytes(audioSize)
      }

      // Calculate transcripts size
      let captionsSize = await calculateTranscriptsSize()
      await MainActor.run {
        transcriptsSize = formatBytes(captionsSize)
      }

      // Count AI analyses
      let analysisCount = countAIAnalyses()
      await MainActor.run {
        aiAnalysisCount = analysisCount
      }
    }
  }

  private func calculateImageCacheSize() async -> Int64 {
    // Run synchronous file enumeration in a detached context to avoid async iterator issues
    await Task.detached(priority: .utility) {
      let fileManager = FileManager.default
      let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      let cacheDir = cachesDir.appendingPathComponent("ImageCache")

      guard let enumerator = fileManager.enumerator(
        at: cacheDir,
        includingPropertiesForKeys: [.fileSizeKey]
      ) else { return Int64(0) }

      var totalSize: Int64 = 0
      while let fileURL = enumerator.nextObject() as? URL {
        if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
          totalSize += Int64(size)
        }
      }
      return totalSize
    }.value
  }

  private func calculateDownloadedAudioSize() async -> Int64 {
    await FileStorageManager.shared.calculateTotalAudioSize()
  }

  private func calculateTranscriptsSize() async -> Int64 {
    // Run synchronous file enumeration in a detached context to avoid async iterator issues
    await Task.detached(priority: .utility) {
      let fileManager = FileManager.default
      let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
      let captionsDir = documentsDir.appendingPathComponent("Captions")

      guard let enumerator = fileManager.enumerator(
        at: captionsDir,
        includingPropertiesForKeys: [.fileSizeKey]
      ) else { return Int64(0) }

      var totalSize: Int64 = 0
      while let fileURL = enumerator.nextObject() as? URL {
        if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
          totalSize += Int64(size)
        }
      }
      return totalSize
    }.value
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

  // MARK: - Clear Data Actions

  private func clearImageCache() {
    isClearingData = true
    clearingMessage = "cache"

    Task {
      await ImageCacheManager.shared.clearAllCache()

      await MainActor.run {
        isClearingData = false
        clearingMessage = ""
        imageCacheSize = "0 bytes"
      }
    }
  }

  private func clearAllDownloads() {
    isClearingData = true
    clearingMessage = "downloads"

    Task {
      // Get all downloaded episodes and delete their files
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

      // Also clear via FileStorageManager
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
      // Update models to remove caption paths
      let descriptor = FetchDescriptor<EpisodeDownloadModel>(
        predicate: #Predicate { $0.captionPath != nil }
      )

      if let episodesWithCaptions = try? modelContext.fetch(descriptor) {
        for episode in episodesWithCaptions {
          episode.captionPath = nil
        }
        try? modelContext.save()
      }

      // Clear captions directory
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
      // Delete all AI analysis records
      let descriptor = FetchDescriptor<EpisodeAIAnalysis>()
      if let analyses = try? modelContext.fetch(descriptor) {
        for analysis in analyses {
          modelContext.delete(analysis)
        }
        try? modelContext.save()
      }

      // Also delete quick tags
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

  // MARK: - Notification Status Text

  @ViewBuilder
  private var notificationStatusText: some View {
    switch syncManager.notificationPermissionStatus {
    case .authorized:
      Text("Enabled")
        .font(.caption2)
        .foregroundColor(.green)
    case .denied:
      Text("Denied - Enable in Settings")
        .font(.caption2)
        .foregroundColor(.red)
    case .notDetermined:
      Text("Permission required")
        .font(.caption2)
        .foregroundColor(.orange)
    default:
      EmptyView()
    }
  }

  // MARK: - Transcript Status Views

  @ViewBuilder
  private var transcriptStatusText: some View {
    switch viewModel.transcriptModelStatus {
    case .checking:
      Text("Checking...")
        .font(.caption)
        .foregroundColor(.secondary)
    case .notDownloaded:
      Text("Not installed")
        .font(.caption)
        .foregroundColor(.orange)
    case .downloading(let progress):
      Text("Downloading \(Int(progress * 100))%")
        .font(.caption)
        .foregroundColor(.blue)
    case .ready:
      Text("Ready")
        .font(.caption)
        .foregroundColor(.green)
    case .error(let message):
      Text(message)
        .font(.caption)
        .foregroundColor(.red)
        .lineLimit(1)
    case .simulatorNotSupported:
      Text("Requires physical device")
        .font(.caption)
        .foregroundColor(.secondary)
    }
  }

  @ViewBuilder
  private var transcriptActionButton: some View {
    switch viewModel.transcriptModelStatus {
    case .checking:
      ProgressView()
        .scaleEffect(0.8)
    case .notDownloaded, .error:
      Button("Download") {
        viewModel.downloadTranscriptModel()
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.small)
    case .downloading(let progress):
      HStack(spacing: 8) {
        ProgressView(value: progress)
          .frame(width: 60)
        Button {
          viewModel.cancelTranscriptDownload()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
      }
    case .ready:
      Image(systemName: "checkmark.circle.fill")
        .foregroundColor(.green)
    case .simulatorNotSupported:
      Image(systemName: "desktopcomputer")
        .foregroundColor(.secondary)
    }
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

// MARK: - Feed Row View
struct FeedRowView: View {
  let feed: PodcastInfoModel

  var body: some View {
    HStack(spacing: 12) {
      // Podcast artwork
      if let urlString = feed.podcastInfo.imageURL.isEmpty ? nil : feed.podcastInfo.imageURL,
        let url = URL(string: urlString)
      {
        AsyncImage(url: url) { phase in
          switch phase {
          case .empty:
            ZStack {
              Color.gray.opacity(0.2)
              ProgressView().scaleEffect(0.5)
            }
          case .success(let image):
            image.resizable().scaledToFill()
          case .failure:
            Image(systemName: "mic.fill")
              .foregroundColor(.purple)
          @unknown default:
            EmptyView()
          }
        }
        .frame(width: 50, height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 8))
      } else {
        RoundedRectangle(cornerRadius: 8)
          .fill(Color.purple.opacity(0.2))
          .frame(width: 50, height: 50)
          .overlay(
            Image(systemName: "mic.fill")
              .foregroundColor(.purple)
          )
      }

      VStack(alignment: .leading, spacing: 4) {
        Text(feed.podcastInfo.title)
          .font(.body)
          .fontWeight(.medium)
          .lineLimit(1)

        Text("\(feed.podcastInfo.episodes.count) episodes")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .padding(.vertical, 4)
  }
}

// MARK: - Add Feed Sheet View
struct AddFeedView: View {
  @ObservedObject var viewModel: SettingsViewModel
  var modelContext: ModelContext
  var onDismiss: () -> Void

  @FocusState private var isTextFieldFocused: Bool

  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        // Icon
        Image(systemName: "antenna.radiowaves.left.and.right")
          .font(.system(size: 60))
          .foregroundColor(.blue)
          .padding(.top, 40)

        // Title and description
        VStack(spacing: 8) {
          Text("Add Podcast")
            .font(.title2)
            .fontWeight(.bold)

          Text("Enter the RSS feed URL to subscribe")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
        }

        // Input field
        VStack(spacing: 12) {
          TextField("https://example.com/feed.xml", text: $viewModel.rssUrlInput)
            .textFieldStyle(.plain)
            .padding(16)
            .background(Color.platformSystemGray6)
            .cornerRadius(12)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            #endif
            .disabled(viewModel.isValidating)
            .focused($isTextFieldFocused)

          // Status messages
          if viewModel.isValidating {
            HStack(spacing: 8) {
              ProgressView()
                .scaleEffect(0.8)
              Text("Validating feed...")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          } else if !viewModel.successMessage.isEmpty {
            HStack(spacing: 6) {
              Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
              Text(viewModel.successMessage)
                .font(.caption)
                .foregroundColor(.green)
            }
          } else if !viewModel.errorMessage.isEmpty {
            HStack(spacing: 6) {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
              Text(viewModel.errorMessage)
                .font(.caption)
                .foregroundColor(.red)
            }
          }
        }
        .padding(.horizontal, 24)

        Spacer()

        // Add button
        Button(action: {
          viewModel.addRssLink(modelContext: modelContext) {
            // Dismiss on success
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
              onDismiss()
            }
          }
        }) {
          HStack {
            if viewModel.isValidating {
              ProgressView()
                .tint(.white)
            } else {
              Image(systemName: "plus.circle.fill")
              Text("Add Podcast")
            }
          }
          .font(.headline)
          .foregroundColor(.white)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 16)
          .background(
            RoundedRectangle(cornerRadius: 14)
              .fill(
                viewModel.rssUrlInput.trimmingCharacters(in: .whitespaces).isEmpty
                  || viewModel.isValidating ? Color.gray : Color.blue)
          )
        }
        .disabled(
          viewModel.rssUrlInput.trimmingCharacters(in: .whitespaces).isEmpty
            || viewModel.isValidating
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
      }
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            viewModel.clearMessages()
            onDismiss()
          }
        }
      }
      .onAppear {
        isTextFieldFocused = true
      }
      .onDisappear {
        viewModel.clearMessages()
      }
    }
    .presentationDetents([.medium])
    .presentationDragIndicator(.visible)
  }
}

#Preview {
  SettingsView()
}
