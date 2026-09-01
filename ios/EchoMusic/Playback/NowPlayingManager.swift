import MediaPlayer
import UIKit

/// Manages the lock screen / Control Center surface:
/// `MPNowPlayingInfoCenter` (metadata + artwork) and `MPRemoteCommandCenter`
/// (play / pause / next / previous / scrub).
@MainActor
final class NowPlayingManager {

    private var artworkTask: Task<Void, Never>?

    // MARK: - Remote commands
    // Wire once at startup. Handlers run on the main thread (MPRemoteCommandCenter
    // guarantees this), which is where PlaybackManager lives.

    func configureRemoteCommands(
        play: @escaping () -> Void,
        pause: @escaping () -> Void,
        toggle: @escaping () -> Void,
        next: @escaping () -> Void,
        previous: @escaping () -> Void,
        seek: @escaping (TimeInterval) -> Void
    ) {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { _ in
            play()
            return .success
        }
        center.pauseCommand.addTarget { _ in
            pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { _ in
            toggle()
            return .success
        }
        center.nextTrackCommand.addTarget { _ in
            next()
            return .success
        }
        center.previousTrackCommand.addTarget { _ in
            previous()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { event in
            guard let change = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            seek(change.positionTime)
            return .success
        }

        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
    }

    // MARK: - Now Playing info

    func update(for song: Song, currentTime: TimeInterval, duration: TimeInterval) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artistNames,
            MPMediaItemPropertyAlbumTitle: song.album?.name ?? "",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPMediaItemPropertyMediaType: MPMediaType.music.rawValue,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
        loadArtwork(urlString: song.thumbnail)
    }

    /// Called from the periodic time observer while playing.
    func updateProgress(currentTime: TimeInterval, rate: Double) {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Artwork

    private func loadArtwork(urlString: String?) {
        guard let urlString,
              let url = URL(string: MediaParser.thumbnailURL(urlString, width: 640)) else {
            return
        }
        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else {
                return
            }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
            info[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }
}
