import SwiftUI
import MusicKit

struct AlbumDetailView: View {
    let album: Album
    @StateObject private var music = AppleMusicService.shared
    @State private var tracks: [Track] = []
    @State private var isLoading = true
    @State private var addedToLibrary = false
    @State private var addingToLibrary = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.clear.appBackground()
            #if os(tvOS)
            tvLayout
            #else
            iOSLayout
            #endif
        }
        .navigationTitle(album.title)
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if os(tvOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }
        }
        #endif
        .task {
            tracks = await music.fetchTracks(for: album)
            isLoading = false
        }
    }

    // MARK: - tvOS Layout (side by side, compact)
    #if os(tvOS)
    var tvLayout: some View {
        HStack(alignment: .top, spacing: 48) {
            // Left column: artwork + info + controls
            VStack(spacing: 16) {
                if let artwork = album.artwork {
                    ArtworkImage(artwork, width: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
                }
                VStack(spacing: 4) {
                    Text(album.title)
                        .font(.headline.bold())
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    if !album.artistName.isEmpty {
                        Text(album.artistName)
                            .font(.subheadline)
                            .foregroundColor(.pink)
                    }
                    if !tracks.isEmpty {
                        Text("\(tracks.count) songs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                VStack(spacing: 10) {
                    Button { Task { await music.playAlbum(album) } } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    if let err = music.playbackError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                    Button {
                        Task {
                            await music.playAlbum(album)
                            ApplicationMusicPlayer.shared.state.shuffleMode = .songs
                        }
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                if music.isPlaying, let title = music.nowPlayingTitle {
                    NowPlayingBar(title: title)
                }
                Spacer()
            }
            .frame(width: 260)
            .padding(.leading, 40)
            .padding(.top, 40)

            // Right column: track list (no scroll needed for most albums)
            VStack(alignment: .leading) {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    trackList
                }
            }
            .padding(.trailing, 40)
            .padding(.top, 40)
        }
    }
    #endif

    // MARK: - iOS Layout
    var iOSLayout: some View {
        ScrollView {
            VStack(spacing: 24) {
                albumHeader
                playControls
                if music.isPlaying, let title = music.nowPlayingTitle {
                    NowPlayingBar(title: title).padding(.horizontal, 16)
                }
                if isLoading {
                    ProgressView().frame(minHeight: 100)
                } else {
                    trackList
                }
            }
            .padding(.vertical, 16)
        }
    }

    // MARK: - Album Header

    var albumHeader: some View {
        VStack(spacing: 16) {
            if let artwork = album.artwork {
                ArtworkImage(artwork, width: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
            }

            VStack(spacing: 6) {
                Text(album.title)
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                if !album.artistName.isEmpty {
                    Text(album.artistName)
                        .font(.headline)
                        .foregroundColor(.pink)
                }

                HStack(spacing: 8) {
                    if let genre = album.genreNames.first {
                        Text(genre)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let year = album.releaseDate {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(year, format: .dateTime.year())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if !tracks.isEmpty {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(tracks.count) songs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Play Controls

    var playControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Button {
                    Task { await music.playAlbum(album) }
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Play")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    Task {
                        await music.playAlbum(album)
                        ApplicationMusicPlayer.shared.state.shuffleMode = .songs
                    }
                } label: {
                    HStack {
                        Image(systemName: "shuffle")
                        Text("Shuffle")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            // Add to Apple Music Library
            Button {
                Task {
                    addingToLibrary = true
                    do {
                        try await MusicLibrary.shared.add(album)
                        addedToLibrary = true
                    } catch {
                        print("Failed to add to library: \(error)")
                    }
                    addingToLibrary = false
                }
            } label: {
                HStack {
                    if addingToLibrary {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: addedToLibrary ? "checkmark" : "plus")
                    }
                    Text(addedToLibrary ? "Added to Library" : "Add to My Library")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(addedToLibrary ? .green : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.white.opacity(addedToLibrary ? 0.05 : 0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(addedToLibrary || addingToLibrary)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Track List

    var trackList: some View {
        VStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                Button {
                    Task { await music.playTrack(track, in: album) }
                } label: {
                    HStack(spacing: 14) {
                        // Track number
                        Text("\(index + 1)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(width: 28, alignment: .trailing)

                        // Track info
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.body)
                                .foregroundColor(.white)
                                .lineLimit(1)

                            if track.artistName != album.artistName {
                                Text(track.artistName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        // Duration
                        if let duration = track.duration {
                            Text(formatDuration(duration))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Now playing indicator
                        if music.nowPlayingTitle == track.title && music.isPlaying {
                            Image(systemName: "waveform")
                                .foregroundColor(.pink)
                                .font(.caption)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        music.nowPlayingTitle == track.title
                            ? Color.pink.opacity(0.1)
                            : Color.clear
                    )
                }
                .buttonStyle(.plain)

                if index < tracks.count - 1 {
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.leading, 58)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.05))
        )
        .padding(.horizontal, 16)
    }

    func formatDuration(_ duration: TimeInterval) -> String {
        let m = Int(duration) / 60
        let s = Int(duration) % 60
        return String(format: "%d:%02d", m, s)
    }
}
