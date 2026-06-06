import SwiftUI
import AVFoundation

// MARK: - Full-screen audio player for tvOS
/// Shows cover art, track title/artist, transport controls (skip ±15s, play/pause),
/// collapsible playback speed, and a scrubbable progress bar.
/// Has a back button that collapses to a mini player.
struct TVAudioPlayerView: View {
    @ObservedObject private var audioPlayer = AudioPlayerManager.shared
    var onCollapse: () -> Void = {}

    @State private var playbackSpeed: Float = 1.0
    @FocusState private var focusedControl: AudioControl?
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
    @State private var showSpeedOptions = false

    private let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    enum AudioControl: Hashable {
        case back, scrubber, skipBack, playPause, skipForward, speedToggle, speedOption(Float)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background
            backgroundLayer

            // Back button (top-left)
            Button {
                onCollapse()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
            .focused($focusedControl, equals: .back)
            .padding(.top, 40)
            .padding(.leading, 40)

            // Content
            VStack(spacing: 32) {
                Spacer()

                // Cover art
                coverArt

                // Title / Artist
                VStack(spacing: 8) {
                    Text(audioPlayer.currentTitle)
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    if !audioPlayer.currentArtist.isEmpty {
                        Text(audioPlayer.currentArtist)
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 60)

                // Progress bar + times
                progressSection

                // Transport controls
                transportControls

                // Playback Speed button (collapsed by default)
                speedButton

                // Speed options (expanded)
                if showSpeedOptions {
                    speedOptions
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer()
            }
        }
        .onAppear {
            focusedControl = .playPause
            playbackSpeed = audioPlayer.playbackRate
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundLayer: some View {
        if let urlStr = audioPlayer.currentCoverUrlPublic, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .blur(radius: 60)
                        .overlay(Color.black.opacity(0.65))
                } else {
                    Color.black
                }
            }
        } else {
            LinearGradient(
                colors: [Color(white: 0.12), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - Cover Art

    @ViewBuilder
    private var coverArt: some View {
        if let urlStr = audioPlayer.currentCoverUrlPublic, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 360, height: 360)
                        .cornerRadius(20)
                        .shadow(color: .black.opacity(0.5), radius: 30, y: 15)
                } else {
                    placeholderArt
                }
            }
        } else {
            placeholderArt
        }
    }

    private var placeholderArt: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.white.opacity(0.08))
            .frame(width: 360, height: 360)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 80))
                    .foregroundColor(.white.opacity(0.3))
            )
    }

    // MARK: - Progress (scrubbable)

    private var progressSection: some View {
        let displayProgress = isScrubbing ? scrubValue : audioPlayer.progress
        let currentTime = isScrubbing
            ? audioPlayer.formattedTime(scrubValue * audioPlayer.duration)
            : audioPlayer.currentTimeFormatted
        let remaining = max(audioPlayer.duration - (displayProgress * audioPlayer.duration), 0)

        return VStack(spacing: 8) {
            TVScrubberBar(
                progress: displayProgress,
                isFocused: focusedControl == .scrubber,
                onScrub: { newVal in
                    scrubValue = newVal
                    isScrubbing = true
                },
                onCommit: {
                    audioPlayer.seek(to: scrubValue)
                    isScrubbing = false
                }
            )
            .focused($focusedControl, equals: .scrubber)

            HStack {
                Text(currentTime)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Text("-" + audioPlayer.formattedTime(remaining))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 120)
    }

    // MARK: - Transport Controls

    private var transportControls: some View {
        HStack(spacing: 60) {
            Button { audioPlayer.skip(seconds: -15) } label: {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 44))
                    .foregroundColor(.white)
                    .frame(width: 80, height: 80)
            }
            .focused($focusedControl, equals: .skipBack)

            Button { audioPlayer.togglePlayPause() } label: {
                Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 76))
                    .foregroundColor(.white)
                    .frame(width: 100, height: 100)
            }
            .focused($focusedControl, equals: .playPause)

            Button { audioPlayer.skip(seconds: 15) } label: {
                Image(systemName: "goforward.15")
                    .font(.system(size: 44))
                    .foregroundColor(.white)
                    .frame(width: 80, height: 80)
            }
            .focused($focusedControl, equals: .skipForward)
        }
    }

    // MARK: - Speed Toggle Button

    private var speedButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                showSpeedOptions.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.needle")
                    .font(.callout)
                Text("Playback Speed: \(speedLabel(playbackSpeed))")
                    .font(.callout.bold())
                Image(systemName: showSpeedOptions ? "chevron.up" : "chevron.down")
                    .font(.caption)
            }
            .foregroundColor(.white.opacity(0.7))
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.12))
            .clipShape(Capsule())
        }
        .focused($focusedControl, equals: .speedToggle)
    }

    // MARK: - Speed Options (expanded)

    private var speedOptions: some View {
        HStack(spacing: 12) {
            ForEach(speeds, id: \.self) { speed in
                Button {
                    playbackSpeed = speed
                    audioPlayer.setPlaybackRate(speed)
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showSpeedOptions = false
                    }
                } label: {
                    Text(speedLabel(speed))
                        .font(.callout.bold())
                        .foregroundColor(playbackSpeed == speed ? .blue : .white.opacity(0.6))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            playbackSpeed == speed
                                ? Color.blue.opacity(0.2)
                                : Color.white.opacity(0.08)
                        )
                        .clipShape(Capsule())
                }
                .focused($focusedControl, equals: .speedOption(speed))
            }
        }
    }

    private func speedLabel(_ speed: Float) -> String {
        if speed == 1.0 { return "1×" }
        if speed == floor(speed) { return "\(Int(speed))×" }
        return String(format: "%.1f×", speed)
    }
}

// MARK: - tvOS Mini Audio Player
/// Compact bar shown at the bottom of the content area when audio is playing
/// but the user has navigated away from the full player.
struct TVAudioMiniPlayer: View {
    @ObservedObject private var audioPlayer = AudioPlayerManager.shared
    var onExpand: () -> Void = {}

    var body: some View {
        Button {
            onExpand()
        } label: {
            HStack(spacing: 16) {
                // Cover art thumbnail
                if let urlStr = audioPlayer.currentCoverUrlPublic, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                                .frame(width: 48, height: 48)
                                .cornerRadius(8)
                                .clipped()
                        } else {
                            miniPlaceholder
                        }
                    }
                } else {
                    miniPlaceholder
                }

                // Title + artist
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

                // Progress
                ProgressView(value: audioPlayer.progress)
                    .tint(.blue)
                    .frame(width: 200)

                // Play/Pause
                Button {
                    audioPlayer.togglePlayPause()
                } label: {
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }

                // Stop
                Button {
                    audioPlayer.stop()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.92))
        }
        .buttonStyle(.plain)
    }

    private var miniPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.1))
            .frame(width: 48, height: 48)
            .overlay(Image(systemName: "music.note").foregroundColor(.secondary))
    }
}

// MARK: - tvOS Scrubber Bar
struct TVScrubberBar: View {
    let progress: Double
    let isFocused: Bool
    let onScrub: (Double) -> Void
    let onCommit: () -> Void

    var body: some View {
        GeometryReader { geo in
            let height: CGFloat = isFocused ? 14 : 6
            let knobSize: CGFloat = isFocused ? 28 : 0
            let fillWidth = geo.size.width * CGFloat(progress)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(isFocused ? 0.3 : 0.2))
                    .frame(height: height)
                Capsule()
                    .fill(Color.blue)
                    .frame(width: max(fillWidth, 0), height: height)

                if isFocused {
                    Circle()
                        .fill(Color.white)
                        .frame(width: knobSize, height: knobSize)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        .offset(x: max(min(fillWidth - knobSize / 2, geo.size.width - knobSize), 0))
                }
            }
            .frame(height: max(height, knobSize))
        }
        .frame(height: isFocused ? 28 : 6)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
        #if os(tvOS)
        .onMoveCommand { direction in
            guard isFocused else { return }
            let step: Double = 0.02
            switch direction {
            case .left:
                onScrub(max(progress - step, 0))
                onCommit()
            case .right:
                onScrub(min(progress + step, 1))
                onCommit()
            default: break
            }
        }
        .onPlayPauseCommand {
            AudioPlayerManager.shared.togglePlayPause()
        }
        #endif
    }
}
