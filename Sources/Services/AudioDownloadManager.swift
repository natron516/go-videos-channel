import AVFoundation
import UIKit

#if os(tvOS)
// Audio download not available on tvOS
class AudioDownloadManager: ObservableObject {
    static let shared = AudioDownloadManager()
    @Published var isDownloading = false
    @Published var progress: Double = 0
    @Published var downloadingAssetId: String?
    func downloadAudio(asset: MuxAsset) {}
    func cancel() {}
}
#else

/// Downloads audio-only M4A from a Mux HLS stream and presents a share sheet to save.
class AudioDownloadManager: ObservableObject {
    static let shared = AudioDownloadManager()

    @Published var isDownloading = false
    @Published var progress: Double = 0
    @Published var downloadingAssetId: String?

    private var exportSession: AVAssetExportSession?

    func downloadAudio(asset: MuxAsset) {
        guard !isDownloading, let url = asset.streamURL else { return }

        isDownloading = true
        progress = 0
        downloadingAssetId = asset.id

        let avAsset = AVURLAsset(url: url)

        // Use a timer to track export progress
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.progress = Double(self?.exportSession?.progress ?? 0)
            }
        }

        Task {
            do {
                // Load the asset's tracks
                let _ = try await avAsset.load(.tracks, .duration)

                guard let session = AVAssetExportSession(asset: avAsset, presetName: AVAssetExportPresetAppleM4A) else {
                    await finish(timer: progressTimer, error: "Could not create export session")
                    return
                }

                let sanitizedTitle = asset.title
                    .replacingOccurrences(of: "/", with: "-")
                    .replacingOccurrences(of: ":", with: "-")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let filename = sanitizedTitle.isEmpty ? "sermon_audio" : sanitizedTitle

                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(filename)
                    .appendingPathExtension("m4a")

                // Remove existing file if any
                try? FileManager.default.removeItem(at: tempURL)

                session.outputURL = tempURL
                session.outputFileType = .m4a
                self.exportSession = session

                await session.export()

                progressTimer.invalidate()

                switch session.status {
                case .completed:
                    await presentShareSheet(fileURL: tempURL)
                case .failed:
                    let errMsg = session.error?.localizedDescription ?? "Export failed"
                    await finish(timer: nil, error: errMsg)
                case .cancelled:
                    await finish(timer: nil, error: "Download cancelled")
                default:
                    await finish(timer: nil, error: "Unexpected export status")
                }
            } catch {
                progressTimer.invalidate()
                await finish(timer: nil, error: error.localizedDescription)
            }
        }
    }

    func cancel() {
        exportSession?.cancelExport()
        DispatchQueue.main.async {
            self.isDownloading = false
            self.progress = 0
            self.downloadingAssetId = nil
        }
    }

    @MainActor
    private func presentShareSheet(fileURL: URL) {
        isDownloading = false
        progress = 1.0
        downloadingAssetId = nil

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let rootVC = scene.windows.first?.rootViewController else { return }

        var presenter = rootVC
        while let presented = presenter.presentedViewController {
            presenter = presented
        }

        let activityVC = UIActivityViewController(
            activityItems: [fileURL],
            applicationActivities: nil
        )
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            // Clean up temp file after sharing
            try? FileManager.default.removeItem(at: fileURL)
        }
        activityVC.popoverPresentationController?.sourceView = presenter.view
        activityVC.popoverPresentationController?.sourceRect = CGRect(
            x: presenter.view.bounds.midX, y: presenter.view.bounds.midY,
            width: 0, height: 0
        )
        presenter.present(activityVC, animated: true)
    }

    @MainActor
    private func finish(timer: Timer?, error: String) {
        timer?.invalidate()
        isDownloading = false
        progress = 0
        downloadingAssetId = nil

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let rootVC = scene.windows.first?.rootViewController else { return }

        var presenter = rootVC
        while let presented = presenter.presentedViewController {
            presenter = presented
        }

        let alert = UIAlertController(title: "Audio Download Failed", message: error, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presenter.present(alert, animated: true)
    }
}
#endif
