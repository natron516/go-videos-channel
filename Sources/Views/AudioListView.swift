import SwiftUI

struct AudioListView: View {
    @ObservedObject private var contentAPI = ContentAPI.shared
    @ObservedObject private var audioPlayer = AudioPlayerManager.shared

    @State private var allAudioAssets: [GOAudioAsset] = []
    @State private var audiobookSeries: [GOSeries] = []
    @State private var isLoading = true
    @State private var error: String?

    var columns: [GridItem] {
        #if os(tvOS)
        Array(repeating: GridItem(.flexible(), spacing: 24), count: 4)
        #else
        UIDevice.current.userInterfaceIdiom == .pad
            ? Array(repeating: GridItem(.flexible(), spacing: 14), count: 6)
            : Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
        #endif
    }

    // Singles: audio assets NOT in any series
    private var singleAssets: [GOAudioAsset] {
        allAudioAssets.filter { $0.seriesId == nil || $0.seriesId!.isEmpty }
    }

    var body: some View {
        ZStack {
            Color.clear
            if let err = error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    Text("Unable to load audio")
                        .font(.title3)
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
                .padding(40)
            } else if !isLoading && singleAssets.isEmpty && audiobookSeries.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "waveform")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    Text("No Audiobooks Yet")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            } else if !isLoading {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // ── AUDIOBOOK SERIES ──
                            if !audiobookSeries.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Audiobook Series")
                                        .font(.title2.bold())
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.top, 16)

                                    LazyVGrid(columns: columns, spacing: 16) {
                                        ForEach(audiobookSeries) { series in
                                            NavigationLink(destination: SeriesDetailView(series: series)) {
                                                VStack(alignment: .leading, spacing: 8) {
                                                    ZStack(alignment: .bottomTrailing) {
                                                        Group {
                                                            if let urlStr = series.artworkUrl, let url = URL(string: urlStr) {
                                                                CachedAsyncImage(url: url) {
                                                                    Color.white.opacity(0.08)
                                                                        .overlay(
                                                                            Image(systemName: "book.fill")
                                                                                .font(.system(size: 30))
                                                                                .foregroundColor(.secondary)
                                                                        )
                                                                }
                                                            } else {
                                                                Color.white.opacity(0.08)
                                                                    .overlay(
                                                                        Image(systemName: "book.fill")
                                                                            .font(.system(size: 30))
                                                                            .foregroundColor(.secondary)
                                                                    )
                                                            }
                                                        }
                                                        .aspectRatio(3.0/2.0, contentMode: .fit)
                                                        .clipped()
                                                        .cornerRadius(10)

                                                        Image(systemName: "book.fill")
                                                            .font(.caption.bold())
                                                            .foregroundColor(.white)
                                                            .padding(6)
                                                            .background(Circle().fill(Color.purple.opacity(0.8)))
                                                            .padding(8)
                                                    }

                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(series.title)
                                                            .font(.caption.bold())
                                                            .foregroundColor(.white)
                                                            .lineLimit(2)
                                                        if !series.description.isEmpty {
                                                            Text(series.description)
                                                                .font(.caption)
                                                                .foregroundColor(.secondary)
                                                                .lineLimit(1)
                                                        }
                                                    }
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }

                            // ── SINGLES SECTION ──
                            if !singleAssets.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Audio")
                                        .font(.title2.bold())
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.top, 16)

                                    LazyVGrid(columns: columns, spacing: 16) {
                                        ForEach(singleAssets) { asset in
                                            AudioAssetCard(asset: asset) {
                                                let savedPos = PlaybackTracker.shared.getPosition(asset.id)
                                                audioPlayer.play(
                                                    url: asset.audioUrl,
                                                    title: asset.title,
                                                    artist: asset.artist,
                                                    coverUrl: asset.coverImageUrl,
                                                    trackId: asset.id,
                                                    resumeAt: savedPos
                                                )
                                                PlaybackTracker.shared.markPlayed(asset.id)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 16)
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
        .overlay {
            if isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.3))
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            if let cached = ContentPreloader.shared.audioAssets {
                allAudioAssets = cached
            } else {
                allAudioAssets = try await contentAPI.fetchAudio()
            }
            // Fetch series categorized as "audiobook"
            let allSeries = try await contentAPI.fetchSeries()
            audiobookSeries = allSeries.filter { $0.category.lowercased() == "audiobook" }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Audio Asset Card
struct AudioAssetCard: View {
    let asset: GOAudioAsset
    let onPlay: () -> Void
    @ObservedObject private var audioPlayer = AudioPlayerManager.shared

    private var isCurrentlyPlaying: Bool {
        audioPlayer.currentTitle == asset.title && audioPlayer.isPlaying
    }

    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let urlStr = asset.coverImageUrl, let url = URL(string: urlStr) {
                            CachedAsyncImage(url: url) {
                                Color.white.opacity(0.08)
                                    .overlay(
                                        Image(systemName: "waveform")
                                            .font(.system(size: 30))
                                            .foregroundColor(.secondary)
                                    )
                            }
                        } else {
                            Color.white.opacity(0.08)
                                .overlay(
                                    Image(systemName: "waveform")
                                        .font(.system(size: 30))
                                        .foregroundColor(.secondary)
                                )
                        }
                    }
                    .aspectRatio(3.0/2.0, contentMode: .fit)
                    .clipped()
                    .cornerRadius(10)

                    // Play/playing indicator
                    Image(systemName: isCurrentlyPlaying ? "waveform" : "play.fill")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Circle().fill(isCurrentlyPlaying ? Color.blue : Color.black.opacity(0.6)))
                        .padding(8)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.title)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .lineLimit(2)
                    if !asset.artist.isEmpty {
                        Text(asset.artist)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mini Player
struct AudioMiniPlayer: View {
    @ObservedObject private var audioPlayer = AudioPlayerManager.shared
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0


    var body: some View {
        #if os(tvOS)
        tvOSBody
        #else
        iOSBody
        #endif
    }

    #if os(tvOS)
    // On tvOS, the full audio player is embedded in TVContentView's main area.
    // The mini player is not needed since the full player takes over the content area.
    private var tvOSBody: some View {
        EmptyView()
    }
    #endif

    private var iOSBody: some View {
        VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.15))

            VStack(spacing: 6) {
                // Title + close
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(audioPlayer.currentTitle)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .lineLimit(1)
                        if !audioPlayer.currentArtist.isEmpty {
                            Text(audioPlayer.currentArtist)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Button { audioPlayer.stop() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }

                // Scrubbable progress bar
                #if os(tvOS)
                ProgressView(value: audioPlayer.progress)
                    .tint(.blue)
                    .frame(height: 4)
                #else
                Slider(
                    value: Binding(
                        get: { isScrubbing ? scrubValue : audioPlayer.progress },
                        set: { newVal in
                            scrubValue = newVal
                            isScrubbing = true
                        }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        if !editing {
                            audioPlayer.seek(to: scrubValue)
                            isScrubbing = false
                        }
                    }
                )
                .tint(.blue)
                .frame(height: 20)
                #endif

                // Time + controls
                HStack(spacing: 0) {
                    Text(audioPlayer.currentTimeFormatted)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .leading)

                    Spacer()

                    // Skip back 15s
                    Button { audioPlayer.skip(seconds: -15) } label: {
                        Image(systemName: "gobackward.15")
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 36)
                    }

                    // Play/Pause
                    Button { audioPlayer.togglePlayPause() } label: {
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 50, height: 36)
                    }

                    // Skip forward 15s
                    Button { audioPlayer.skip(seconds: 15) } label: {
                        Image(systemName: "goforward.15")
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 36)
                    }

                    Spacer()

                    Text(audioPlayer.durationFormatted)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.85))
        }
        .background(Color.black.opacity(0.9))
    }

    #if os(tvOS)
    // Auto-present full player when a new track starts on tvOS
    #endif
}

