import SwiftUI

struct AudioListView: View {
    @ObservedObject private var contentAPI = ContentAPI.shared
    @ObservedObject private var audioPlayer = AudioPlayerManager.shared

    @State private var allAudioAssets: [GOAudioAsset] = []
    @State private var isLoading = true
    @State private var error: String?

    var columns: [GridItem] {
        #if os(tvOS)
        Array(repeating: GridItem(.flexible(), spacing: 24), count: 4)
        #else
        UIDevice.current.userInterfaceIdiom == .pad
            ? Array(repeating: GridItem(.flexible(), spacing: 20), count: 3)
            : Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
        #endif
    }

    // Singles: audio assets NOT in any series
    private var singleAssets: [GOAudioAsset] {
        allAudioAssets.filter { $0.seriesId == nil || $0.seriesId!.isEmpty }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Color.clear.appBackground()

            if isLoading {
                ProgressView("Loading Audio…")
            } else if let err = error {
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
            } else if singleAssets.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "waveform")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    Text("No Audio Yet")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // ── SINGLES SECTION ──
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Audio")
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 16)

                                LazyVGrid(columns: columns, spacing: 16) {
                                    ForEach(singleAssets) { asset in
                                        AudioAssetCard(asset: asset) {
                                            audioPlayer.play(
                                                url: asset.audioUrl,
                                                title: asset.title,
                                                artist: asset.artist
                                            )
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
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
        .task { await load() }
    }

    private func load() async {
        if let cached = ContentPreloader.shared.audioAssets {
            allAudioAssets = cached
            isLoading = false
            return
        }
        isLoading = true
        error = nil
        do {
            allAudioAssets = try await contentAPI.fetchAudio()
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
                    .aspectRatio(1, contentMode: .fill)
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

    var body: some View {
        VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.15))

            HStack(spacing: 16) {
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

                // Progress text
                Text("\(audioPlayer.currentTimeFormatted) / \(audioPlayer.durationFormatted)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()

                Button {
                    audioPlayer.togglePlayPause()
                } label: {
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }

                Button {
                    audioPlayer.stop()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.85))

            // Progress bar
            ProgressView(value: audioPlayer.progress)
                .tint(.blue)
                .frame(height: 2)
        }
        .background(Color.black.opacity(0.9))
    }
}

