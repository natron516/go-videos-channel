import AVFoundation
import Foundation

#if os(tvOS)
// Video download not available on tvOS
class VideoDownloadManager: ObservableObject {
    static let shared = VideoDownloadManager()
    @Published var downloadingAssetIds: Set<String> = []
    @Published var progressByAssetId: [String: Double] = [:]
    @Published var completedDownloads: [DownloadedVideo] = []
    var totalStorageUsed: Int64 { 0 }
    func startDownload(asset: MuxAsset) {}
    func cancelDownload(assetId: String) {}
    func deleteDownload(assetId: String) {}
    func isDownloaded(_ assetId: String) -> Bool { false }
    func isDownloading(_ assetId: String) -> Bool { false }
    func localAssetURL(for assetId: String) -> URL? { nil }
}

struct DownloadedVideo: Identifiable, Codable {
    let id: String
    let title: String
    let category: String?
    let duration: Double?
    let thumbnailURLString: String?
    let dateDownloaded: Date
    var bookmarkData: Data
    var thumbnailURL: URL? {
        guard let s = thumbnailURLString else { return nil }
        return URL(string: s)
    }
}
#else

import UIKit

// MARK: - Downloaded Video Metadata

struct DownloadedVideo: Identifiable, Codable {
    let id: String          // MuxAsset.id
    let title: String
    let category: String?
    let duration: Double?
    let thumbnailURLString: String?
    let dateDownloaded: Date
    var bookmarkData: Data

    var thumbnailURL: URL? {
        guard let s = thumbnailURLString else { return nil }
        return URL(string: s)
    }
}

// MARK: - Video Download Manager

class VideoDownloadManager: NSObject, ObservableObject {
    static let shared = VideoDownloadManager()

    @Published var downloadingAssetIds: Set<String> = []
    @Published var progressByAssetId: [String: Double] = [:]
    @Published var completedDownloads: [DownloadedVideo] = []

    private var downloadSession: AVAssetDownloadURLSession!
    private var activeDownloads: [AVAssetDownloadTask: String] = [:]  // task → assetId
    private var pendingAssets: [String: MuxAsset] = [:]               // assetId → MuxAsset (for metadata on complete)

    private let storageKey = "com.gomedia.downloadedVideos"

    override init() {
        super.init()

        let config = URLSessionConfiguration.background(withIdentifier: "com.gomedia.videodownloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true

        downloadSession = AVAssetDownloadURLSession(
            configuration: config,
            assetDownloadDelegate: self,
            delegateQueue: .main
        )

        loadCompletedDownloads()
        pruneStaleDownloads()
    }

    // MARK: - Public API

    func startDownload(asset: MuxAsset) {
        guard let streamURL = asset.streamURL else { return }
        guard !downloadingAssetIds.contains(asset.id),
              !isDownloaded(asset.id) else { return }

        let avAsset = AVURLAsset(url: streamURL)

        guard let task = downloadSession.makeAssetDownloadTask(
            asset: avAsset,
            assetTitle: asset.title,
            assetArtworkData: nil,
            options: [AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: 2_000_000]
        ) else {
            print("[VideoDownloadManager] Failed to create download task for \(asset.id)")
            return
        }

        activeDownloads[task] = asset.id
        pendingAssets[asset.id] = asset

        downloadingAssetIds.insert(asset.id)
        progressByAssetId[asset.id] = 0

        task.resume()
    }

    func cancelDownload(assetId: String) {
        if let entry = activeDownloads.first(where: { $0.value == assetId }) {
            entry.key.cancel()
        }
        cleanupDownloadState(assetId: assetId)
    }

    func deleteDownload(assetId: String) {
        guard let index = completedDownloads.firstIndex(where: { $0.id == assetId }) else { return }
        let download = completedDownloads[index]

        // Resolve bookmark and delete the .movpkg
        if let url = resolveBookmark(download.bookmarkData) {
            try? FileManager.default.removeItem(at: url)
        }

        completedDownloads.remove(at: index)
        saveCompletedDownloads()
    }

    func isDownloaded(_ assetId: String) -> Bool {
        completedDownloads.contains { $0.id == assetId }
    }

    func isDownloading(_ assetId: String) -> Bool {
        downloadingAssetIds.contains(assetId)
    }

    func localAssetURL(for assetId: String) -> URL? {
        guard let download = completedDownloads.first(where: { $0.id == assetId }) else { return nil }
        return resolveBookmark(download.bookmarkData)
    }

    /// Total bytes used by all downloaded .movpkg files
    var totalStorageUsed: Int64 {
        completedDownloads.compactMap { download -> Int64? in
            guard let url = resolveBookmark(download.bookmarkData) else { return nil }
            return directorySize(url: url)
        }.reduce(0, +)
    }

    // MARK: - Persistence

    private func loadCompletedDownloads() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let downloads = try? JSONDecoder().decode([DownloadedVideo].self, from: data) else {
            completedDownloads = []
            return
        }
        completedDownloads = downloads
    }

    private func saveCompletedDownloads() {
        if let data = try? JSONEncoder().encode(completedDownloads) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    /// Remove entries whose bookmark can no longer be resolved (deleted by OS, etc.)
    private func pruneStaleDownloads() {
        let before = completedDownloads.count
        completedDownloads.removeAll { resolveBookmark($0.bookmarkData) == nil }
        if completedDownloads.count != before {
            saveCompletedDownloads()
        }
    }

    // MARK: - Helpers

    private func cleanupDownloadState(assetId: String) {
        downloadingAssetIds.remove(assetId)
        progressByAssetId.removeValue(forKey: assetId)
        pendingAssets.removeValue(forKey: assetId)
        activeDownloads = activeDownloads.filter { $0.value != assetId }
    }

    private func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                  bookmarkDataIsStale: &isStale) else { return nil }
        if isStale {
            // Re-save bookmark if stale but still valid
            if let newData = try? url.bookmarkData() {
                if let idx = completedDownloads.firstIndex(where: { $0.bookmarkData == data }) {
                    completedDownloads[idx].bookmarkData = newData
                    saveCompletedDownloads()
                }
            }
        }
        return url
    }

    private func directorySize(url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}

// MARK: - AVAssetDownloadDelegate

extension VideoDownloadManager: AVAssetDownloadDelegate {

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask,
                    didLoad timeRange: CMTimeRange, totalTimeRangesLoaded loadedTimeRanges: [NSValue],
                    timeRangeExpectedToLoad: CMTimeRange) {
        guard let assetId = activeDownloads[assetDownloadTask] else { return }

        var totalLoaded: Double = 0
        for value in loadedTimeRanges {
            let loaded = value.timeRangeValue
            totalLoaded += loaded.duration.seconds
        }
        let expected = timeRangeExpectedToLoad.duration.seconds
        let progress = expected > 0 ? min(totalLoaded / expected, 1.0) : 0

        DispatchQueue.main.async {
            self.progressByAssetId[assetId] = progress
        }
    }

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let assetId = activeDownloads[assetDownloadTask] else { return }

        // Save bookmark to the downloaded .movpkg
        guard let bookmarkData = try? location.bookmarkData() else {
            print("[VideoDownloadManager] Failed to create bookmark for \(assetId)")
            cleanupDownloadState(assetId: assetId)
            return
        }

        let asset = pendingAssets[assetId]
        let downloaded = DownloadedVideo(
            id: assetId,
            title: asset?.title ?? "Video",
            category: asset?.category,
            duration: asset?.duration,
            thumbnailURLString: asset?.thumbnailURL?.absoluteString,
            dateDownloaded: Date(),
            bookmarkData: bookmarkData
        )

        DispatchQueue.main.async {
            self.completedDownloads.insert(downloaded, at: 0)
            self.saveCompletedDownloads()
            self.cleanupDownloadState(assetId: assetId)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let downloadTask = task as? AVAssetDownloadTask,
              let assetId = activeDownloads[downloadTask] else { return }

        if let error = error as? NSError {
            // Cancelled by user is not a real error
            if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
                // Already cleaned up in cancelDownload
            } else {
                print("[VideoDownloadManager] Download failed for \(assetId): \(error.localizedDescription)")
            }
        }

        DispatchQueue.main.async {
            self.cleanupDownloadState(assetId: assetId)
        }
    }
}

#endif
