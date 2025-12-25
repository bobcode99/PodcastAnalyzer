//
//  EpisodeAIAnalysisView.swift
//  PodcastAnalyzer
//
//  Created by Claude Code
//  UI for displaying AI-powered episode analysis
//

import SwiftUI
import FoundationModels

/// View displaying AI analysis results for an episode
@available(iOS 26.0, macOS 26.0, *)
struct EpisodeAIAnalysisView: View {
    @Bindable var viewModel: EpisodeDetailViewModel

    @State private var selectedAnalysisTab: Int = 0
    @State private var questionInput: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Availability banner
            if !viewModel.aiAvailability.isAvailable {
                availabilityBanner
            }

            // Tab selection for different analyses
            Picker("Analysis Type", selection: $selectedAnalysisTab) {
                Text("Summary").tag(0)
                Text("Tags").tag(1)
                Text("Entities").tag(2)
                Text("Highlights").tag(3)
                Text("Q&A").tag(4)
            }
            .pickerStyle(.segmented)
            .padding()

            // Content area
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedAnalysisTab {
                    case 0: summaryTab
                    case 1: tagsTab
                    case 2: entitiesTab
                    case 3: highlightsTab
                    case 4: questionAnswerTab
                    default: EmptyView()
                    }
                }
                .padding()
            }
        }
        .navigationTitle("AI Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.checkAIAvailability()
        }
    }

    // MARK: - Availability Banner

    private var availabilityBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)

            Text(viewModel.aiAvailability.message ?? "AI unavailable")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.1))
    }

    // MARK: - Summary Tab

    private var summaryTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Episode Summary")
                .font(.title2)
                .bold()

            if let summary = viewModel.episodeSummary {
                // Display summary
                summaryCard(summary)
            } else {
                // Generate button
                generateButton(
                    title: "Generate AI Summary",
                    action: { viewModel.generateAISummary() }
                )
            }

            // Analysis state feedback
            analysisStateView
        }
    }

    private func summaryCard(_ summary: EpisodeSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Main summary
            VStack(alignment: .leading, spacing: 8) {
                Text("Overview")
                    .font(.headline)
                Text(summary.summary)
                    .font(.body)
            }

            Divider()

            // Main topics
            VStack(alignment: .leading, spacing: 8) {
                Text("Main Topics")
                    .font(.headline)
                ForEach(summary.mainTopics, id: \.self) { topic in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                        Text(topic)
                    }
                }
            }

            Divider()

            // Key takeaways
            VStack(alignment: .leading, spacing: 8) {
                Text("Key Takeaways")
                    .font(.headline)
                ForEach(summary.keyTakeaways, id: \.self) { takeaway in
                    HStack(alignment: .top, spacing: 8) {
                        Text("→")
                            .foregroundColor(.blue)
                        Text(takeaway)
                    }
                }
            }

            Divider()

            // Metadata
            HStack {
                VStack(alignment: .leading) {
                    Text("Target Audience")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(summary.targetAudience)
                        .font(.subheadline)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("Engagement")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    engagementBadge(summary.engagementLevel)
                }
            }

            // Regenerate button
            Button(action: {
                viewModel.clearAIResults()
                viewModel.generateAISummary()
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

    private func engagementBadge(_ level: String) -> some View {
        Text(level.capitalized)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(engagementColor(level).opacity(0.2))
            .foregroundColor(engagementColor(level))
            .cornerRadius(8)
    }

    private func engagementColor(_ level: String) -> Color {
        switch level.lowercased() {
        case "high": return .green
        case "medium": return .orange
        case "low": return .red
        default: return .gray
        }
    }

    // MARK: - Tags Tab

    private var tagsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tags & Categories")
                .font(.title2)
                .bold()

            if let tags = viewModel.episodeTags {
                tagsCard(tags)
            } else {
                generateButton(
                    title: "Generate Tags",
                    action: { viewModel.generateAITags() }
                )
            }

            analysisStateView
        }
    }

    private func tagsCard(_ tags: EpisodeTags) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category
            VStack(alignment: .leading, spacing: 8) {
                Text("Category")
                    .font(.headline)
                HStack {
                    categoryBadge(tags.primaryCategory, isPrimary: true)
                    ForEach(tags.secondaryCategories, id: \.self) { category in
                        categoryBadge(category, isPrimary: false)
                    }
                }
            }

            Divider()

            // Tags as chips
            VStack(alignment: .leading, spacing: 8) {
                Text("Tags")
                    .font(.headline)
                FlowLayout(spacing: 8) {
                    ForEach(tags.tags, id: \.self) { tag in
                        tagChip(tag)
                    }
                }
            }

            Divider()

            // Difficulty
            HStack {
                Text("Difficulty Level")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                difficultyBadge(tags.difficultyLevel)
            }

            // Technical terms
            if !tags.technicalTerms.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Technical Terms")
                        .font(.headline)
                    ForEach(tags.technicalTerms, id: \.self) { term in
                        Text("• \(term)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Regenerate button
            Button(action: {
                viewModel.episodeTags = nil
                viewModel.generateAITags()
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

    private func categoryBadge(_ category: String, isPrimary: Bool) -> some View {
        Text(category)
            .font(.caption)
            .bold(isPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isPrimary ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
            .foregroundColor(isPrimary ? .blue : .secondary)
            .cornerRadius(8)
    }

    private func tagChip(_ tag: String) -> some View {
        Text("#\(tag)")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(6)
    }

    private func difficultyBadge(_ level: String) -> some View {
        Text(level.capitalized)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(difficultyColor(level).opacity(0.2))
            .foregroundColor(difficultyColor(level))
            .cornerRadius(8)
    }

    private func difficultyColor(_ level: String) -> Color {
        switch level.lowercased() {
        case "beginner": return .green
        case "intermediate": return .orange
        case "advanced": return .red
        default: return .gray
        }
    }

    // MARK: - Entities Tab

    private var entitiesTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Named Entities")
                .font(.title2)
                .bold()

            if let entities = viewModel.episodeEntities {
                entitiesCard(entities)
            } else {
                generateButton(
                    title: "Extract Entities",
                    action: { viewModel.extractAIEntities() }
                )
            }

            analysisStateView
        }
    }

    private func entitiesCard(_ entities: EpisodeEntities) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // People
            if !entities.people.isEmpty {
                entitySection(title: "People", icon: "person.2.fill", items: entities.people)
            }

            // Organizations
            if !entities.organizations.isEmpty {
                entitySection(title: "Organizations", icon: "building.2.fill", items: entities.organizations)
            }

            // Products
            if !entities.products.isEmpty {
                entitySection(title: "Products & Technologies", icon: "cpu", items: entities.products)
            }

            // Locations
            if !entities.locations.isEmpty {
                entitySection(title: "Locations", icon: "location.fill", items: entities.locations)
            }

            // Resources
            if !entities.resources.isEmpty {
                entitySection(title: "Resources", icon: "book.fill", items: entities.resources)
            }

            // Regenerate button
            Button(action: {
                viewModel.episodeEntities = nil
                viewModel.extractAIEntities()
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

    private func entitySection(title: String, icon: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(.blue)

            ForEach(items, id: \.self) { item in
                Text("• \(item)")
                    .font(.body)
            }

            Divider()
        }
    }

    // MARK: - Highlights Tab

    private var highlightsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Episode Highlights")
                .font(.title2)
                .bold()

            if let highlights = viewModel.episodeHighlights {
                highlightsCard(highlights)
            } else {
                generateButton(
                    title: "Generate Highlights",
                    action: { viewModel.generateAIHighlights() }
                )
            }

            analysisStateView
        }
    }

    private func highlightsCard(_ highlights: EpisodeHighlights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Key highlights
            VStack(alignment: .leading, spacing: 8) {
                Text("Key Moments")
                    .font(.headline)
                ForEach(Array(highlights.highlights.enumerated()), id: \.offset) { index, highlight in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .bold()
                            .foregroundColor(.blue)
                        Text(highlight)
                    }
                }
            }

            Divider()

            // Best quote
            VStack(alignment: .leading, spacing: 8) {
                Text("Best Quote")
                    .font(.headline)
                Text(""\(highlights.bestQuote)"")
                    .italic()
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
            }

            // Optional sections
            if let entertaining = highlights.entertainingMoment {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Entertaining Moment")
                        .font(.headline)
                    Text(entertaining)
                }
            }

            if let controversial = highlights.controversialPoint {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Controversial Point")
                        .font(.headline)
                    Text(controversial)
                }
            }

            // Action items
            if !highlights.actionItems.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Action Items")
                        .font(.headline)
                    ForEach(highlights.actionItems, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.square")
                                .foregroundColor(.green)
                            Text(item)
                        }
                    }
                }
            }

            // Regenerate button
            Button(action: {
                viewModel.episodeHighlights = nil
                viewModel.generateAIHighlights()
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

    // MARK: - Q&A Tab

    private var questionAnswerTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ask Questions")
                .font(.title2)
                .bold()

            Text("Ask questions about this episode and get AI-powered answers based on the transcript.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Question input
            HStack {
                TextField("Enter your question...", text: $questionInput)
                    .textFieldStyle(.roundedBorder)

                Button(action: {
                    viewModel.askAIQuestion(questionInput)
                }) {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(questionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !viewModel.aiAvailability.isAvailable)
            }

            // Answer display
            if let answer = viewModel.currentAnswer {
                answerCard(question: viewModel.currentQuestion, answer: answer)
            }

            analysisStateView
        }
    }

    private func answerCard(question: String, answer: EpisodeAnswer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Question
            VStack(alignment: .leading, spacing: 4) {
                Text("Question")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(question)
                    .font(.body)
                    .bold()
            }

            Divider()

            // Answer
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Answer")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    confidenceBadge(answer.confidence)
                }
                Text(answer.answer)
                    .font(.body)
            }

            // Timestamp
            if answer.timestamp != "N/A" {
                Divider()
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.blue)
                    Text("Timestamp: \(answer.timestamp)")
                        .font(.caption)
                }
            }

            // Related topics
            if !answer.relatedTopics.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Related Topics")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(answer.relatedTopics, id: \.self) { topic in
                        Text("• \(topic)")
                            .font(.caption)
                    }
                }
            }

            // Ask another question button
            Button(action: {
                questionInput = ""
                viewModel.currentAnswer = nil
                viewModel.currentQuestion = ""
            }) {
                Label("Ask Another Question", systemImage: "plus.circle")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func confidenceBadge(_ confidence: String) -> some View {
        Text(confidence.capitalized)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(confidenceColor(confidence).opacity(0.2))
            .foregroundColor(confidenceColor(confidence))
            .cornerRadius(4)
    }

    private func confidenceColor(_ confidence: String) -> Color {
        switch confidence.lowercased() {
        case "high": return .green
        case "medium": return .orange
        case "low": return .red
        default: return .gray
        }
    }

    // MARK: - Helper Views

    private func generateButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "sparkles")
                .frame(maxWidth: .infinity)
                .padding()
                .background(viewModel.aiAvailability.isAvailable ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
        }
        .disabled(!viewModel.aiAvailability.isAvailable)
    }

    private var analysisStateView: some View {
        Group {
            switch viewModel.analysisState {
            case .idle:
                EmptyView()

            case .analyzing(let progress):
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                    Text("Analyzing... \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()

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
