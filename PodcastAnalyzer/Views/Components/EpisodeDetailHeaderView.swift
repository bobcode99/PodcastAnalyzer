
import SwiftData
import SwiftUI

struct EpisodeDetailHeaderView: View {
    @Bindable var viewModel: EpisodeDetailViewModel
    @Environment(\.modelContext) private var modelContext

    /// Destination view for navigating to the podcast's episode list
    @ViewBuilder
    private var podcastDestination: some View {
        // Try to find the podcast model in SwiftData
        let title = viewModel.podcastTitle
        let descriptor = FetchDescriptor<PodcastInfoModel>(
            predicate: #Predicate { $0.title == title }
        )
        if let podcastModel = try? modelContext.fetch(descriptor).first {
            EpisodeListView(podcastModel: podcastModel)
        } else {
            // Fallback: show an error or navigate with browse mode
            ContentUnavailableView(
                "Podcast Not Found",
                systemImage: "exclamationmark.triangle",
                description: Text("This podcast is not in your library")
            )
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                // Artwork
                if let url = URL(string: viewModel.imageURLString) {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Color.gray.overlay(ProgressView())
                    }
                    .frame(width: 80, height: 80)
                    .clipShape(.rect(cornerRadius: 10))
                    .shadow(radius: 2)
                } else {
                    Color.gray.frame(width: 80, height: 80).clipShape(.rect(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 6) {
                    // FULL TITLE – no lineLimit, multiline, selectable
                    // Show translated title if available, with disclosure for original
                    if let translatedTitle = viewModel.translatedEpisodeTitle {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(translatedTitle)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .multilineTextAlignment(.leading)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)

                            DisclosureGroup("Original") {
                                Text(viewModel.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .textSelection(.enabled)
                            }
                            .font(.caption2)
                            .foregroundStyle(.blue)
                        }
                    } else {
                        Text(viewModel.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Tappable podcast title - navigates to show
                    NavigationLink(destination: podcastDestination) {
                        HStack(spacing: 4) {
                            if let translatedTitle = viewModel.translatedPodcastTitle {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(translatedTitle)
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                    Text(viewModel.podcastTitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text(viewModel.podcastTitle)
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8))
                                .foregroundStyle(.blue)
                        }
                    }
                    .buttonStyle(.plain)

                    // Date and status icons row
                    HStack(spacing: 8) {
                        if let dateString = viewModel.pubDateString {
                            Text(dateString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        // Status icons (same as EpisodeRowView)
                        HStack(spacing: 6) {
                            if viewModel.isStarred {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.yellow)
                            }

                            if viewModel.hasLocalAudio {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.green)
                            }

                            // Transcript status
                            switch viewModel.transcriptState {
                            case .idle, .error:
                                if viewModel.hasTranscript {
                                    Image(systemName: "captions.bubble.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.purple)
                                }
                            case .downloadingModel, .transcribing:
                                HStack(spacing: 2) {
                                    ProgressView().scaleEffect(0.5)
                                }
                            case .completed:
                                Image(systemName: "captions.bubble.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.purple)
                            }

                            // AI Analysis available
                            if viewModel.hasAIAnalysis {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.orange)
                            }

                            if viewModel.isCompleted {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
                Spacer()
            }

            // Play + Download buttons (icon-only capsules)
            HStack(spacing: 8) {
                // Play button with progress (icon-only style)
                EpisodePlayButton(
                    isPlaying: viewModel.audioManager.isPlaying,
                    isPlayingThisEpisode: viewModel.isPlayingThisEpisode,
                    isCompleted: viewModel.isCompleted,
                    playbackProgress: viewModel.playbackProgress,
                    duration: viewModel.savedDuration,
                    lastPlaybackPosition: viewModel.lastPlaybackPosition,
                    formattedDuration: viewModel.formattedDuration,
                    isDisabled: viewModel.isPlayDisabled,
                    style: .iconOnly,
                    action: { viewModel.playAction() }
                )

                EpisodeDownloadButton(viewModel: viewModel)

                Spacer()
            }

            if !viewModel.hasLocalAudio && viewModel.audioURL != nil {
                HStack(spacing: 4) {
                    Image(systemName: "wifi")
                    Text("Streaming")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}
