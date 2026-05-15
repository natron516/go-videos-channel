import Foundation
import AVFoundation

/// Intercepts Mux live HLS manifests and strips #EXT-X-PROGRAM-DATE-TIME tags
/// so AVKit shows elapsed time (with seconds) instead of wall-clock time.
///
/// Usage: call LiveHLSProxy.makePlayerItem(url:) for live streams.
/// The proxy rewrites the URL scheme to "golivelane://" so it can intercept
/// manifest requests; segment URLs are left as absolute HTTPS so AVFoundation
/// fetches them directly without going through the delegate.
class LiveHLSProxy: NSObject, AVAssetResourceLoaderDelegate {

    static let scheme = "golivelane"

    // Keep a strong reference so the delegate isn't deallocated mid-playback
    private var retainSelf: LiveHLSProxy?

    /// Creates an AVPlayerItem for a live stream URL with clock-time display suppressed.
    static func makePlayerItem(url: URL) -> AVPlayerItem {
        let proxy = LiveHLSProxy()
        proxy.retainSelf = proxy  // self-retain until item is done

        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return AVPlayerItem(url: url)
        }
        comps.scheme = scheme
        guard let proxyURL = comps.url else { return AVPlayerItem(url: url) }

        let asset = AVURLAsset(url: proxyURL)
        asset.resourceLoader.setDelegate(proxy, queue: DispatchQueue(label: "LiveHLSProxy", qos: .userInitiated))

        let item = AVPlayerItem(asset: asset)
        // Allow seeking from beginning of DVR window and show elapsed time
        item.automaticallyPreservesTimeOffsetFromLive = false
        // Ask AVKit to prefer a short forward buffer so the scrubber
        // treats the content as shorter and shows MM:SS rather than H:MM
        item.preferredForwardBufferDuration = 30

        // Release self-retain when item is deallocated (via KVO on status going to .failed or end notification)
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
            proxy.retainSelf = nil
        }

        return item
    }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = loadingRequest.request.url else { return false }
        Task { await self.handle(loadingRequest, originalURL: url) }
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        loadingRequest.finishLoading(with: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
    }

    // MARK: - Internal

    private func handle(_ loadingRequest: AVAssetResourceLoadingRequest, originalURL: URL) async {
        // Convert back to HTTPS
        guard var comps = URLComponents(url: originalURL, resolvingAgainstBaseURL: false) else {
            loadingRequest.finishLoading(with: makeError("Bad URL"))
            return
        }
        comps.scheme = "https"
        guard let realURL = comps.url else {
            loadingRequest.finishLoading(with: makeError("Bad URL"))
            return
        }

        do {
            var request = URLRequest(url: realURL)
            // Forward range header if present (segment byte-range requests)
            if let range = loadingRequest.request.value(forHTTPHeaderField: "Range") {
                request.setValue(range, forHTTPHeaderField: "Range")
            }

            let (data, response) = try await URLSession.shared.data(for: request)

            if let info = loadingRequest.contentInformationRequest,
               let http = response as? HTTPURLResponse {
                info.contentType = http.value(forHTTPHeaderField: "Content-Type") ?? "application/vnd.apple.mpegurl"
                info.contentLength = Int64(data.count)
                info.isByteRangeAccessSupported = false
            }

            // For HLS playlists, strip DATE-TIME and rewrite nested playlist URLs
            let isPlaylist = realURL.pathExtension == "m3u8"
                || (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.contains("mpegurl") == true

            if isPlaylist, let text = String(data: data, encoding: .utf8) {
                let modified = processPlaylist(text, baseURL: realURL)
                let modifiedData = modified.data(using: .utf8) ?? data
                loadingRequest.dataRequest?.respond(with: modifiedData)
            } else {
                loadingRequest.dataRequest?.respond(with: data)
            }

            loadingRequest.finishLoading()
        } catch {
            loadingRequest.finishLoading(with: error)
        }
    }

    /// Detect whether this is a master playlist (has #EXT-X-STREAM-INF)
    /// or a media playlist (has #EXTINF / #EXT-X-TARGETDURATION).
    /// Master playlists: rewrite ALL bare URL lines (they’re sub-playlists).
    /// Media playlists: strip timestamp tags, leave segment URLs alone.
    private func processPlaylist(_ text: String, baseURL: URL) -> String {
        let isMaster = text.contains("#EXT-X-STREAM-INF")
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Strip timestamp tags in ALL playlists (master + media)
            if trimmed.hasPrefix("#EXT-X-PROGRAM-DATE-TIME") { continue }
            if trimmed.hasPrefix("#EXT-X-DATERANGE") { continue }

            // Rewrite URI= attributes in tag lines (e.g. #EXT-X-MEDIA, #EXT-X-I-FRAME-STREAM-INF)
            if trimmed.hasPrefix("#") && trimmed.contains("URI=\"") {
                result.append(rewriteURIAttribute(in: line, baseURL: baseURL))
                continue
            }

            // Bare URL lines (not tags, not empty)
            if !trimmed.hasPrefix("#") && !trimmed.isEmpty {
                if isMaster {
                    // Master playlist: every bare URL is a sub-playlist — rewrite through proxy
                    result.append(rewriteURL(trimmed, baseURL: baseURL))
                } else {
                    // Media playlist: bare URLs are segments — leave as-is
                    result.append(line)
                }
                continue
            }

            result.append(line)
        }
        return result.joined(separator: "\n")
    }

    /// Rewrite any URL to use the proxy scheme (handles query strings, relative URLs)
    private func rewriteURL(_ urlString: String, baseURL: URL) -> String {
        // Resolve relative URLs first
        let absolute: String
        if urlString.hasPrefix("https://") || urlString.hasPrefix("http://") {
            absolute = urlString
        } else if let resolved = URL(string: urlString, relativeTo: baseURL)?.absoluteString {
            absolute = resolved
        } else {
            return urlString
        }
        // Swap scheme
        if absolute.hasPrefix("https://") {
            return absolute.replacingOccurrences(of: "https://", with: "\(LiveHLSProxy.scheme)://")
        }
        if absolute.hasPrefix("http://") {
            return absolute.replacingOccurrences(of: "http://", with: "\(LiveHLSProxy.scheme)://")
        }
        return urlString
    }

    /// Rewrite ALL URI="..." attributes in a tag line through the proxy
    private func rewriteURIAttribute(in line: String, baseURL: URL) -> String {
        // Match URI="..." — any value, not just .m3u8
        guard let regex = try? NSRegularExpression(pattern: #"URI="([^"]+)""#) else { return line }
        let nsLine = line as NSString
        var result = line
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
        for match in matches.reversed() {
            guard match.numberOfRanges > 1 else { continue }
            let uriRange = match.range(at: 1)
            let uriString = nsLine.substring(with: uriRange)
            let rewritten = rewriteURL(uriString, baseURL: baseURL)
            result = (result as NSString).replacingCharacters(in: uriRange, with: rewritten)
        }
        return result
    }

    private func makeError(_ msg: String) -> NSError {
        NSError(domain: "LiveHLSProxy", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
    }
}
