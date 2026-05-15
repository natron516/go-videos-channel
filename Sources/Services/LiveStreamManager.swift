import Foundation
import Combine

/// Shared live stream state. Updated by HomeView and SermonLibraryView on every load.
class LiveStreamManager: ObservableObject {
    static let shared = LiveStreamManager()
    private init() {}

    @Published var activeStream: MuxLiveStream?
    @Published var liveAsset: MuxAsset?

    var isLive: Bool { activeStream?.isLive == true }

    /// The category of the current live stream. Prefers the matched asset's category,
    /// then falls back to the stream's own passthrough category.
    var liveCategory: String? {
        liveAsset?.category ?? activeStream?.category
    }

    /// Call this from any view that loads assets + live streams.
    /// Set `authoritative: true` only from the root poller that has the final say on live state.
    func update(stream: MuxLiveStream?, allAssets: [MuxAsset], authoritative: Bool = false) {
        guard let stream = stream, stream.isLive else {
            // Only clear when the authoritative source confirms no live stream
            if authoritative {
                activeStream = nil
                liveAsset = nil
            }
            return
        }
        // Live stream confirmed — always update
        activeStream = stream
        // 1. active_asset_id — Mux's definitive pointer to the currently-recording asset
        if let activeId = stream.activeAssetId {
            liveAsset = allAssets.first { $0.id == activeId }
            if liveAsset != nil { return }
        }
        // 2. Fall back: any asset currently "preparing" (being recorded right now)
        liveAsset = allAssets.first { $0.status == "preparing" }
    }

    /// Returns true if the given asset is the one currently being live-streamed.
    func isAssetLive(_ asset: MuxAsset) -> Bool {
        guard isLive else { return false }
        // If we identified the exact active asset, match by ID only
        if let live = liveAsset { return live.id == asset.id }
        // Fallback: active_asset_id direct check
        if let activeId = activeStream?.activeAssetId { return asset.id == activeId }
        return false
    }
}
