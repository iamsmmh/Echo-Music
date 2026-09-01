import SwiftUI
import UIKit

/// Full-screen "now playing" view: blurred artwork background, big album art,
/// scrubber, transport controls, shuffle & repeat.
struct PlayerScreen: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var isScrubbing = false
    @State private var scrubTime: TimeInterval?

    var body: some View {
        ZStack {
            BlurredArtworkBackground(urlString: env.player.currentSong?.thumbnail)

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 8)
                artwork
                Spacer(minLength: 24)
                titleBlock
                progressSection
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                controls
                    .padding(.top, 20)
                Spacer(minLength: 24)
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.title3)
            }
            Spacer()
            Text("Now Playing")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Button {} label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var artwork: some View {
        let side = min(UIScreen.main.bounds.width - 64, 380)
        return ArtworkView(
            urlString: env.player.currentSong?.thumbnail,
            size: side,
            cornerRadius: 16
        )
        .shadow(color: .black.opacity(0.4), radius: 24, y: 8)
    }

    private var titleBlock: some View {
        VStack(spacing: 6) {
            Text(env.player.currentSong?.title ?? "")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(env.player.currentSong?.artistNames ?? "")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
        .padding(.horizontal, 24)
    }

    private var progressSection: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { displayedTime },
                    set: { scrubTime = $0 }
                ),
                in: 0...max(env.player.duration, 1)
            ) { editing in
                if editing {
                    isScrubbing = true
                } else {
                    isScrubbing = false
                    env.player.seek(to: scrubTime ?? env.player.currentTime)
                    scrubTime = nil
                }
            }
            .tint(.white)

            HStack {
                Text(TimeParser.string(displayedTime))
                Spacer()
                Text(TimeParser.string(env.player.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var controls: some View {
        HStack(spacing: 0) {
            Spacer()
            shuffleButton
            Spacer()
            previousButton
            Spacer()
            playPauseButton
            Spacer()
            nextButton
            Spacer()
            repeatButton
            Spacer()
        }
        .frame(height: 92)
    }

    // MARK: - Control buttons

    private var shuffleButton: some View {
        Button { env.player.toggleShuffle() } label: {
            Image(systemName: "shuffle")
                .foregroundStyle(env.player.isShuffle ? .white : .white.opacity(0.5))
        }
        .frame(width: 56)
        .buttonStyle(.plain)
    }

    private var previousButton: some View {
        Button { env.player.skipToPrevious() } label: {
            Image(systemName: "backward.fill")
                .font(.title)
        }
        .frame(width: 72)
        .buttonStyle(.plain)
    }

    private var playPauseButton: some View {
        Button { env.player.togglePlayPause() } label: {
            Image(systemName: env.player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 76))
        }
        .buttonStyle(.plain)
    }

    private var nextButton: some View {
        Button { env.player.skipToNext() } label: {
            Image(systemName: "forward.fill")
                .font(.title)
        }
        .frame(width: 72)
        .buttonStyle(.plain)
    }

    private var repeatButton: some View {
        Button {
            let modes: [PlaybackManager.RepeatMode] = [.off, .all, .one]
            let next = modes[(Int(env.player.repeatMode.rawValue) + 1) % modes.count]
            env.player.repeatMode = next
        } label: {
            Image(systemName: repeatIconName)
                .foregroundStyle(env.player.repeatMode == .off ? .white.opacity(0.5) : .white)
        }
        .frame(width: 56)
        .buttonStyle(.plain)
    }

    private var repeatIconName: String {
        switch env.player.repeatMode {
        case .off, .all: "repeat"
        case .one: "repeat.1"
        }
    }

    // MARK: - Helpers

    private var displayedTime: TimeInterval {
        if isScrubbing { return scrubTime ?? env.player.currentTime }
        return env.player.currentTime
    }
}

#Preview {
    PlayerScreen()
        .environmentObject(AppEnvironment.shared)
}
