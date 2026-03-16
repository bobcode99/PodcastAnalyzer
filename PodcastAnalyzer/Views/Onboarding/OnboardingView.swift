//
//  OnboardingView.swift
//  PodcastAnalyzer
//
//  First-launch onboarding guide. Shown once; skippable.
//  After completion or skip the flag is persisted via AppStorage
//  so the screen never appears again.
//

#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

struct OnboardingView: View {
  @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
  @State private var currentPage = 0
  @State private var showFilePicker = false
  @State private var importErrorMessage: String?

  var body: some View {
    TabView(selection: $currentPage) {
      WelcomeOnboardingPage(onNext: { currentPage = 1 })
        .tag(0)
      ImportOnboardingPage(
        onImport: { showFilePicker = true },
        onSkip: { hasCompletedOnboarding = true }
      )
      .tag(1)
    }
    .tabViewStyle(.page)
    .indexViewStyle(.page(backgroundDisplayMode: .always))
    .ignoresSafeArea()
    .fileImporter(
      isPresented: $showFilePicker,
      allowedContentTypes: [.xml, .data],
      allowsMultipleSelection: false
    ) { result in
      handleFileImport(result)
    }
    .alert(
      "Import Error",
      isPresented: Binding(
        get: { importErrorMessage != nil },
        set: { if !$0 { importErrorMessage = nil } }
      )
    ) {
      Button("OK") { importErrorMessage = nil }
    } message: {
      if let message = importErrorMessage {
        Text(message)
      }
    }
  }

  private func handleFileImport(_ result: Result<[URL], Error>) {
    switch result {
    case .failure(let error):
      importErrorMessage = "Couldn't open the file: \(error.localizedDescription)"

    case .success(let urls):
      guard let url = urls.first else { return }

      let accessing = url.startAccessingSecurityScopedResource()
      defer { if accessing { url.stopAccessingSecurityScopedResource() } }

      guard let data = try? Data(contentsOf: url) else {
        importErrorMessage = "Couldn't read the selected file."
        return
      }

      let rssURLs = OPMLParser.parse(data: data)
      guard !rssURLs.isEmpty else {
        importErrorMessage = "No podcast subscriptions found. Please export an OPML file from Apple Podcasts (Library → ··· → Export Subscriptions)."
        return
      }

      // Dismiss onboarding first, then start the batch import.
      // PodcastImportManager will show its own progress sheet in ContentView.
      hasCompletedOnboarding = true
      Task {
        try? await Task.sleep(for: .milliseconds(400))
        await PodcastImportManager.shared.importPodcasts(from: rssURLs)
      }
    }
  }
}

// MARK: - Welcome Page

private struct WelcomeOnboardingPage: View {
  let onNext: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      Spacer()

      Image(systemName: "waveform.circle.fill")
        .font(.system(size: 96))
        .foregroundStyle(.blue.gradient)
        .padding(.bottom, 28)

      VStack(spacing: 10) {
        Text("Welcome to\nPodcastAnalyzer")
          .font(.largeTitle)
          .fontWeight(.bold)
          .multilineTextAlignment(.center)

        Text("Listen, download, and analyze podcasts\nwith AI-powered insights.")
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }

      Spacer()

      VStack(spacing: 16) {
        FeatureRow(
          icon: "arrow.down.circle.fill",
          color: .green,
          title: "Download Episodes",
          description: "Save episodes for offline listening"
        )
        FeatureRow(
          icon: "text.bubble.fill",
          color: .purple,
          title: "AI Transcripts",
          description: "On-device speech-to-text with Whisper"
        )
        FeatureRow(
          icon: "sparkles",
          color: .orange,
          title: "Smart Analysis",
          description: "Summaries, highlights, and Q&A"
        )
      }
      .padding(.horizontal, 28)

      Spacer()

      Button("Get Started", action: onNext)
        .font(.headline)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.blue, in: .rect(cornerRadius: 14))
        .padding(.horizontal, 24)
        .padding(.bottom, 52)
    }
  }
}

// MARK: - Import Page

private struct ImportOnboardingPage: View {
  let onImport: () -> Void
  let onSkip: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      Spacer()

      Image(systemName: "square.and.arrow.down.fill")
        .font(.system(size: 80))
        .foregroundStyle(.blue.gradient)
        .padding(.bottom, 24)

      VStack(spacing: 10) {
        Text("Bring Your Podcasts")
          .font(.largeTitle)
          .fontWeight(.bold)
          .multilineTextAlignment(.center)

        Text("Already subscribed in Apple Podcasts?\nImport all your shows in seconds.")
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 32)
      }

      Spacer()

      // How-to steps
      VStack(alignment: .leading, spacing: 12) {
        Text("How to export from Apple Podcasts")
          .font(.subheadline)
          .fontWeight(.semibold)

        ForEach(exportSteps, id: \.self) { step in
          HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(.green)
              .font(.subheadline)
            Text(step)
              .font(.subheadline)
          }
        }
      }
      .padding(18)
      .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
      .padding(.horizontal, 24)

      Spacer()

      VStack(spacing: 12) {
        Button(action: onImport) {
          Label("Import from Apple Podcasts", systemImage: "square.and.arrow.down")
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(.blue, in: .rect(cornerRadius: 14))
        }

        Button("Start Fresh", action: onSkip)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .padding(.vertical, 8)
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 52)
    }
  }

  private let exportSteps = [
    "Open the Apple Podcasts app",
    "Tap your profile → Library → Podcasts",
    "Tap ··· → Export Subscriptions",
    "Save the .opml file, then select it here",
  ]
}

// MARK: - Feature Row

private struct FeatureRow: View {
  let icon: String
  let color: Color
  let title: String
  let description: String

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: icon)
        .font(.title2)
        .foregroundStyle(color)
        .frame(width: 36)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.subheadline)
          .fontWeight(.semibold)
        Text(description)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()
    }
  }
}

#Preview {
  OnboardingView()
}

#endif
