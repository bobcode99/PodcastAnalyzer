import SwiftData
import SwiftUI
import UserNotifications

#if os(iOS)
import UIKit
#endif

struct SettingsView: View {
  @State private var viewModel = SettingsViewModel()
  @State private var syncManager = BackgroundSyncManager.shared
  @Environment(\.modelContext) var modelContext
  @State private var showAddFeedSheet = false

  private let playbackSpeeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

  var body: some View {
    List {
        // MARK: - Sync & Notifications Section
        Section {
          Toggle(isOn: Binding(get: { syncManager.isBackgroundSyncEnabled }, set: { syncManager.isBackgroundSyncEnabled = $0 })) {
            HStack {
              Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.blue)
                .frame(width: 24)
              VStack(alignment: .leading, spacing: 2) {
                Text("Background Sync")
                if let lastSync = syncManager.lastSyncDate {
                  Text("Last: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
              }
            }
          }

          Toggle(isOn: Binding(get: { syncManager.isNotificationsEnabled }, set: { syncManager.isNotificationsEnabled = $0 })) {
            HStack {
              Image(systemName: "bell.badge")
                .foregroundStyle(.orange)
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
                  .foregroundStyle(.green)
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

        // MARK: - Appearance Section
        Section {
          Toggle(isOn: Binding(
            get: { viewModel.showEpisodeArtwork },
            set: { viewModel.setShowEpisodeArtwork($0) }
          )) {
            HStack {
              Image(systemName: "photo")
                .foregroundStyle(.blue)
                .frame(width: 24)
              Text("Show Episode Artwork")
            }
          }
        } header: {
          Text("Appearance")
        } footer: {
          Text("Hide artwork in episode lists to reduce memory usage")
        }

        // MARK: - Subscriptions Section
        Section {
          Button(action: {
            showAddFeedSheet = true
          }) {
            HStack {
              Image(systemName: "plus.circle.fill")
                .foregroundStyle(.blue)
                .font(.title2)
              Text("Add RSS Feed")
                .foregroundStyle(.primary)
              Spacer()
              Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.blue)
                .frame(width: 24)
              Text("Default Speed")
            }
          }
          .onChange(of: viewModel.defaultPlaybackSpeed) { _, newValue in
            viewModel.setDefaultPlaybackSpeed(newValue)
          }

          Toggle(isOn: Binding(
            get: { viewModel.autoPlayNextEpisode },
            set: { viewModel.setAutoPlayNextEpisode($0) }
          )) {
            HStack {
              Image(systemName: "shuffle")
                .foregroundStyle(.purple)
                .frame(width: 24)
              Text("Auto-Play Random Episode")
            }
          }
        } header: {
          Text("Playback")
        } footer: {
          Text("When enabled, a random unplayed episode will play when the queue is empty")
        }

        // MARK: - Region Section
        Section {
          Picker(selection: $viewModel.selectedRegion) {
            ForEach(Constants.podcastRegions, id: \.code) { region in
              Text(region.name).tag(region.code)
            }
          } label: {
            HStack {
              Image(systemName: "globe")
                .foregroundStyle(.blue)
                .frame(width: 24)
              Text("Default Region")
            }
          }
          .onChange(of: viewModel.selectedRegion) { _, newValue in
            viewModel.setSelectedRegion(newValue)
          }
        } header: {
          Text("Discovery")
        } footer: {
          Text("Region for browsing top podcasts on Home")
        }

        // MARK: - Translation Section
        Section {
          Picker(selection: Binding(
            get: { SubtitleSettingsManager.shared.targetLanguage },
            set: { SubtitleSettingsManager.shared.targetLanguage = $0 }
          )) {
            ForEach(TranslationTargetLanguage.allCases, id: \.self) { language in
              Text(language.displayName).tag(language)
            }
          } label: {
            HStack {
              Image(systemName: "translate")
                .foregroundStyle(.blue)
                .frame(width: 24)
              Text("Default Translation Language")
            }
          }
        } header: {
          Text("Translation")
        } footer: {
          Text("Default target language for translating transcripts and episode descriptions")
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
                .foregroundStyle(.blue)
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
              .foregroundStyle(.blue)
              .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
              Text("Speech Model")
              transcriptStatusText
            }

            Spacer()

            transcriptActionButton
          }

          Toggle(isOn: Binding(
            get: { SubtitleSettingsManager.shared.autoGenerateTranscripts },
            set: { SubtitleSettingsManager.shared.autoGenerateTranscripts = $0 }
          )) {
            HStack {
              Image(systemName: "waveform")
                .foregroundStyle(.orange)
                .frame(width: 24)
              VStack(alignment: .leading, spacing: 2) {
                Text("Auto-Generate Transcripts")
                Text("Generate when episodes are downloaded")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            }
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
                .foregroundStyle(.purple)
                .frame(width: 24)
              Text("AI Settings")
              Spacer()
              if AISettingsManager.shared.hasConfiguredProvider {
                Text(AISettingsManager.shared.selectedProvider.displayName)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              } else {
                Text("Not configured")
                  .font(.caption)
                  .foregroundStyle(.orange)
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
          NavigationLink {
            DataManagementView()
          } label: {
            HStack {
              Image(systemName: "externaldrive")
                .foregroundStyle(.gray)
                .frame(width: 24)
              Text("Data Management")
            }
          }
        } header: {
          Text("Storage")
        } footer: {
          Text("Manage cached images, downloads, transcripts, and AI analysis data")
        }

        // MARK: - About Section
        Section {
          HStack {
            Image(systemName: "info.circle")
              .foregroundStyle(.blue)
              .frame(width: 24)
            Text("Version")
            Spacer()
            Text("1.0.0")
              .foregroundStyle(.secondary)
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
      }
  }

  // MARK: - Notification Status Text

  @ViewBuilder
  private var notificationStatusText: some View {
    switch syncManager.notificationPermissionStatus {
    case .authorized:
      Text("Enabled")
        .font(.caption2)
        .foregroundStyle(.green)
    case .denied:
      Text("Denied - Enable in Settings")
        .font(.caption2)
        .foregroundStyle(.red)
    case .notDetermined:
      Text("Permission required")
        .font(.caption2)
        .foregroundStyle(.orange)
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
        .foregroundStyle(.secondary)
    case .notDownloaded:
      Text("Not installed")
        .font(.caption)
        .foregroundStyle(.orange)
    case .downloading(let progress):
      Text("Downloading \(Int(progress * 100))%")
        .font(.caption)
        .foregroundStyle(.blue)
    case .ready:
      Text("Ready")
        .font(.caption)
        .foregroundStyle(.green)
    case .error(let message):
      Text(message)
        .font(.caption)
        .foregroundStyle(.red)
        .lineLimit(1)
    case .simulatorNotSupported:
      Text("Requires physical device")
        .font(.caption)
        .foregroundStyle(.secondary)
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
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }
    case .ready:
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case .simulatorNotSupported:
      Image(systemName: "desktopcomputer")
        .foregroundStyle(.secondary)
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
              .foregroundStyle(.purple)
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
              .foregroundStyle(.purple)
          )
      }

      VStack(alignment: .leading, spacing: 4) {
        Text(feed.podcastInfo.title)
          .font(.body)
          .fontWeight(.medium)
          .lineLimit(1)

        Text("\(feed.podcastInfo.episodes.count) episodes")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 4)
  }
}

// MARK: - Add Feed Sheet View
struct AddFeedView: View {
  @Bindable var viewModel: SettingsViewModel
  var modelContext: ModelContext
  var onDismiss: () -> Void

  @FocusState private var isTextFieldFocused: Bool

  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        // Icon
        Image(systemName: "antenna.radiowaves.left.and.right")
          .font(.system(size: 60))
          .foregroundStyle(.blue)
          .padding(.top, 40)

        // Title and description
        VStack(spacing: 8) {
          Text("Add Podcast")
            .font(.title2)
            .fontWeight(.bold)

          Text("Enter the RSS feed URL to subscribe")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }

        // Input field
        VStack(spacing: 12) {
          TextField("https://example.com/feed.xml", text: $viewModel.rssUrlInput)
            .textFieldStyle(.plain)
            .padding(16)
            .background(Color.platformSystemGray6)
            .clipShape(.rect(cornerRadius: 12))
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
                .foregroundStyle(.secondary)
            }
          } else if !viewModel.successMessage.isEmpty {
            HStack(spacing: 6) {
              Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
              Text(viewModel.successMessage)
                .font(.caption)
                .foregroundStyle(.green)
            }
          } else if !viewModel.errorMessage.isEmpty {
            HStack(spacing: 6) {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
              Text(viewModel.errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
            }
          }
        }
        .padding(.horizontal, 24)

        Spacer()

        // Add button
        Button(action: {
          viewModel.addRssLink(modelContext: modelContext) {
            // Dismiss on success
            Task {
              try? await Task.sleep(for: .seconds(1.5))
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
          .foregroundStyle(.white)
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
