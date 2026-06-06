import SwiftUI

struct PodcastDetailView: View {
    let podcast: GOPodcast

    @ObservedObject private var contentAPI = ContentAPI.shared
    @ObservedObject private var audioPlayer = AudioPlayerManager.shared
    @AppStorage("podcastAutoplay") private var autoplay: Bool = true

    @State private var episodes: [GOPodcastEpisode] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var pinUnlocked = PinUnlockManager.shared.isUnlocked

    private var requiresPin: Bool {
        podcast.category.lowercased() == "sermons"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Color.clear.appBackground()

            VStack(spacing: 0) {
                if isLoading {
                    Spacer()
                    ProgressView("Loading Episodes…")
                    Spacer()
                } else if let err = error {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        Text("Unable to load episodes")
                            .font(.title3)
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(40)
                    Spacer()
                } else if episodes.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "mic")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text("No Episodes Yet")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        // Podcast header
                        HStack(alignment: .top, spacing: 16) {
                            Group {
                                if let urlStr = podcast.artworkUrl, let url = URL(string: urlStr) {
                                    CachedAsyncImage(url: url) {
                                        Color.white.opacity(0.08)
                                            .overlay(
                                                Image(systemName: "mic.fill")
                                                    .foregroundColor(.secondary)
                                            )
                                    }
                                } else {
                                    Color.white.opacity(0.08)
                                        .overlay(
                                            Image(systemName: "mic.fill")
                                                .foregroundColor(.secondary)
                                        )
                                }
                            }
                            .frame(width: 100, height: 100)
                            .clipped()
                            .cornerRadius(14)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(podcast.title)
                                    .font(.title3.bold())
                                    .foregroundColor(.white)
                                if !podcast.description.isEmpty {
                                    Text(podcast.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(4)
                                }
                                Text("\(episodes.count) episode\(episodes.count == 1 ? "" : "s")")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(20)

                        Divider().background(Color.white.opacity(0.1))

                        LazyVStack(spacing: 0) {
                            ForEach(episodes) { episode in
                                EpisodeRow(episode: episode, podcastTitle: podcast.title) {
                                    playEpisode(episode)
                                }
                            }
                        }

                        // Spacer for mini player
                        if audioPlayer.hasItem {
                            Color.clear.frame(height: 80)
                        }
                    }

                    // Mini player
                    if audioPlayer.hasItem {
                        AudioMiniPlayer()
                    }
                }
            }
        }
        .navigationTitle(podcast.title)
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button { autoplay.toggle() } label: {
                    Image(systemName: autoplay ? "forward.end.fill" : "forward.end")
                        .foregroundColor(autoplay ? .blue : .secondary)
                }
                .accessibilityLabel(autoplay ? "Autoplay On" : "Autoplay Off")
            }
        }
        .task { await load() }
        .overlay {
            if requiresPin && !pinUnlocked {
                PinLockView {
                    pinUnlocked = true
                }
            }
        }
    }

    // MARK: - Playback

    private func playEpisode(_ episode: GOPodcastEpisode) {
        // Resume from saved position if available
        let savedPos = PlaybackTracker.shared.getPosition(episode.id)
        audioPlayer.play(
            url: episode.audioUrl,
            title: episode.title,
            artist: podcast.title,
            coverUrl: episode.imageUrl ?? podcast.artworkUrl
        )
        if savedPos > 0 {
            audioPlayer.seek(to: savedPos / max(audioPlayer.duration, 1))
        }
        // Mark as played and set track ID for position saving
        PlaybackTracker.shared.markPlayed(episode.id)
        audioPlayer.currentTrackId = episode.id
        if autoplay {
            audioPlayer.onFinish = { [self] in
                PlaybackTracker.shared.clearPosition(episode.id)
                playNextEpisode(after: episode)
            }
        } else {
            audioPlayer.onFinish = {
                PlaybackTracker.shared.clearPosition(episode.id)
            }
        }
    }

    private func playNextEpisode(after episode: GOPodcastEpisode) {
        guard let currentIndex = episodes.firstIndex(where: { $0.id == episode.id }),
              currentIndex + 1 < episodes.count else { return }
        let next = episodes[currentIndex + 1]
        playEpisode(next)
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            episodes = try await contentAPI.fetchEpisodes(podcastId: podcast.id)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Episode Row
struct EpisodeRow: View {
    let episode: GOPodcastEpisode
    let podcastTitle: String
    let onPlay: () -> Void

    @ObservedObject private var audioPlayer = AudioPlayerManager.shared
    @ObservedObject private var tracker = PlaybackTracker.shared

    private var isCurrentlyPlaying: Bool {
        audioPlayer.currentTitle == episode.title && audioPlayer.currentArtist == podcastTitle
    }

    private var isUnplayed: Bool {
        !tracker.hasPlayed(episode.id)
    }

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 14) {
                // Artwork or placeholder
                Group {
                    if let urlStr = episode.imageUrl, let url = URL(string: urlStr) {
                        CachedAsyncImage(url: url) {
                            Color.white.opacity(0.08)
                                .overlay(
                                    Image(systemName: "waveform")
                                        .foregroundColor(.secondary)
                                )
                        }
                    } else {
                        Color.white.opacity(0.08)
                            .overlay(
                                Image(systemName: "waveform")
                                    .foregroundColor(.secondary)
                            )
                    }
                }
                .frame(width: 54, height: 54)
                .clipped()
                .cornerRadius(8)
                .overlay(
                    Group {
                        if isCurrentlyPlaying {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.opacity(0.6))
                                .overlay(
                                    Image(systemName: "waveform")
                                        .font(.caption.bold())
                                        .foregroundColor(.white)
                                )
                        }
                    }
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if isUnplayed {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 8, height: 8)
                        }
                        Text(episode.title)
                            .font(.subheadline.bold())
                            .foregroundColor(isCurrentlyPlaying ? .blue : .white)
                            .lineLimit(2)
                    }
                    HStack(spacing: 8) {
                        if let dur = episode.duration {
                            Text(dur)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        if let pub = episode.pubDate {
                            Text(pub)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    if !episode.description.isEmpty {
                        Text(episode.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Image(systemName: isCurrentlyPlaying ? "waveform" : "play.circle")
                    .font(.title3)
                    .foregroundColor(isCurrentlyPlaying ? .blue : .secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.white.opacity(isCurrentlyPlaying ? 0.06 : 0.02))
            .overlay(
                Divider().background(Color.white.opacity(0.07)),
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
    }
}

