import SwiftUI

struct PodcastListView: View {
    @ObservedObject private var contentAPI = ContentAPI.shared
    @State private var podcasts: [GOPodcast] = []
    @State private var seriesList: [GOSeries] = []
    @State private var allAudioAssets: [GOAudioAsset] = []
    @State private var isLoading = true
    @State private var showAddToPlaylist = false
    @State private var addToPlaylistAudioId: String?
    @State private var error: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Color.clear.appBackground()

            if isLoading {
                ProgressView("Loading…")
            } else if let err = error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    Text("Unable to load content")
                        .font(.title3)
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
                .padding(40)
            } else if seriesList.isEmpty && podcasts.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "mic")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    Text("No Podcasts Yet")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {

                        // ── YOUR SERIES SECTION ──
                        if !seriesList.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Your Series")
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 16)

                                LazyVStack(spacing: 0) {
                                    ForEach(seriesList) { series in
                                        NavigationLink(destination: SeriesDetailView(series: series)) {
                                            PodcastSeriesRowCard(series: series, allAudio: allAudioAssets)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        // ── PODCAST FEEDS SECTION ──
                        if !podcasts.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Podcast Feeds")
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.top, seriesList.isEmpty ? 16 : 28)

                                LazyVStack(spacing: 0) {
                                    ForEach(podcasts) { podcast in
                                        NavigationLink {
                                            PodcastDetailView(podcast: podcast)
                                        } label: {
                                            PodcastRowCard(podcast: podcast)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        let pre = ContentPreloader.shared
        if let p = pre.podcasts, let s = pre.series, let a = pre.audioAssets {
            podcasts = p
            seriesList = s
            allAudioAssets = a
            isLoading = false
            return
        }
        isLoading = true
        error = nil
        do {
            async let podcastsTask = contentAPI.fetchPodcasts()
            async let seriesTask = contentAPI.fetchSeries()
            async let audioTask = contentAPI.fetchAudio()
            let (p, s, a) = try await (podcastsTask, seriesTask, audioTask)
            podcasts = p
            seriesList = s
            allAudioAssets = a
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Series Row Card (for Podcasts tab)
struct PodcastSeriesRowCard: View {
    let series: GOSeries
    let allAudio: [GOAudioAsset]

    private var episodeCount: Int {
        allAudio.filter { $0.seriesId == series.id }.count
    }

    var body: some View {
        HStack(spacing: 16) {
            Group {
                if let urlStr = series.artworkUrl, let url = URL(string: urlStr) {
                    CachedAsyncImage(url: url) {
                        seriesPlaceholder
                    }
                } else {
                    seriesPlaceholder
                }
            }
            .frame(width: 72, height: 72)
            .clipped()
            .cornerRadius(12)

            VStack(alignment: .leading, spacing: 4) {
                Text(series.title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if episodeCount > 0 {
                        Label("\(episodeCount) episode\(episodeCount == 1 ? "" : "s")", systemImage: "music.note.list")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if series.mediaType == "video" {
                        Label("Video", systemImage: "video.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if series.mediaType == "mixed" {
                        Label("Audio & Video", systemImage: "waveform")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Label("Audio", systemImage: "waveform")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if !series.description.isEmpty {
                    Text(series.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.03))
        .overlay(
            Divider().background(Color.white.opacity(0.07)),
            alignment: .bottom
        )
    }

    private var seriesPlaceholder: some View {
        Color.white.opacity(0.08)
            .overlay(
                Image(systemName: series.mediaType == "video" ? "video.fill" : "music.note.list")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary)
            )
    }
}

// MARK: - Podcast Row Card
struct PodcastRowCard: View {
    let podcast: GOPodcast

    var body: some View {
        HStack(spacing: 16) {
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
            .frame(width: 72, height: 72)
            .clipped()
            .cornerRadius(12)

            VStack(alignment: .leading, spacing: 4) {
                Text(podcast.title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(2)
                if !podcast.description.isEmpty {
                    Text(podcast.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.03))
        .overlay(
            Divider().background(Color.white.opacity(0.07)),
            alignment: .bottom
        )
    }
}

