import Foundation
import AVFoundation
import Combine

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
    /// ID of the currently playing track (for position saving)
    var currentTrackId: String?

    /// Called when the current track finishes playing (for autoplay)
    var onFinish: (() -> Void)?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupAudioSession()
    }

    private func setupAudioSession() {
        #if !os(tvOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AudioPlayerManager: Audio session setup failed: \(error)")
        }
        #endif
    }

    // MARK: - Public API

    func play(url urlString: String, title: String, artist: String) {
        guard let url = URL(string: urlString) else { return }

        // Dismiss any active video player first
        dismissTopPlayer()

        // Stop any existing playback
        stop()

        currentTitle = title
        currentArtist = artist
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
                    self.player?.play()
                    self.isPlaying = true
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

        // Time observer for progress + position saving
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        var saveCounter = 0
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, let dur = self.player?.currentItem?.duration, !dur.isIndefinite, dur.seconds > 0 else { return }
            self.progress = time.seconds / dur.seconds
            // Save position to Firestore every 10 seconds
            saveCounter += 1
            if saveCounter % 20 == 0, let trackId = self.currentTrackId {
                PlaybackTracker.shared.savePosition(trackId, seconds: time.seconds)
            }
        }

        // Observe end
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.isPlaying = false
                self?.progress = 0
                self?.onFinish?()
            }
            .store(in: &cancellables)
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func resume() {
        player?.play()
        isPlaying = true
    }

    func stop() {
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
        cancellables.removeAll()
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
