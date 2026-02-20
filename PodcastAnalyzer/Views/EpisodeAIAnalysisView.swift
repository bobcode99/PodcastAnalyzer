//
//  EpisodeAIAnalysisView.swift
//  PodcastAnalyzer
//
//  Cloud-based AI analysis view using user-provided API keys (BYOK)
//  Uses CloudAIService for transcript analysis
//

import SwiftUI

#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// View for cloud-based AI transcript analysis
struct EpisodeAIAnalysisView: View {
  private var toolbarPlacement: ToolbarItemPlacement {
    #if os(iOS)
    return .topBarTrailing
    #else
    return .primaryAction
    #endif
  }
  @Bindable var viewModel: EpisodeDetailViewModel
  var embedsOwnScroll: Bool = true  // When false, parent provides scrolling (for embedded mode)

  @State private var selectedTab: CloudAnalysisTab = .summary
  @State private var questionInput: String = ""
  @State private var showSettingsSheet = false

  private let settings = AISettingsManager.shared

  var body: some View {
    VStack(spacing: 0) {
      // Configuration banner
      configurationBanner

      // Tab selection
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
          ForEach(CloudAnalysisTab.allCases) { tab in
            tabButton(for: tab)
          }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
      }

      Divider()

      // Content area - conditionally wrap in ScrollView based on embedsOwnScroll
      if embedsOwnScroll {
        ScrollView {
          aiContentView
        }
      } else {
        aiContentView
      }
    }
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar {
      ToolbarItem(placement: toolbarPlacement) {
        Button(action: { showSettingsSheet = true }) {
          Image(systemName: "gear")
        }
      }
    }
    .sheet(isPresented: $showSettingsSheet) {
      NavigationStack {
        AISettingsView()
          #if os(iOS)
          .navigationBarTitleDisplayMode(.inline)
          #endif
          .toolbar {
            ToolbarItem(placement: toolbarPlacement) {
              Button("Done") { showSettingsSheet = false }
            }
          }
      }
    }
  }

  // MARK: - AI Content View (shared between scrolled and non-scrolled modes)

  private var aiContentView: some View {
    VStack(alignment: .leading, spacing: 16) {
      switch selectedTab {
      case .summary: summaryTab
      case .entities: entitiesTab
      case .highlights: highlightsTab
      case .fullAnalysis: fullAnalysisTab
      case .askQuestion: questionAnswerTab
      }
    }
    .padding()
  }

  // MARK: - Configuration Banner

  @ViewBuilder
  private var configurationBanner: some View {
    if !settings.hasConfiguredProvider {
      // No API key configured
      HStack {
        Image(systemName: "key.fill")
          .foregroundStyle(.orange)

        VStack(alignment: .leading, spacing: 2) {
          Text("API Key Required")
            .font(.subheadline)
            .fontWeight(.medium)
          Text("Configure your cloud AI provider to analyze transcripts")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Button("Setup") {
          showSettingsSheet = true
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .frame(minHeight: 60)
      .background(Color.orange.opacity(0.1))
    } else if !viewModel.hasTranscript {
      // No transcript available
      HStack {
        Image(systemName: "doc.text")
          .foregroundStyle(.blue)

        Text("Generate a transcript first to enable AI analysis")
          .font(.caption)
          .foregroundStyle(.secondary)

        Spacer()
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .frame(minHeight: 60)
      .background(Color.blue.opacity(0.1))
    } else {
      // Ready to analyze
      HStack {
        Image(systemName: settings.selectedProvider.iconName)
          .foregroundStyle(.green)

        Text("Using \(settings.selectedProvider.displayName) (\(settings.currentModel))")
          .font(.caption)
          .foregroundStyle(.secondary)

        Spacer()

        Button(action: { showSettingsSheet = true }) {
          Text("Change")
            .font(.caption)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .frame(minHeight: 60)
      .background(Color.green.opacity(0.05))
    }
  }

  // MARK: - Tab Button

  private func tabButton(for tab: CloudAnalysisTab) -> some View {
    Button {
      selectedTab = tab
    } label: {
      HStack(spacing: 6) {
        Image(systemName: tab.icon)
          .font(.system(size: 12))
        Text(tab.rawValue)
          .font(.subheadline)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(selectedTab == tab ? Color.accentColor : Color.clear)
      )
      .foregroundStyle(selectedTab == tab ? .white : .primary)
    }
    #if os(macOS)
    .buttonStyle(.plain)      // 🔑 THIS fixes the weird macOS behavior
    #endif
  }


  // MARK: - Summary Tab

  private var summaryTab: some View {
    VStack(alignment: .leading, spacing: 16) {
      tabHeader(
        title: "Episode Summary",
        description: "Get a comprehensive summary with key topics and takeaways"
      )

      if viewModel.isStreaming && viewModel.currentStreamingType == .summary {
        streamingResponseView
      } else if let result = viewModel.cloudAnalysisCache.summary {
        analysisResultCard(result)
      } else {
        generateButton(
          title: "Generate Summary",
          action: { viewModel.generateCloudAnalysis(type: .summary) }
        )
      }

      analysisStateView(for: viewModel.cloudAnalysisState)
    }
  }

  // MARK: - Entities Tab

  private var entitiesTab: some View {
    VStack(alignment: .leading, spacing: 16) {
      tabHeader(
        title: "Named Entities",
        description: "Extract people, organizations, products, and locations"
      )

      if viewModel.isStreaming && viewModel.currentStreamingType == .entities {
        streamingResponseView
      } else if let result = viewModel.cloudAnalysisCache.entities {
        analysisResultCard(result)
      } else {
        generateButton(
          title: "Extract Entities",
          action: { viewModel.generateCloudAnalysis(type: .entities) }
        )
      }

      analysisStateView(for: viewModel.cloudAnalysisState)
    }
  }

  // MARK: - Highlights Tab

  private var highlightsTab: some View {
    VStack(alignment: .leading, spacing: 16) {
      tabHeader(
        title: "Episode Highlights",
        description: "Find key moments, quotes, and action items"
      )

      if viewModel.isStreaming && viewModel.currentStreamingType == .highlights {
        streamingResponseView
      } else if let result = viewModel.cloudAnalysisCache.highlights {
        analysisResultCard(result)
      } else {
        generateButton(
          title: "Generate Highlights",
          action: { viewModel.generateCloudAnalysis(type: .highlights) }
        )
      }

      analysisStateView(for: viewModel.cloudAnalysisState)
    }
  }

  // MARK: - Full Analysis Tab

  private var fullAnalysisTab: some View {
    VStack(alignment: .leading, spacing: 16) {
      tabHeader(
        title: "Full Analysis",
        description: "Comprehensive analysis including summary, topics, quotes, and more"
      )

      if viewModel.isStreaming && viewModel.currentStreamingType == .fullAnalysis {
        streamingResponseView
      } else if let result = viewModel.cloudAnalysisCache.fullAnalysis {
        analysisResultCard(result)
      } else {
        generateButton(
          title: "Generate Full Analysis",
          action: { viewModel.generateCloudAnalysis(type: .fullAnalysis) }
        )
      }

      analysisStateView(for: viewModel.cloudAnalysisState)
    }
  }

  // MARK: - Q&A Tab

  private var questionAnswerTab: some View {
    VStack(alignment: .leading, spacing: 16) {
      tabHeader(
        title: "Ask Questions",
        description: "Ask any question about the episode content"
      )

      // Question input with X button and Enter to send
      HStack(spacing: 8) {
        HStack {
          TextField("Enter your question...", text: $questionInput)
            .textFieldStyle(.plain)
            .onSubmit {
              submitQuestion()
            }

          // X button to clear input
          if !questionInput.isEmpty {
            Button(action: {
              questionInput = ""
              #if os(iOS)
              // Hide keyboard when clearing
              UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
              #endif
            }) {
              Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.platformSystemGray6)
        .clipShape(.rect(cornerRadius: 10))

        Button(action: submitQuestion) {
          Image(systemName: "paperplane.fill")
            .font(.system(size: 18))
        }
        .disabled(
          questionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !canAnalyze)
      }
      #if os(iOS)
      .submitLabel(.send)
      #endif

      // Previous Q&A history
      if !viewModel.cloudAnalysisCache.questionAnswers.isEmpty {
        VStack(alignment: .leading, spacing: 12) {
          Text("Previous Questions")
            .font(.headline)

          ForEach(
            Array(viewModel.cloudAnalysisCache.questionAnswers.enumerated().reversed()),
            id: \.offset
          ) { _, qa in
            qaResultCard(qa)
          }
        }
      }

      analysisStateView(for: viewModel.cloudQuestionState)
    }
  }

  // MARK: - Helper Views

  private func tabHeader(title: String, description: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.title2)
        .bold()
      Text(description)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var canAnalyze: Bool {
    settings.hasConfiguredProvider && viewModel.hasTranscript
  }

  private func submitQuestion() {
    let trimmed = questionInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, canAnalyze else { return }
    viewModel.askCloudQuestion(questionInput)
    questionInput = ""
    #if os(iOS)
    // Hide keyboard after submitting
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    #endif
  }

  private func generateButton(title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack {
        Image(systemName: "sparkles")
        Text(title)
      }
      .frame(maxWidth: .infinity)
      .padding()
      .background(canAnalyze ? Color.blue : Color.gray)
      .foregroundStyle(.white)
      .clipShape(.rect(cornerRadius: 12))
    }
    .disabled(!canAnalyze)
  }

  private func analysisResultCard(_ result: CloudAnalysisResult) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      // Show warning if JSON parsing failed
      if let warning = result.jsonParseWarning {
        HStack(spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
          VStack(alignment: .leading, spacing: 2) {
            Text("Response Format Warning")
              .font(.caption)
              .fontWeight(.semibold)
              .foregroundStyle(.orange)
            Text(warning)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .clipShape(.rect(cornerRadius: 8))
      }

      // Structured content based on type
      switch result.type {
      case .summary:
        summaryResultView(result)
      case .entities:
        entitiesResultView(result)
      case .highlights:
        highlightsResultView(result)
      case .fullAnalysis:
        fullAnalysisResultView(result)
      }

      Divider()

      // Metadata
      HStack {
        Label(result.provider.displayName, systemImage: result.provider.iconName)
          .font(.caption)
          .foregroundStyle(.secondary)

        Spacer()

        Text(result.model)
          .font(.caption)
          .foregroundStyle(.secondary)

        Text(result.timestamp.formatted(date: .abbreviated, time: .shortened))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      // Regenerate button
      Button(action: {
        if let type = selectedTab.analysisType {
          viewModel.clearCloudAnalysis(type: type)
          viewModel.generateCloudAnalysis(type: type)
        }
      }) {
        Label("Regenerate", systemImage: "arrow.clockwise")
          .font(.caption)
      }
      .buttonStyle(.bordered)
    }
    .padding()
    .background(Color.platformSystemGray6)
    .clipShape(.rect(cornerRadius: 12))
  }

  // MARK: - Structured Result Views

  @ViewBuilder
  private func summaryResultView(_ result: CloudAnalysisResult) -> some View {
    if let parsed = result.parsedSummary {
      VStack(alignment: .leading, spacing: 16) {
        // Summary text
        Text(parsed.summary)
          .font(.body)
          .textSelection(.enabled)

        // Main topics as chips
        if !parsed.mainTopics.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Label("Main Topics", systemImage: "list.bullet")
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundStyle(.blue)

            FlowLayout(spacing: 8) {
              ForEach(parsed.mainTopics, id: \.self) { topic in
                Text(topic)
                  .font(.caption)
                  .padding(.horizontal, 10)
                  .padding(.vertical, 6)
                  .background(Color.blue.opacity(0.1))
                  .foregroundStyle(.blue)
                  .clipShape(.rect(cornerRadius: 16))
              }
            }
          }
        }

        // Key takeaways
        if !parsed.keyTakeaways.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Label("Key Takeaways", systemImage: "lightbulb")
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundStyle(.orange)

            ForEach(Array(parsed.keyTakeaways.enumerated()), id: \.offset) { _, takeaway in
              HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(.green)
                  .font(.caption)
                Text(takeaway)
                  .font(.subheadline)
              }
            }
          }
        }

        // Target audience & engagement
        HStack(spacing: 16) {
          if !parsed.targetAudience.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
              Text("Target Audience")
                .font(.caption)
                .foregroundStyle(.secondary)
              Text(parsed.targetAudience)
                .font(.caption)
                .fontWeight(.medium)
            }
          }

          if !parsed.engagementLevel.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
              Text("Engagement")
                .font(.caption)
                .foregroundStyle(.secondary)
              HStack(spacing: 4) {
                engagementIcon(parsed.engagementLevel)
                Text(parsed.engagementLevel.capitalized)
                  .font(.caption)
                  .fontWeight(.medium)
              }
            }
          }
        }
      }
    } else {
      Text(result.content)
        .font(.body)
        .textSelection(.enabled)
    }
  }

  @ViewBuilder
  private func entitiesResultView(_ result: CloudAnalysisResult) -> some View {
    if let parsed = result.parsedEntities {
      VStack(alignment: .leading, spacing: 16) {
        entitySection(title: "People", icon: "person.fill", items: parsed.people, color: .blue)
        entitySection(
          title: "Organizations", icon: "building.2.fill", items: parsed.organizations,
          color: .purple)
        entitySection(
          title: "Products", icon: "shippingbox.fill", items: parsed.products, color: .orange)
        entitySection(
          title: "Locations", icon: "mappin.circle.fill", items: parsed.locations, color: .green)
        entitySection(title: "Resources", icon: "book.fill", items: parsed.resources, color: .red)
      }
    } else {
      Text(result.content)
        .font(.body)
        .textSelection(.enabled)
    }
  }

  @ViewBuilder
  private func entitySection(title: String, icon: String, items: [String], color: Color)
    -> some View
  {
    if !items.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Label(title, systemImage: icon)
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundStyle(color)

        FlowLayout(spacing: 8) {
          ForEach(items, id: \.self) { item in
            Text(item)
              .font(.caption)
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
              .background(color.opacity(0.1))
              .foregroundStyle(color)
              .clipShape(.rect(cornerRadius: 16))
          }
        }
      }
    }
  }

  @ViewBuilder
  private func highlightsResultView(_ result: CloudAnalysisResult) -> some View {
    if let parsed = result.parsedHighlights {
      VStack(alignment: .leading, spacing: 16) {
        // Best quote card
        if !parsed.bestQuote.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Label("Best Quote", systemImage: "quote.opening")
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundStyle(.purple)

            Text("\"\(parsed.bestQuote)\"")
              .font(.body)
              .italic()
              .padding()
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(
                RoundedRectangle(cornerRadius: 8)
                  .fill(Color.purple.opacity(0.1))
              )
              .overlay(
                Rectangle()
                  .fill(Color.purple)
                  .frame(width: 4),
                alignment: .leading
              )
          }
        }

        // Highlights
        if !parsed.highlights.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Label("Highlights", systemImage: "star.fill")
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundStyle(.yellow)

            ForEach(Array(parsed.highlights.enumerated()), id: \.offset) { _, highlight in
              HStack(alignment: .top, spacing: 8) {
                Image(systemName: "star.fill")
                  .foregroundStyle(.yellow)
                  .font(.caption)
                Text(highlight)
                  .font(.subheadline)
              }
            }
          }
        }

        // Action items
        if !parsed.actionItems.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Label("Action Items", systemImage: "checklist")
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundStyle(.green)

            ForEach(Array(parsed.actionItems.enumerated()), id: \.offset) { _, item in
              HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.right.circle.fill")
                  .foregroundStyle(.green)
                  .font(.caption)
                Text(item)
                  .font(.subheadline)
              }
            }
          }
        }

        // Controversial points
        if let controversial = parsed.controversialPoints, !controversial.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Label("Controversial Points", systemImage: "exclamationmark.triangle.fill")
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundStyle(.orange)

            ForEach(Array(controversial.enumerated()), id: \.offset) { _, point in
              HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                  .foregroundStyle(.orange)
                  .font(.caption)
                Text(point)
                  .font(.subheadline)
              }
            }
          }
        }

        // Entertaining moments
        if let entertaining = parsed.entertainingMoments, !entertaining.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Label("Entertaining Moments", systemImage: "face.smiling.fill")
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundStyle(.pink)

            ForEach(Array(entertaining.enumerated()), id: \.offset) { _, moment in
              HStack(alignment: .top, spacing: 8) {
                Image(systemName: "face.smiling.fill")
                  .foregroundStyle(.pink)
                  .font(.caption)
                Text(moment)
                  .font(.subheadline)
              }
            }
          }
        }
      }
    } else {
      selectableText(result.content)
    }
  }

  // MARK: - Full Analysis Result View

  @ViewBuilder
  private func fullAnalysisResultView(_ result: CloudAnalysisResult) -> some View {
    if let parsed = result.parsedFullAnalysis {
      VStack(alignment: .leading, spacing: 20) {
        // Overview
        VStack(alignment: .leading, spacing: 8) {
          Label("Overview", systemImage: "doc.text")
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.blue)

          selectableText(parsed.overview)
        }

        // Main Topics
        if !parsed.mainTopics.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            Label("Main Topics", systemImage: "list.bullet.rectangle")
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundStyle(.purple)

            ForEach(Array(parsed.mainTopics.enumerated()), id: \.offset) { _, topic in
              VStack(alignment: .leading, spacing: 6) {
                Text(topic.topic)
                  .font(.subheadline)
                  .fontWeight(.medium)
                  .foregroundStyle(.primary)

                selectableText(topic.summary)
                  .font(.caption)
                  .foregroundStyle(.secondary)

                ForEach(topic.keyPoints, id: \.self) { point in
                  HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle.fill")
                      .font(.system(size: 4))
                      .foregroundStyle(.purple)
                      .padding(.top, 6)
                    selectableText(point)
                      .font(.caption)
                  }
                }
              }
              .padding()
              .background(Color.purple.opacity(0.05))
              .clipShape(.rect(cornerRadius: 8))
            }
          }
        }

        // Key Insights
        if !parsed.keyInsights.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Label("Key Insights", systemImage: "lightbulb.fill")
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundStyle(.orange)

            ForEach(Array(parsed.keyInsights.enumerated()), id: \.offset) { _, insight in
              HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb.fill")
                  .foregroundStyle(.orange)
                  .font(.caption)
                selectableText(insight)
              }
            }
          }
        }

        // Notable Quotes
        if !parsed.notableQuotes.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Label("Notable Quotes", systemImage: "quote.opening")
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundStyle(.green)

            ForEach(Array(parsed.notableQuotes.enumerated()), id: \.offset) { _, quote in
              selectableText("\"\(quote)\"")
                .font(.subheadline)
                .italic()
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                  RoundedRectangle(cornerRadius: 8)
                    .fill(Color.green.opacity(0.1))
                )
                .overlay(
                  Rectangle()
                    .fill(Color.green)
                    .frame(width: 4),
                  alignment: .leading
                )
            }
          }
        }

        // Actionable Advice
        if let advice = parsed.actionableAdvice, !advice.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Label("Actionable Advice", systemImage: "checkmark.circle.fill")
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundStyle(.teal)

            ForEach(Array(advice.enumerated()), id: \.offset) { _, item in
              HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.right.circle.fill")
                  .foregroundStyle(.teal)
                  .font(.caption)
                selectableText(item)
              }
            }
          }
        }

        // Conclusion
        VStack(alignment: .leading, spacing: 8) {
          Label("Conclusion", systemImage: "checkmark.seal.fill")
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.indigo)

          selectableText(parsed.conclusion)
            .padding()
            .background(Color.indigo.opacity(0.1))
            .clipShape(.rect(cornerRadius: 8))
        }
      }
    } else {
      selectableText(result.content)
    }
  }

  private func engagementIcon(_ level: String) -> some View {
    let iconName: String
    let color: Color
    switch level.lowercased() {
    case "high":
      iconName = "flame.fill"
      color = .red
    case "medium":
      iconName = "circle.lefthalf.filled"
      color = .orange
    default:
      iconName = "circle"
      color = .gray
    }
    return Image(systemName: iconName)
      .foregroundStyle(color)
      .font(.caption)
  }

  // MARK: - Selectable Text with Context Menu

  /// Text view with selection enabled and context menu for copy, translate, search
  private func selectableText(_ content: String) -> some View {
    Text(content)
      .font(.body)
      .textSelection(.enabled)
      .contextMenu {
        Button {
          PlatformClipboard.string = content
        } label: {
          Label("Copy", systemImage: "doc.on.doc")
        }

        Button {
          // Open in Safari for web search
          if let query = content.prefix(100).addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: "https://www.google.com/search?q=\(query)")
          {
            #if os(iOS)
            UIApplication.shared.open(url)
            #else
            NSWorkspace.shared.open(url)
            #endif
          }
        } label: {
          Label("Search Web", systemImage: "magnifyingglass")
        }

        ShareLink(item: content) {
          Label("Share", systemImage: "square.and.arrow.up")
        }
      }
  }

  // MARK: - Streaming Response View

  private var streamingResponseView: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Header with streaming indicator
      HStack {
        Image(systemName: "sparkles")
          .foregroundStyle(.blue)
          .symbolEffect(.pulse)
        Text("Generating...")
          .font(.subheadline)
          .fontWeight(.medium)
          .foregroundStyle(.blue)
        Spacer()
        ProgressView()
          .scaleEffect(0.8)
      }

      // Streaming text content
      if !viewModel.streamingText.isEmpty {
        Text(viewModel.streamingText)
          .font(.body)
          .textSelection(.enabled)
          .animation(.easeInOut(duration: 0.1), value: viewModel.streamingText)
      } else {
        HStack {
          Text("Waiting for response...")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      // Metadata
      HStack {
        Label(
          settings.selectedProvider.displayName, systemImage: settings.selectedProvider.iconName
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        Spacer()
        Text(settings.currentModel)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding()
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(Color.blue.opacity(0.05))
        .overlay(
          RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
        )
    )
  }

  /// Beautiful Q&A result card with all parsed fields
  private func qaResultCard(_ result: CloudQAResult) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      // Warning if JSON parsing failed
      if let warning = result.jsonParseWarning {
        HStack(spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
          Text(warning)
            .font(.caption)
            .foregroundStyle(.orange)
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .clipShape(.rect(cornerRadius: 6))
      }

      // Question with enhanced styling
      HStack(alignment: .top, spacing: 10) {
        ZStack {
          Circle()
            .fill(Color.blue.opacity(0.15))
            .frame(width: 32, height: 32)
          Image(systemName: "bubble.left.fill")
            .font(.system(size: 14))
            .foregroundStyle(.blue)
        }
        VStack(alignment: .leading, spacing: 4) {
          Text("Question")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
          Text(result.question)
            .font(.subheadline)
            .fontWeight(.medium)
        }
      }

      // Answer with enhanced styling and context menu
      HStack(alignment: .top, spacing: 10) {
        ZStack {
          Circle()
            .fill(Color.green.opacity(0.15))
            .frame(width: 32, height: 32)
          Image(systemName: "text.bubble.fill")
            .font(.system(size: 14))
            .foregroundStyle(.green)
        }
        VStack(alignment: .leading, spacing: 4) {
          Text("Answer")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
          Text(result.answer)
            .font(.body)
            .textSelection(.enabled)
            .contextMenu {
              Button {
                PlatformClipboard.string = result.answer
              } label: {
                Label("Copy Answer", systemImage: "doc.on.doc")
              }

              Button {
                if let query = result.answer.prefix(100).addingPercentEncoding(
                  withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://www.google.com/search?q=\(query)")
                {
                  #if os(iOS)
                  UIApplication.shared.open(url)
                  #else
                  NSWorkspace.shared.open(url)
                  #endif
                }
              } label: {
                Label("Search Web", systemImage: "safari")
              }

              ShareLink(item: result.answer) {
                Label("Share", systemImage: "square.and.arrow.up")
              }
            }
        }
      }

      // Confidence badge
      if result.confidence != "unknown" {
        HStack(spacing: 6) {
          Image(systemName: confidenceIcon(result.confidence))
            .foregroundStyle(confidenceColor(result.confidence))
          Text("Confidence: \(result.confidence.capitalized)")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(confidenceColor(result.confidence))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(confidenceColor(result.confidence).opacity(0.1))
        .clipShape(.rect(cornerRadius: 16))
      }

      // Related topics as chips
      if let topics = result.relatedTopics, !topics.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Text("Related Topics")
            .font(.caption)
            .foregroundStyle(.secondary)

          FlowLayout(spacing: 6) {
            ForEach(topics, id: \.self) { topic in
              Text(topic)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.1))
                .foregroundStyle(.purple)
                .clipShape(.rect(cornerRadius: 12))
            }
          }
        }
      }

      // Sources from transcript
      if let sources = result.sources, !sources.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Label("Sources from Transcript", systemImage: "quote.bubble")
            .font(.caption)
            .foregroundStyle(.secondary)

          ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
            Text("\"\(source)\"")
              .font(.caption)
              .italic()
              .foregroundStyle(.secondary)
              .padding(8)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(Color.platformSystemGray5)
              .clipShape(.rect(cornerRadius: 6))
          }
        }
      }

      Divider()

      // Metadata footer
      HStack {
        Label(result.provider.displayName, systemImage: result.provider.iconName)
          .font(.caption2)
          .foregroundStyle(.secondary)
        Spacer()
        Text(result.model)
          .font(.caption2)
          .foregroundStyle(.secondary)
        Text(result.timestamp.formatted(date: .abbreviated, time: .shortened))
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .padding()
    .background(Color.platformSystemGray6)
    .clipShape(.rect(cornerRadius: 12))
  }

  /// Get icon for confidence level
  private func confidenceIcon(_ confidence: String) -> String {
    switch confidence.lowercased() {
    case "high": return "checkmark.seal.fill"
    case "medium": return "circle.lefthalf.filled"
    case "low": return "exclamationmark.circle"
    default: return "questionmark.circle"
    }
  }

  /// Get color for confidence level
  private func confidenceColor(_ confidence: String) -> Color {
    switch confidence.lowercased() {
    case "high": return .green
    case "medium": return .orange
    case "low": return .red
    default: return .gray
    }
  }

  private func analysisStateView(for state: AnalysisState) -> some View {
    Group {
      switch state {
      case .idle:
        EmptyView()

      case .analyzing(let progress, let message):
        VStack(spacing: 12) {
          if progress < 0 {
            ProgressView()
              .scaleEffect(1.2)
          } else {
            ProgressView(value: progress)
              .progressViewStyle(.linear)
          }

          HStack(spacing: 8) {
            Image(systemName: "sparkles")
              .foregroundStyle(.blue)
              .symbolEffect(.pulse)

            Text(message)
              .font(.subheadline)
              .foregroundStyle(.primary)
          }

          if progress >= 0 {
            Text("\(Int(progress * 100))% complete")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .clipShape(.rect(cornerRadius: 12))

      case .completed:
        EmptyView()

      case .error(let message):
        HStack {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
          Text(message)
            .font(.caption)
            .foregroundStyle(.red)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .clipShape(.rect(cornerRadius: 8))
      }
    }
  }
}

// MARK: - Flow Layout (for tag chips)

struct FlowLayout: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let result = FlowResult(
      in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
    return result.size
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
    for (index, subview) in subviews.enumerated() {
      subview.place(
        at: CGPoint(
          x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY),
        proposal: .unspecified)
    }
  }

  struct FlowResult {
    var frames: [CGRect] = []
    var size: CGSize = .zero

    init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
      var currentX: CGFloat = 0
      var currentY: CGFloat = 0
      var lineHeight: CGFloat = 0

      for subview in subviews {
        let size = subview.sizeThatFits(.unspecified)

        if currentX + size.width > maxWidth && currentX > 0 {
          currentX = 0
          currentY += lineHeight + spacing
          lineHeight = 0
        }

        frames.append(CGRect(x: currentX, y: currentY, width: size.width, height: size.height))
        lineHeight = max(lineHeight, size.height)
        currentX += size.width + spacing
      }

      self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
    }
  }
}
