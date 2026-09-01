import Foundation

/// Chooses the best playable audio format from a `player` response.
///
/// iOS-specific constraint: `AVPlayer` cannot decode Opus-in-WebM (itag 249/250/251),
/// so we always prefer AAC `audio/mp4` formats (itag 139/140/141). The Android app can
/// play Opus via ExoPlayer; on iOS that would require a third-party player.
enum StreamURLResolver {

    /// Preferred AAC itags, best first.
    static let aacItagPreference = [141, 140, 139]

    static func bestAudioFormat(in response: PlayerResponse) -> Format? {
        let audio = response.streamingData?.adaptiveFormats?.filter(\.isAudio) ?? []
        guard !audio.isEmpty else { return nil }

        // Prefer AAC-in-MP4; only fall back to other codecs if nothing AAC exists.
        let aac = audio.filter { $0.mimeType.contains("audio/mp4") }
        let pool = aac.isEmpty ? audio : aac

        return pool.sorted { lhs, rhs in
            let l = preference(lhs)
            let r = preference(rhs)
            if l != r { return l > r }
            return lhs.bitrate > rhs.bitrate
        }.first
    }

    /// True when the format has no direct `url` and would require signature / `n`-parameter
    /// deciphering (WEB_REMIX-style responses). Not implemented in the starter — we route
    /// playback through the VISIONOS / IOS / ANDROID_VR clients that return direct URLs.
    static func requiresDeciphering(_ format: Format) -> Bool {
        format.url == nil && (format.signatureCipher != nil || format.cipher != nil)
    }

    private static func preference(_ format: Format) -> Int {
        if let index = aacItagPreference.firstIndex(of: format.itag) {
            return 100 - index
        }
        return format.mimeType.contains("audio/mp4") ? 10 : 0
    }
}
