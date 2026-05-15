#if !os(tvOS)
import Foundation
import GoogleCast
import AVFoundation

// MARK: - CastManager
// Initialises the Google Cast SDK and provides helpers for launching media
// on a discovered Cast receiver.

final class CastManager: NSObject {
    static let shared = CastManager()
    private override init() {}

    private let kReceiverAppID = "6C3A18CB"

    // Call once at app launch (before any Cast UI is shown)
    func setup() {
        // Use default media receiver for broadest device compatibility
        let criteria = GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID)
        let options  = GCKCastOptions(discoveryCriteria: criteria)
        options.physicalVolumeButtonsWillControlDeviceVolume = true
        GCKCastContext.setSharedInstanceWith(options)
        GCKCastContext.sharedInstance().useDefaultExpandedMediaControls = true
        GCKLogger.sharedInstance().delegate = self
        print("[Cast] SDK initialized with default receiver")
        print("[Cast] Discovery active: \(GCKCastContext.sharedInstance().discoveryManager.discoveryActive)")
        GCKCastContext.sharedInstance().discoveryManager.startDiscovery()
        print("[Cast] Discovery started manually")
    }

    // Cast a Mux video to the connected receiver
    func cast(url: URL, title: String?, startTime: Double = 0) {
        guard let session = GCKCastContext.sharedInstance().sessionManager.currentCastSession else {
            return
        }

        let metadata = GCKMediaMetadata(metadataType: .movie)
        metadata.setString(title ?? "GO Videos", forKey: kGCKMetadataKeyTitle)
        metadata.setString("GO Videos", forKey: kGCKMetadataKeyStudio)

        let mediaInfo = GCKMediaInformationBuilder(contentURL: url)
        mediaInfo.streamType       = .buffered
        mediaInfo.contentType      = "application/x-mpegURL"
        mediaInfo.metadata         = metadata
        let media = mediaInfo.build()

        let options = GCKMediaLoadOptions()
        options.playPosition = startTime

        session.remoteMediaClient?.loadMedia(media, with: options)
    }

    // True when a Cast session is active
    var isConnected: Bool {
        GCKCastContext.sharedInstance().castState == .connected
    }
}

extension CastManager: GCKLoggerDelegate {
    func logMessage(_ message: String, at level: GCKLoggerLevel, fromFunction function: String, location: String) {
        // Log all cast messages for debugging
        print("[Cast \(level.rawValue)] \(function): \(message)")
    }
}
#endif
