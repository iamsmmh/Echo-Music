import Foundation

/// A single timestamped lyric line, as parsed from LRC format.
struct LyricLine: Identifiable, Hashable {
    let time: TimeInterval
    let text: String

    var id: TimeInterval { time }
}

/// Minimal LRC parser — enough for LRCLIB's `syncedLyrics`, which is standard LRC:
///
///     [00:12.34]First line
///     [00:15.00][00:45.00]Repeated line
///     [ti:Title]               ← metadata tags are ignored
///
/// Supports `mm:ss`, `mm:ss.xx` and `mm:ss:xx` timestamps, multiple timestamps per
/// line, and returns the lines sorted by time.
enum LrcParser {

    static func parse(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []

        for rawLine in lrc.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("[") else { continue }

            // Collect every leading [timestamp] tag, then treat the rest as text.
            var times: [TimeInterval] = []
            var rest = Substring(trimmed)
            while rest.hasPrefix("[") {
                guard let close = rest.firstIndex(of: "]") else { break }
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                rest = rest[rest.index(after: close)...]
                if let time = parseTime(String(tag)) {
                    times.append(time)
                }
            }

            let text = rest.trimmingCharacters(in: .whitespaces)
            guard !times.isEmpty, !text.isEmpty else { continue }
            for time in times {
                lines.append(LyricLine(time: time, text: text))
            }
        }

        return lines.sorted { $0.time < $1.time }
    }

    /// Parses `mm:ss`, `mm:ss.xx` or `mm:ss:xx` into seconds. Returns nil for
    /// non-timestamp tags like `ti:Title`.
    static func parseTime(_ tag: String) -> TimeInterval? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 2,
              let minutes = Double(parts[0]),
              let seconds = Double(parts[1]) else {
            return nil
        }
        var time = minutes * 60 + seconds
        if parts.count >= 3, let fraction = Double(parts[2]) {
            time += fraction / pow(10, Double(parts[2].count))
        }
        return time
    }
}
