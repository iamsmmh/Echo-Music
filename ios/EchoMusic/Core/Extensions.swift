import Foundation

// MARK: - Collection safety

extension Collection {
    /// Safe subscript that returns `nil` instead of trapping for out-of-range access.
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - InnerTube text-run helpers
// These mirror the Kotlin helpers in the Android repo:
//   innertube/src/main/kotlin/com/music/innertube/models/Runs.kt

extension Array where Element == Run {
    /// Splits a run array on the literal " • " separator runs YouTube uses in bylines.
    /// Example: ["Artist A", " • ", "Artist B", " • ", "Album", " • ", "3:45"]
    func splitBySeparator() -> [[Run]] {
        var result: [[Run]] = []
        var bucket: [Run] = []
        for run in self {
            if run.text == " • " {
                result.append(bucket)
                bucket = []
            } else {
                bucket.append(run)
            }
        }
        result.append(bucket)
        return result
    }

    /// YouTube places the separator runs at odd indices, so the meaningful values
    /// (artist names, etc.) live at even indices.
    func oddElements() -> [Run] {
        enumerated().compactMap { $0.offset.isMultiple(of: 2) ? $0.element : nil }
    }
}

// MARK: - Timestamp parsing

enum TimeParser {
    /// Parses "3:45", "1:02:03" style timestamps into seconds.
    static func parse(_ string: String?) -> TimeInterval? {
        guard let string, !string.isEmpty else { return nil }
        let parts = string.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    /// Formats a duration as "m:ss" or "h:mm:ss".
    static func string(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
