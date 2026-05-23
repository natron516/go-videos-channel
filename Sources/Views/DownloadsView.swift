import SwiftUI
import AVKit

#if !os(tvOS)

struct DownloadsView: View {
    @ObservedObject private var downloadManager = VideoDownloadManager.shared
    @State private var showLinkTV = false
    @State private var showWatchTimer = false
    @State private var showSearch = false

    var columns: [GridItem] {
        UIDevice.current.userInterfaceIdiom == .pad
            ? Array(repeating: GridItem(.flexible(), spacing: 20), count: 3)
            : Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
    }

    var body: some View {
        Group {
            if downloadManager.completedDownloads.isEmpty && downloadManager.downloadingAssetIds.isEmpty {
                // Empty state
                ZStack {
                    Color.black.ignoresSafeArea()
                    Color.clear.appBackground()
                    VStack(spacing: 16) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("No Downloaded Videos")
                            .font(.title2.bold())
                            .foregroundColor(.primary)
                        Text("Download videos to watch offline")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Label("Downloaded", systemImage: "arrow.down.circle.fill")
                            .font(.title3.bold())
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)

                        // In-progress downloads
                        if !downloadManager.downloadingAssetIds.isEmpty {
                            ForEach(Array(downloadManager.downloadingAssetIds), id: \.self) { assetId in
                                DownloadProgressRow(
                                    assetId: assetId,
                                    progress: downloadManager.progressByAssetId[assetId] ?? 0
                                )
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                        }

                        // Completed downloads grid
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(downloadManager.completedDownloads) { download in
                                Button {
                                    playDownloadedVideo(download)
                                } label: {
                                    DownloadedCardView(download: download)
                                }
                                .mediaCardStyle()
                                .contextMenu {
                                    Button(role: .destructive) {
                                        downloadManager.deleteDownload(assetId: download.id)
                                    } label: {
                                        Label("Delete Download", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                        // Storage info
                        if !downloadManager.completedDownloads.isEmpty {
                            HStack {
                                Spacer()
                                Text("Storage used: \(formattedSize(downloadManager.totalStorageUsed))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.top, 12)
                            .padding(.bottom, 24)
                        }
                    }
                }
            }
        }
        .navigationTitle("")
        .appBackground()
        .goNavBar(showLinkTV: $showLinkTV, showWatchTimer: $showWatchTimer, showSearch: $showSearch)
        .sheet(isPresented: $showLinkTV) { LinkTVView() }
        .sheet(isPresented: $showWatchTimer) { WatchTimerSetupView() }
        .sheet(isPresented: $showSearch) { NavigationStack { SearchView() } }
    }

    // MARK: - Play Downloaded Video

    private func playDownloadedVideo(_ download: DownloadedVideo) {
        guard let localURL = downloadManager.localAssetURL(for: download.id) else {
            // Bookmark no longer valid — clean up
            downloadManager.deleteDownload(assetId: download.id)
            return
        }

        let avAsset = AVURLAsset(url: localURL)
        let item = AVPlayerItem(asset: avAsset)
        let player = AVPlayer(playerItem: item)
        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true

        let vc = AVPlayerViewController()
        vc.player = player

        // Resume from saved position
        let assetId = download.id
        if PlaybackProgress.shared.hasProgress(for: assetId) {
            var obs: NSKeyValueObservation?
            obs = player.currentItem?.observe(\.status, options: [.new]) { [weak player] item, _ in
                if item.status == .readyToPlay {
                    let duration = item.duration.seconds
                    if !duration.isNaN && duration < 300 {
                        PlaybackProgress.shared.clear(assetId: assetId)
                    } else {
                        player?.resumeIfNeeded(assetId: assetId)
                    }
                    obs?.invalidate(); obs = nil
                }
            }
        }

        // Track position for progress saving
        MuxAssetURLTracker.track(url: localURL, assetId: assetId)

        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first?.rootViewController else { return }

        var top = root
        while let presented = top.presentedViewController { top = presented }

        // Save position periodically
        let progressObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 5, preferredTimescale: 600),
            queue: .main
        ) { [weak player] _ in
            guard let player = player,
                  let item = player.currentItem else { return }
            let pos = player.currentTime().seconds
            let rawDur = item.duration.seconds
            let dur = (rawDur.isNaN || rawDur.isInfinite) ? nil : rawDur
            PlaybackProgress.shared.save(assetId: assetId, position: pos, duration: dur)
        }

        // End-of-video handler
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            PlaybackProgress.shared.clear(assetId: assetId)
        }

        ActivePlayerSession.shared.set(player: player, observer: progressObserver, url: localURL, title: download.title)

        top.present(vc, animated: true) {
            player.play()
        }
    }

    // MARK: - Helpers

    private func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Download Progress Row

private struct DownloadProgressRow: View {
    let assetId: String
    let progress: Double

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("Downloading video…")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                ProgressView(value: progress)
                    .tint(.blue)
            }
            Spacer()
            Text("\(Int(progress * 100))%")
                .font(.caption.bold())
                .foregroundColor(.white.opacity(0.7))
            Button {
                VideoDownloadManager.shared.cancelDownload(assetId: assetId)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.7))
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.blue.opacity(0.6)))
        .padding(.bottom, 4)
    }
}

// MARK: - Downloaded Card View

private struct DownloadedCardView: View {
    let download: DownloadedVideo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Thumbnail
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay(
                    Group {
                        if let thumbURL = download.thumbnailURL {
                            CachedAsyncImage(url: thumbURL) {
                                thumbnailPlaceholder
                            }
                        } else {
                            thumbnailPlaceholder
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .bottomTrailing) {
                    // Downloaded badge
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                        .padding(4)
                }

            Text(download.title)
                .font(UIDevice.current.userInterfaceIdiom == .pad
                    ? .system(size: 17, weight: .bold)
                    : .system(size: 14, weight: .bold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .foregroundColor(.primary)

            HStack(spacing: 4) {
                Text(formattedDate(download.dateDownloaded))
                    .font(UIDevice.current.userInterfaceIdiom == .pad
                        ? .system(size: 11) : .system(size: 10))
                    .foregroundColor(.secondary)
                if let duration = download.duration {
                    Text("· \(formatDuration(duration))")
                        .font(UIDevice.current.userInterfaceIdiom == .pad
                            ? .system(size: 11) : .system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(
                    colors: [Color.white.opacity(0.08), Color.white.opacity(0.08)],
                    startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var thumbnailPlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .overlay(
                Image(systemName: "play.circle")
                    .font(.largeTitle)
                    .foregroundColor(.white)
            )
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

#endif
