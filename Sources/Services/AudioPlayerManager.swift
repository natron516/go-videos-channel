import Foundation
import AVFoundation
import Combine
import MediaPlayer

@MainActor
class AudioPlayerManager: ObservableObject {
    static let shared = AudioPlayerManager()

    @Published var isPlaying = false
    @Published var currentTitle: String = ""
    @Published var currentArtist: String = ""
    @Published var progress: Double = 0
    @Published var duration: Double = 0
    @Published var isLoading = false
    @Published var hasItem = false
    @Published var playbackRate: Float = 1.0
    /// ID of the currently playing track (for position saving)
    var currentTrackId: String?

    /// Position (seconds) to seek to once the item is ready to play
    private var pendingResumePosition: Double = 0

    /// Called when the current track finishes playing (for autoplay)
    var onFinish: (() -> Void)?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()

    /// Cover image URL for Now Playing artwork
    private var currentCoverUrl: String?

    /// Public read access to cover URL for UI
    var currentCoverUrlPublic: String? { currentCoverUrl }

    private init() {
        setupRemoteCommandCenter()
        // Save position when the app goes to background or is about to terminate
        #if !os(tvOS)
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.saveCurrentPosition() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.saveCurrentPosition() }
        }
        #endif
    }

    /// Persist the current playback position immediately (if we have a track).
    private func saveCurrentPosition() {
        guard let trackId = currentTrackId, let p = player else { return }
        let secs = p.currentTime().seconds
        guard secs.isFinite, secs > 0 else { return }
        PlaybackTracker.shared.savePosition(trackId, seconds: secs)
    }

    /// Activate the audio session on-demand (called right before playback starts).
    private func activateAudioSessionIfNeeded() {
        #if !os(tvOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AudioPlayerManager: Audio session setup failed: \(error)")
        }
        #endif
    }

    // MARK: - Remote Command Center (lock screen / Control Center controls)

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.skip(seconds: 15)
            return .success
        }
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skip(seconds: -15)
            return .success
        }
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let posEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let dur = self.duration
            guard dur > 0 else { return .commandFailed }
            self.seek(to: posEvent.positionTime / dur)
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = currentTitle
        info[MPMediaItemPropertyArtist] = currentArtist
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player?.currentTime().seconds ?? 0
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadNowPlayingArtwork() {
        guard let urlStr = currentCoverUrl, let url = URL(string: urlStr) else { return }
        Task.detached(priority: .utility) {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            await MainActor.run {
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        }
    }

    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Public API

    func play(url urlString: String, title: String, artist: String, coverUrl: String? = nil, trackId: String? = nil, resumeAt: Double = 0) {
        guard let url = URL(string: urlString) else { return }

        // Dismiss any active video player first
        dismissTopPlayer()

        // Reset progress immediately for UI
        progress = 0
        duration = 0

        // Stop any existing playback
        stop()

        // Activate audio session now that the user is actually playing something
        activateAudioSessionIfNeeded()

        currentTitle = title
        currentArtist = artist
        currentCoverUrl = coverUrl
        if let trackId { currentTrackId = trackId }
        pendingResumePosition = resumeAt
        isLoading = true
        hasItem = true

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer

        // Observe status
        item.publisher(for: \.status)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self else { return }
                switch status {
                case .readyToPlay:
                    self.isLoading = false
                    if let dur = self.player?.currentItem?.duration, !dur.isIndefinite {
                        self.duration = CMTimeGetSeconds(dur)
                    }
                    // Resume from saved position now that the item is ready
                    if self.pendingResumePosition > 0 {
                        let resumeTime = CMTime(seconds: self.pendingResumePosition, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                        self.player?.seek(to: resumeTime, toleranceBefore: .zero, toleranceAfter: .zero)
                        self.pendingResumePosition = 0
                    }
                    self.player?.rate = self.playbackRate
                    self.isPlaying = true
                    self.updateNowPlayingInfo()
                    self.loadNowPlayingArtwork()
                case .failed:
                    self.isLoading = false
                    self.isPlaying = false
                default:
                    break
                }
            }
            .store(in: &cancellables)

        // Observe duration
        item.publisher(for: \.duration)
            .receive(on: RunLoop.main)
            .sink { [weak self] dur in
                guard let self else { return }
                if !dur.isIndefinite && dur.seconds > 0 {
                    self.duration = dur.seconds
                }
            }
            .store(in: &cancellables)

        // Time observer for progress + position saving + Now Playing updates
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        var saveCounter = 0
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, let dur = self.player?.currentItem?.duration, !dur.isIndefinite, dur.seconds > 0 else { return }
            self.progress = time.seconds / dur.seconds
            // Save position to Firestore every 10 seconds
            saveCounter += 1
            if saveCounter % 20 == 0 {
                if let trackId = self.currentTrackId {
                    PlaybackTracker.shared.savePosition(trackId, seconds: time.seconds)
                }
                // Update Now Playing elapsed time periodically
                self.updateNowPlayingInfo()
            }
        }

        // Observe end — dispatch onFinish async to avoid cancelling the active sink
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.isPlaying = false
                self?.progress = 0
                let finish = self?.onFinish
                DispatchQueue.main.async {
                    finish?()
                }
            }
            .store(in: &cancellables)
    }

    func pause() {
        player?.pause()
        isPlaying = false
        saveCurrentPosition()
        updateNowPlayingInfo()
    }

    func resume() {
        player?.rate = playbackRate
        isPlaying = true
        updateNowPlayingInfo()
    }

    func stop() {
        saveCurrentPosition()
        if let obs = timeObserver, let p = player {
            p.removeTimeObserver(obs)
            timeObserver = nil
        }
        player?.pause()
        player = nil
        isPlaying = false
        isLoading = false
        hasItem = false
        progress = 0
        duration = 0
        currentTitle = ""
        currentArtist = ""
        currentCoverUrl = nil
        currentTrackId = nil
        pendingResumePosition = 0
        cancellables.removeAll()
        playbackRate = 1.0
        clearNowPlayingInfo()
    }

    func seek(to fraction: Double) {
        guard let player, let dur = player.currentItem?.duration, !dur.isIndefinite else { return }
        let targetTime = CMTime(seconds: dur.seconds * fraction, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: targetTime)
    }

    func skip(seconds: Double) {
        guard let player else { return }
        let current = player.currentTime().seconds
        let dur = player.currentItem?.duration.seconds ?? 0
        guard dur > 0 else { return }
        let target = min(max(current + seconds, 0), dur)
        let time = CMTime(seconds: target, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: time)
    }

    var currentSeconds: Double {
        player?.currentTime().seconds ?? 0
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { resume() }
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying {
            player?.rate = rate
        }
        updateNowPlayingInfo()
    }

    // MARK: - Formatted time helpers

    func formattedTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var currentTimeFormatted: String {
        guard let player else { return "0:00" }
        let secs = CMTimeGetSeconds(player.currentTime())
        return formattedTime(secs)
    }

    var durationFormatted: String {
        formattedTime(duration)
    }
}
