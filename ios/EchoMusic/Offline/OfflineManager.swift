import Foundation

/// Manages offline downloads (blueprint milestone M9):
///
///  1. Resolves a playable audio stream for a `Song` via the `player` endpoint
///     (same direct-URL clients as playback: VISIONOS → IOS → ANDROID_VR).
///  2. Streams it to `Documents/Offline/<videoId>.m4a` with `URLSessionDownloadTask`
///     (AAC `audio/mp4` only — the only thing AVPlayer can reliably decode).
///  3. Records an `OfflineTrack` in SwiftData so `PlaybackManager` can serve the
///     local file instead of the network.
///
/// Progress is exposed as `@Published` state so a `DownloadButton` can render a
/// ring while a download is in flight. Cancelled downloads keep their resume data,
/// so re-tapping the button resumes instead of starting over.
@MainActor
final class OfflineManager: NSObject, ObservableObject {

    /// Where completed downloads live. Kept outside the app sandbox's caches so
    /// files survive launches (and airplane-mode playback works).
    static let offlineDirectory: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Offline", isDirectory: true)
    }()

    // MARK: Published state (what the UI binds to)

    @Published private(set) var downloadedIDs: Set<String> = []
    @Published private(set) var activeDownloadIDs: Set<String> = []
    @Published private(set) var progressByID: [String: Double] = [:]

    // MARK: Private

    private let api: InnertubeAPI
    private let database: AppDatabase

    private lazy var session: URLSession = URLSession(
        configuration: .default,
        delegate: self,
        delegateQueue: .main
    )

    private var tasksByID: [String: URLSessionDownloadTask] = [:]
    private var songsByID: [String: Song] = [:]
    private var resumeDataByID: [String: Data] = [:]

    init(api: InnertubeAPI, database: AppDatabase) {
        self.api = api
        self.database = database
        super.init()
        downloadedIDs = Set((try? database.offlineTracks())?.map(\.videoId) ?? [])
    }

    // MARK: - Queries

    func isDownloaded(_ videoId: String) -> Bool {
        downloadedIDs.contains(videoId)
    }

    /// The on-disk URL of a completed download, if the file still exists.
    func localFileURL(for videoId: String) -> URL? {
        let url = Self.offlineDirectory.appendingPathComponent("\(videoId).m4a")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Download control

    func download(_ song: Song) async {
        guard !isDownloaded(song.id), !activeDownloadIDs.contains(song.id) else { return }

        // Resume an interrupted download from where it stopped.
        if let resumeData = resumeDataByID[song.id] {
            start(task: session.downloadTask(withResumeData: resumeData), for: song)
            return
        }

        do {
            let response = try await api.player(videoId: song.id, playlistId: nil)
            guard let format = StreamURLResolver.bestAudioFormat(in: response),
                  !StreamURLResolver.requiresDeciphering(format),
                  let url = URL(string: format.url ?? "") else {
                return
            }

            // Same user agent as the `player` request — googlevideo rejects some
            // streams without it (see PlaybackManager.makePlayerItem).
            var request = URLRequest(url: url)
            request.setValue(InnertubeClientProfile.visionOS.userAgent, forHTTPHeaderField: "User-Agent")
            start(task: session.downloadTask(with: request), for: song)
        } catch {
            // Best-effort: a failed download simply never lands in `downloadedIDs`.
        }
    }

    func cancel(_ videoId: String) {
        guard let task = tasksByID[videoId] else { return }
        task.cancel { [weak self] resumeData in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let resumeData {
                    self.resumeDataByID[videoId] = resumeData
                }
                self.tasksByID[videoId] = nil
                self.songsByID[videoId] = nil
                self.activeDownloadIDs.remove(videoId)
                self.progressByID[videoId] = nil
            }
        }
    }

    /// Removes a completed download: file + SwiftData record.
    func delete(_ track: OfflineTrack) {
        try? FileManager.default.removeItem(atPath: track.localURL)
        try? database.delete(track)
        downloadedIDs.remove(track.videoId)
    }

    // MARK: - Internals

    private func start(task: URLSessionDownloadTask, for song: Song) {
        task.taskDescription = song.id
        tasksByID[song.id] = task
        songsByID[song.id] = song
        activeDownloadIDs.insert(song.id)
        progressByID[song.id] = 0
        task.resume()
    }

    private func finish(_ downloadTask: URLSessionDownloadTask, at location: URL) {
        guard let id = downloadTask.taskDescription,
              let song = songsByID[id] else { return }

        do {
            try FileManager.default.createDirectory(
                at: Self.offlineDirectory,
                withIntermediateDirectories: true
            )
            let destination = Self.offlineDirectory.appendingPathComponent("\(id).m4a")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)

            try database.insert(OfflineTrack(
                videoId: id,
                title: song.title,
                artistNames: song.artistNames,
                thumbnailURL: song.thumbnail,
                duration: song.duration,
                localURL: destination.path
            ))

            downloadedIDs.insert(id)
            cleanup(id)
        } catch {
            cleanup(id)
        }
    }

    private func cleanup(_ id: String) {
        tasksByID[id] = nil
        songsByID[id] = nil
        activeDownloadIDs.remove(id)
        progressByID[id] = nil
    }
}

// MARK: - URLSessionDownloadDelegate

extension OfflineManager: URLSessionDownloadDelegate {

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        finish(downloadTask, at: location)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let id = downloadTask.taskDescription, totalBytesExpectedToWrite > 0 else { return }
        progressByID[id] = min(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 1)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription, let nsError = error as NSError? else { return }
        // Keep resume data on cancellation / transport failure so the user can
        // resume instead of re-downloading from zero.
        if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            resumeDataByID[id] = resumeData
        }
        cleanup(id)
    }
}
