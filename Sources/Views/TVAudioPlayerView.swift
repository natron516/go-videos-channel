import SwiftUI
import AVFoundation

/// Full-screen audio player for tvOS.
/// Shows cover art, track title/artist, transport controls (skip ±15s, play/pause),
/// playback speed selector, and a progress bar with elapsed/remaining time.
struct TVAudioPlayerView: View {
    @ObservedObject private var audioPlayer = AudioPlayerManager.shared
    @Environment(\.dismiss) var dismiss
    @State private var playbackSpeed: Float = 1.0
    @FocusState private var focusedControl: AudioControl?

    private let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    enum AudioControl: Hashable {
        case skipBack, playPause, skipForward, speed, close
    }

    var body: some View {
        ZStack {
            // Background — blurred cover art or dark gradient
            backgroundLayer

            // Content
            VStack(spacing: 40) {
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

                // Speed selector
                speedSelector

                Spacer()

                // Close button
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.callout.bold())
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 32)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Capsule())
                }
                .focused($focusedControl, equals: .close)
                .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            focusedControl = .playPause
            playbackSpeed = audioPlayer.playbackRate
        }
        .onChange(of: audioPlayer.hasItem) { hasItem in
            if !hasItem { dismiss() }
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
                        .frame(width: 400, height: 400)
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
            .frame(width: 400, height: 400)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 80))
                    .foregroundColor(.white.opacity(0.3))
            )
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 8) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 6)
                    Capsule()
                        .fill(Color.blue)
                        .frame(width: geo.size.width * CGFloat(audioPlayer.progress), height: 6)
                }
            }
            .frame(height: 6)

            // Times
            HStack {
                Text(audioPlayer.currentTimeFormatted)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Text("-" + remainingTime)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 120)
    }

    private var remainingTime: String {
        let remaining = max(audioPlayer.duration - (audioPlayer.duration * audioPlayer.progress), 0)
        return audioPlayer.formattedTime(remaining)
    }

    // MARK: - Transport Controls

    private var transportControls: some View {
        HStack(spacing: 60) {
            // Skip back 15s
            Button {
                audioPlayer.skip(seconds: -15)
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 44))
                    .foregroundColor(.white)
                    .frame(width: 80, height: 80)
            }
            .focused($focusedControl, equals: .skipBack)

            // Play / Pause
            Button {
                audioPlayer.togglePlayPause()
            } label: {
                Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 76))
                    .foregroundColor(.white)
                    .frame(width: 100, height: 100)
            }
            .focused($focusedControl, equals: .playPause)

            // Skip forward 15s
            Button {
                audioPlayer.skip(seconds: 15)
            } label: {
                Image(systemName: "goforward.15")
                    .font(.system(size: 44))
                    .foregroundColor(.white)
                    .frame(width: 80, height: 80)
            }
            .focused($focusedControl, equals: .skipForward)
        }
    }

    // MARK: - Speed Selector

    private var speedSelector: some View {
        HStack(spacing: 16) {
            Text("Speed")
                .font(.callout)
                .foregroundColor(.white.opacity(0.6))

            ForEach(speeds, id: \.self) { speed in
                Button {
                    playbackSpeed = speed
                    audioPlayer.setPlaybackRate(speed)
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
                .focused($focusedControl, equals: .speed)
            }
        }
    }

    private func speedLabel(_ speed: Float) -> String {
        if speed == 1.0 { return "1×" }
        if speed == floor(speed) { return "\(Int(speed))×" }
        return String(format: "%.1f×", speed)
    }
}
