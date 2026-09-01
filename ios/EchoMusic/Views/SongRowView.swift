import SwiftUI
import UIKit

/// A single track row (search results, playlists, queue).
struct SongRowView: View {
    let song: Song
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ArtworkView(urlString: song.thumbnail, size: 48, cornerRadius: 6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(song.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if song.explicit {
                    Text("E")
                        .font(.caption2.bold())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(.secondary)
                }

                Text(TimeParser.string(song.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SongRowView(song: Song(
        id: "dQw4w9WgXcQ",
        title: "Never Gonna Give You Up",
        artists: [Artist(id: nil, name: "Rick Astley")],
        album: Album(id: nil, name: "Whenever You Need Somebody"),
        duration: 213,
        thumbnail: "",
        explicit: false,
        videoType: nil,
        watchEndpoint: nil
    )) {}
    .padding()
}
