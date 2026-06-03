import SwiftUI
import AVKit

struct SeriesDetailView: View {
    let series: GOSeries

    @ObservedObject private var contentAPI = ContentAPI.shared
    @ObservedObject private var audioPlayer = AudioPlayerManager.shared

    @State private var episodes: [GOAudioAsset] = []
    @State private var isLoading = true
    @State private var error: String?
    @AppStorage("seriesAutoplay") private var autoplay: Bool = true

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            Color.clear.appBackground()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // ── Header ──
                        seriesHeader

                        // ── Episode List ──
                        if isLoading {
                            HStack {
                                Spacer()
                                ProgressView("Loading episodes…")
                                    .padding(40)
                                Spacer()
                            }
                        } else if let err = error {
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 40))
                                    .foregroundColor(.orange)
                                Text(err)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                Button("Retry") { Task { await loadEpisodes() } }
                                    .buttonStyle(.borderedProminent)
                            }
                            .padding(40)
                        } else if episodes.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "tray")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                                Text("No episodes yet")
                                    .foregroundColor(.secondary)
                            }
                            .padding(40)
                            .frame(maxWidth: .infinity)
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
                                    SeriesEpisodeRow(
                                        episode: episode,
                                        index: index,
                                        onTap: { handleEpisodeTap(episode) }
                                    )
                                    if index < episodes.count - 1 {
                                        Divider()
                                            .background(Color.white.opacity(0.08))
                                            .padding(.leading, 72)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                        }
                    }
                    // Extra padding for mini player
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
        .navigationTitle(series.title)
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color.black.opacity(0.85), for: .navigationBar)
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
        .task { await loadEpisodes() }
    }

    // MARK: - Series Header

    private var seriesHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            // Artwork
            Group {
                if let urlStr = series.artworkUrl, let url = URL(string: urlStr) {
                    CachedAsyncImage(url: url) {
                        seriesArtworkPlaceholder
                    }
                } else {
                    seriesArtworkPlaceholder
                }
            }
            .frame(width: 120, height: 120)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(series.title)
                    .font(.title3.bold())
                    .foregroundColor(.white)
                    .lineLimit(3)

                HStack(spacing: 6) {
                    Text(series.category.capitalized)
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.15)))

                    Text(series.mediaType.capitalized)
                        .font(.caption.bold())
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.blue.opacity(0.2)))
                }

                if !series.description.isEmpty {
                    Text(series.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(4)
                }

                if !episodes.isEmpty {
                    Text("\(episodes.count) episode\(episodes.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }


            }
        }
        .padding(16)
    }

    private var seriesArtworkPlaceholder: some View {
        Color.white.opacity(0.08)
            .overlay(
                Image(systemName: series.mediaType == "video" ? "video.fill" : "music.note.list")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)
            )
    }

    // MARK: - Data Loading

    private func loadEpisodes() async {
        isLoading = true
        error = nil
        do {
            episodes = try await contentAPI.fetchSeriesEpisodes(seriesId: series.id)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Episode Tap Handler

    private func handleEpisodeTap(_ episode: GOAudioAsset) {
        playEpisode(episode)
    }

    private func playEpisode(_ episode: GOAudioAsset) {
        let isVideo = episode.mediaType == "video"
        if isVideo {
            guard let url = URL(string: episode.audioUrl) else { return }
            // Set up autoplay handler BEFORE presenting so the video player picks it up
            if autoplay {
                AutoplayManager.shared.customNextHandler = { [self] in
                    playNextEpisode(after: episode)
                }
            } else {
                AutoplayManager.shared.customNextHandler = nil
            }
            presentPlayer(url: url)
        } else {
            audioPlayer.play(
                url: episode.audioUrl,
                title: episode.title,
                artist: episode.artist
            )
            if autoplay {
                audioPlayer.onFinish = { [self] in
                    playNextEpisode(after: episode)
                }
            } else {
                audioPlayer.onFinish = nil
            }
        }
    }

    private func playNextEpisode(after episode: GOAudioAsset) {
        guard let currentIndex = episodes.firstIndex(where: { $0.id == episode.id }),
              currentIndex + 1 < episodes.count else {
            // No more episodes — dismiss the player
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { dismissTopPlayer() }
            return
        }
        let next = episodes[currentIndex + 1]
        playEpisode(next)
    }
}

// MARK: - Series Episode Row

struct SeriesEpisodeRow: View {
    let episode: GOAudioAsset
    let index: Int
    let onTap: () -> Void

    @ObservedObject private var audioPlayer = AudioPlayerManager.shared

    private var isCurrentlyPlaying: Bool {
        audioPlayer.currentTitle == episode.title && audioPlayer.isPlaying
    }

    private var isVideo: Bool {
        episode.mediaType == "video"
    }

    private var episodeNumDisplay: String {
        if let num = episode.episodeNumber {
            return "\(num)"
        }
        return "\(index + 1)"
    }

    private var durationDisplay: String {
        guard let dur = episode.duration, dur > 0 else { return "" }
        let total = Int(dur)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Episode number / play indicator
                ZStack {
                    Circle()
                        .fill(isCurrentlyPlaying ? Color.blue : Color.white.opacity(0.08))
                        .frame(width: 44, height: 44)

                    if isCurrentlyPlaying {
                        Image(systemName: "waveform")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                    } else {
                        Text(episodeNumDisplay)
                            .font(.callout.bold())
                            .foregroundColor(.secondary)
                    }
                }

                // Episode info
                VStack(alignment: .leading, spacing: 3) {
                    Text(episode.title)
                        .font(.subheadline.bold())
                        .foregroundColor(isCurrentlyPlaying ? .blue : .white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 8) {
                        // Media type icon
                        Label(isVideo ? "Video" : "Audio",
                              systemImage: isVideo ? "video.fill" : "music.note")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .labelStyle(.iconOnly)

                        if !durationDisplay.isEmpty {
                            Text(durationDisplay)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if !episode.artist.isEmpty {
                            Text("·")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text(episode.artist)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                // Play button
                Image(systemName: isVideo ? "play.rectangle.fill" : (isCurrentlyPlaying ? "pause.fill" : "play.fill"))
                    .font(.body)
                    .foregroundColor(isCurrentlyPlaying ? .blue : .secondary)
                    .frame(width: 32, height: 32)
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}
