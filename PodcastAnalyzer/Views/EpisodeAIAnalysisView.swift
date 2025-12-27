//
//  EpisodeAIAnalysisView.swift
//  PodcastAnalyzer
//
//  Cloud-based AI analysis view using user-provided API keys (BYOK)
//  Uses CloudAIService for transcript analysis
//

import SwiftUI

/// View for cloud-based AI transcript analysis
struct EpisodeAIAnalysisView: View {
    @Bindable var viewModel: EpisodeDetailViewModel

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

            // Content area
            ScrollView {
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
        }
        .navigationTitle("AI Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showSettingsSheet = true }) {
                    Image(systemName: "gear")
                }
            }
        }
        .sheet(isPresented: $showSettingsSheet) {
            NavigationStack {
                AISettingsView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showSettingsSheet = false }
                        }
                    }
            }
        }
    }

    // MARK: - Configuration Banner

    @ViewBuilder
    private var configurationBanner: some View {
        if !settings.hasConfiguredProvider {
            // No API key configured
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("API Key Required")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Configure your cloud AI provider to analyze transcripts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Setup") {
                    showSettingsSheet = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()
            .background(Color.orange.opacity(0.1))
        } else if !viewModel.hasTranscript {
            // No transcript available
            HStack {
                Image(systemName: "doc.text")
                    .foregroundColor(.blue)

                Text("Generate a transcript first to enable AI analysis")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding()
            .background(Color.blue.opacity(0.1))
        } else {
            // Ready to analyze
            HStack {
                Image(systemName: settings.selectedProvider.iconName)
                    .foregroundColor(.green)

                Text("Using \(settings.selectedProvider.displayName) (\(settings.currentModel))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: { showSettingsSheet = true }) {
                    Text("Change")
                        .font(.caption)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.05))
        }
    }

    // MARK: - Tab Button

    private func tabButton(for tab: CloudAnalysisTab) -> some View {
        Button(action: { selectedTab = tab }) {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12))
                Text(tab.rawValue)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selectedTab == tab ? Color.blue : Color.gray.opacity(0.1))
            .foregroundColor(selectedTab == tab ? .white : .primary)
            .cornerRadius(8)
        }
    }

    // MARK: - Summary Tab

    private var summaryTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            tabHeader(
                title: "Episode Summary",
                description: "Get a comprehensive summary with key topics and takeaways"
            )

            if let result = viewModel.cloudAnalysisCache.summary {
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

            if let result = viewModel.cloudAnalysisCache.entities {
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

            if let result = viewModel.cloudAnalysisCache.highlights {
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

            if let result = viewModel.cloudAnalysisCache.fullAnalysis {
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

            // Question input
            HStack {
                TextField("Enter your question...", text: $questionInput)
                    .textFieldStyle(.roundedBorder)

                Button(action: {
                    viewModel.askCloudQuestion(questionInput)
                    questionInput = ""
                }) {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(questionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !canAnalyze)
            }

            // Previous Q&A history
            if !viewModel.cloudAnalysisCache.questionAnswers.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Previous Questions")
                        .font(.headline)

                    ForEach(Array(viewModel.cloudAnalysisCache.questionAnswers.enumerated().reversed()), id: \.offset) { index, qa in
                        qaCard(question: qa.question, answer: qa.answer, timestamp: qa.timestamp)
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
                .foregroundColor(.secondary)
        }
    }

    private var canAnalyze: Bool {
        settings.hasConfiguredProvider && viewModel.hasTranscript
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
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(!canAnalyze)
    }

    private func analysisResultCard(_ result: CloudAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Content
            Text(result.content)
                .font(.body)
                .textSelection(.enabled)

            Divider()

            // Metadata
            HStack {
                Label(result.provider.displayName, systemImage: result.provider.iconName)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text(result.model)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(result.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
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
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func qaCard(question: String, answer: String, timestamp: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Question
            HStack(alignment: .top) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(.blue)
                Text(question)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            // Answer
            Text(answer)
                .font(.body)
                .textSelection(.enabled)

            // Timestamp
            Text(timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
                            .foregroundColor(.blue)
                            .symbolEffect(.pulse)

                        Text(message)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }

                    if progress >= 0 {
                        Text("\(Int(progress * 100))% complete")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(12)

            case .completed:
                EmptyView()

            case .error(let message):
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
}

// MARK: - Flow Layout (for tag chips)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
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
