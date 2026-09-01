import AVFoundation
import Combine
import Foundation

enum PlaybackError: LocalizedError {
    case noCurrentSong
    case streamUnavailable
    case streamRequiresDeciphering

    var errorDescription: String? {
        switch self {
        case .noCurrentSong: "No track is selected."
        case .streamUnavailable: "No playable audio stream was returned."
        case .streamRequiresDeciphering: "This stream needs signature deciphering, which isn't implemented yet."
        }
    }
}

/// The heart of the app: owns the queue and the `AVPlayer`, and exposes a small
/// publishable surface that SwiftUI views bind to. This is effectively the playback
/// view model — views bind to it directly instead of wrapping it in another layer.
///
/// Background audio requirements (all handled here):
///  • `AVAudioSession` category `.playback`           (AudioSessionManager)
///  • `UIBackgroundModes: [audio]` in Info.plist
///  • `MPNowPlayingInfoCenter` metadata               (NowPlayingManager)
///  • `MPRemoteCommandCenter` controls                (NowPlayingManager)
@MainActor
final class PlaybackManager: ObservableObject {

    enum RepeatMode: Int {
        case off, all, one
    }

    // MARK: Published state (what the UI binds to)

    @Published private(set) var queue: [Song] = []
    @Published private(set) var currentIndex: Int?
    @Published private(set) var currentPlaylistId: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var errorMessage: String?
    @Published var repeatMode: RepeatMode = .all
    @Published var isShuffle = false

    // Up-next panel (from the `next` endpoint) plus its tab endpoints, which the
    // queue sheet and the lyrics view consume.
    @Published private(set) var upNext: [Song] = []
    @Published private(set) var upNextContinuation: String?
    @Published private(set) var lyricsEndpoint: BrowseEndpoint?
    @Published private(set) var relatedEndpoint: BrowseEndpoint?
    @Published private(set) var isFetchingUpNext = false

    var currentSong: Song? {
        guard let index = currentIndex, queue.indices.contains(index) else { return nil }
        return queue[index]
    }

    // MARK: Private

    private let api: InnertubeAPI
    private let audioSession: AudioSessionManager
    private let nowPlaying: NowPlayingManager
    private let offline: OfflineManager?
    private let player = AVPlayer()

    private var originalQueue: [Song] = []
    private var originalIndex: Int?

    /// How many times the current song has already been re-resolved after a stream
    /// failure (403 / expiry). Reset on every explicit `play(_:startingAt:)`.
    private var streamRetryCount: [String: Int] = [:]

    private var timeObserver: Any?
    private var timeControlObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?
    private var durationObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failedPlaybackObserver: NSObjectProtocol?

    // MARK: - Init

    init(
        api: InnertubeAPI,
        audioSession: AudioSessionManager = .shared,
        nowPlaying: NowPlayingManager = NowPlayingManager(),
        offline: OfflineManager? = nil
    ) {
        self.api = api
        self.audioSession = audioSession
        self.nowPlaying = nowPlaying
        self.offline = offline
        configurePlaybackInfrastructure()
    }

    private func configurePlaybackInfrastructure() {
        try? audioSession.configure()

        audioSession.onInterruptionBegan = { [weak self] in
            Task { @MainActor [weak self] in
                self?.pauseForInterruption()
            }
        }
        audioSession.onInterruptionEnded = { [weak self] in
            Task { @MainActor [weak self] in
                self?.resumeAfterInterruption()
            }
        }
        audioSession.onRouteLost = { [weak self] in
            Task { @MainActor [weak self] in
                self?.player.pause()
            }
        }
        audioSession.startObserving()

        nowPlaying.configureRemoteCommands(
            play: { [weak self] in
                Task { @MainActor [weak self] in self?.player.play() }
            },
            pause: { [weak self] in
                Task { @MainActor [weak self] in self?.player.pause() }
            },
            toggle: { [weak self] in
                Task { @MainActor [weak self] in self?.togglePlayPause() }
            },
            next: { [weak self] in
                Task { @MainActor [weak self] in self?.skipToNext() }
            },
            previous: { [weak self] in
                Task { @MainActor [weak self] in self?.skipToPrevious() }
            },
            seek: { [weak self] time in
                Task { @MainActor [weak self] in self?.seek(to: time) }
            }
        )

        // Drive the published currentTime + lock-screen progress.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let seconds = time.seconds
                if seconds.isFinite { self.currentTime = seconds }
                self.nowPlaying.updateProgress(
                    currentTime: seconds.isFinite ? seconds : 0,
                    rate: self.isPlaying ? 1 : 0
                )
            }
        }

        // Keep isPlaying in sync with the player's real state (covers buffering stalls).
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                self?.isPlaying = player.timeControlStatus == .playing
            }
        }
    }

    // MARK: - Public controls

    /// Plays `songs` starting at `index` (e.g. tapping a row in a playlist).
    func play(_ songs: [Song], startingAt index: Int, playlistId: String? = nil) {
        guard !songs.isEmpty, songs.indices.contains(index) else { return }
        queue = songs
        currentIndex = index
        currentPlaylistId = playlistId
        originalQueue = []
        originalIndex = nil
        streamRetryCount = [:]
        // The up-next panel belongs to the previous context; refresh it lazily.
        upNext = []
        upNextContinuation = nil
        lyricsEndpoint = nil
        relatedEndpoint = nil
        playCurrentItem()
    }

    // MARK: - Up-next queue (M6)

    /// Fetches the up-next panel for the current track from the `next` endpoint.
    /// The response also carries the lyrics/related tab endpoints used by the
    /// lyrics view. Best-effort: playback never depends on it.
    func fetchUpNext(force: Bool = false) async {
        guard let song = currentSong else { return }
        guard force || upNext.isEmpty else { return }
        guard !isFetchingUpNext else { return }
        isFetchingUpNext = true
        defer { isFetchingUpNext = false }
        do {
            let result = try await api.queue(
                videoId: song.watchEndpoint?.videoId ?? song.id,
                playlistId: song.watchEndpoint?.playlistId ?? currentPlaylistId,
                playlistSetVideoId: song.watchEndpoint?.playlistSetVideoId,
                index: song.watchEndpoint?.index,
                params: song.watchEndpoint?.params
            )
            upNext = result.songs
            upNextContinuation = result.continuation
            lyricsEndpoint = result.lyricsEndpoint ?? lyricsEndpoint
            relatedEndpoint = result.relatedEndpoint ?? relatedEndpoint
        } catch {
            // The panel is a convenience; ignore failures.
        }
    }

    /// Appends the next page of the up-next panel (pagination via continuation).
    func loadMoreUpNext() async {
        guard let token = upNextContinuation else { return }
        upNextContinuation = nil
        do {
            let result = try await api.queue(
                videoId: nil,
                playlistId: nil,
                playlistSetVideoId: nil,
                index: nil,
                params: nil,
                continuation: token
            )
            upNext.append(contentsOf: result.songs)
            upNextContinuation = result.continuation
            lyricsEndpoint = result.lyricsEndpoint ?? lyricsEndpoint
        } catch {
            // Stop paginating on failure; what we have is still playable.
        }
    }

    /// Plays an up-next song and continues with the rest of the panel as the queue.
    func playUpNext(at index: Int) {
        guard !upNext.isEmpty, upNext.indices.contains(index) else { return }
        play(upNext, startingAt: index, playlistId: currentPlaylistId)
    }

    func togglePlayPause() {
        if player.currentItem == nil {
            playCurrentItem()
            return
        }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
    }

    func seek(to time: TimeInterval) {
        guard time.isFinite, time >= 0 else { return }
        player.seek(
            to: CMTime(seconds: time, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func skipToNext() {
        guard let index = currentIndex, !queue.isEmpty else { return }
        if index + 1 < queue.count {
            currentIndex = index + 1
            playCurrentItem()
        } else if repeatMode == .all {
            currentIndex = 0
            playCurrentItem()
        } else {
            // Queue exhausted → try to fetch an automix batch from the `next` endpoint.
            Task { await autoplayNextBatch() }
        }
    }

    func skipToPrevious() {
        guard let index = currentIndex else { return }
        if index > 0 {
            currentIndex = index - 1
            playCurrentItem()
        } else {
            seek(to: 0) // restart the current track
        }
    }

    func toggleShuffle() {
        isShuffle.toggle()
        guard let current = currentSong else { return }

        if isShuffle {
            if originalQueue.isEmpty {
                originalQueue = queue
                originalIndex = currentIndex
            }
            let rest = originalQueue.enumerated()
                .filter { $0.offset != originalIndex }
                .map(\.element)
                .shuffled()
            queue = [current] + rest
            currentIndex = 0
        } else {
            if let originalIndex, originalQueue.indices.contains(originalIndex) {
                queue = originalQueue
                currentIndex = originalIndex
            }
            originalQueue = []
            originalIndex = nil
        }
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        queue = []
        currentIndex = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        upNext = []
        upNextContinuation = nil
        lyricsEndpoint = nil
        relatedEndpoint = nil
        nowPlaying.clear()
    }

    // MARK: - Playback internals

    private func playCurrentItem() {
        guard let song = currentSong else { return }
        isLoading = true
        errorMessage = nil

        // Offline: play the local file directly — no network round-trip needed.
        if let offline, let localURL = offline.localFileURL(for: song.id) {
            let item = AVPlayerItem(url: localURL)
            item.preferredForwardBufferDuration = 30
            replaceCurrentItem(item)
            if song.duration > 0 {
                duration = song.duration
            }
            nowPlaying.update(for: song, currentTime: 0, duration: duration)
            player.play()
            isLoading = false
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await api.player(
                    videoId: song.id,
                    playlistId: currentPlaylistId
                )

                guard let format = StreamURLResolver.bestAudioFormat(in: response) else {
                    throw PlaybackError.streamUnavailable
                }
                guard !StreamURLResolver.requiresDeciphering(format),
                      let url = URL(string: format.url ?? "") else {
                    throw PlaybackError.streamRequiresDeciphering
                }

                let item = makePlayerItem(url: url)
                replaceCurrentItem(item)

                if song.duration > 0 {
                    duration = song.duration
                } else if let lengthSeconds = response.videoDetails?.lengthSeconds,
                          let seconds = TimeInterval(lengthSeconds) {
                    duration = seconds
                }

                nowPlaying.update(for: song, currentTime: 0, duration: duration)
                player.play()
                registerPlaybackIfPossible(response)
            } catch let error as PlaybackError {
                errorMessage = error.errorDescription ?? error.localizedDescription
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    /// Builds an `AVPlayerItem` that sends the same user agent we used for the
    /// `player` request — googlevideo rejects some streams without it.
    private func makePlayerItem(url: URL) -> AVPlayerItem {
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetHTTPHeaderFieldsKey: [
                "User-Agent": InnertubeClientProfile.visionOS.userAgent
            ]
        ])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 30 // seconds of look-ahead buffering
        return item
    }

    private func replaceCurrentItem(_ item: AVPlayerItem) {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        if let failedPlaybackObserver {
            NotificationCenter.default.removeObserver(failedPlaybackObserver)
        }
        statusObservation?.invalidate()
        durationObservation?.invalidate()

        currentTime = 0

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.itemDidFinish()
            }
        }

        // Stream URLs expire (~6 h) and YouTube can cut them mid-playback with a 403.
        // Retry once per track with a freshly resolved URL (see handleItemFailure).
        failedPlaybackObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor [weak self] in
                self?.handleItemFailure(error)
            }
        }

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if item.status == .failed {
                    self.handleItemFailure(item.error)
                }
            }
        }

        durationObservation = item.observe(\.duration, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let seconds = item.duration.seconds
                if seconds.isFinite, seconds > 0 {
                    self.duration = seconds
                }
            }
        }

        player.replaceCurrentItem(with: item)
    }

    /// Stream URLs are only valid for `expiresInSeconds` (~6 h). If a track dies
    /// mid-playback (expired URL / 403), re-resolve a fresh stream once per song
    /// before surfacing the error.
    private func handleItemFailure(_ error: Error?) {
        guard let song = currentSong else { return }
        let attempts = streamRetryCount[song.id, default: 0]
        guard attempts < 1 else {
            errorMessage = error?.localizedDescription ?? "Playback failed."
            return
        }
        streamRetryCount[song.id] = attempts + 1
        playCurrentItem()
    }

    private func itemDidFinish() {
        switch repeatMode {
        case .one:
            seek(to: 0)
            player.play()
        case .all, .off:
            skipToNext()
        }
    }

    private func autoplayNextBatch() async {
        guard let song = currentSong else { return }
        do {
            let result = try await api.queue(
                videoId: song.watchEndpoint?.videoId ?? song.id,
                playlistId: song.watchEndpoint?.playlistId ?? currentPlaylistId,
                playlistSetVideoId: song.watchEndpoint?.playlistSetVideoId,
                index: song.watchEndpoint?.index,
                params: song.watchEndpoint?.params
            )
            guard !result.songs.isEmpty else { return }
            queue.append(contentsOf: result.songs)
            currentIndex = queue.count - result.songs.count
            // Keep the up-next panel + lyrics tab endpoint in sync with the new batch.
            upNext = result.songs
            upNextContinuation = result.continuation
            lyricsEndpoint = result.lyricsEndpoint ?? lyricsEndpoint
            playCurrentItem()
        } catch {
            // Nothing more to play — stop quietly.
            isPlaying = false
        }
    }

    private func registerPlaybackIfPossible(_ response: PlayerResponse) {
        guard let baseURL = response.playbackTracking?.videostatsPlaybackUrl?.baseUrl else { return }
        let playlistId = currentPlaylistId
        Task { [weak self] in
            try? await self?.api.registerPlayback(baseURL: baseURL, playlistId: playlistId)
        }
    }

    // MARK: - Interruption helpers

    private var wasPlayingBeforeInterruption = false

    private func pauseForInterruption() {
        wasPlayingBeforeInterruption = player.timeControlStatus == .playing
        player.pause()
    }

    private func resumeAfterInterruption() {
        guard wasPlayingBeforeInterruption else { return }
        player.play()
    }
}
