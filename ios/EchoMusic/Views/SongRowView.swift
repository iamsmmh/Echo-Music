import SwiftUI
import UIKit

/// A single track row (search results, playlists, queue).
///
/// The tappable area is its own `Button`, and the favorite/download controls are
/// siblings outside it — nesting buttons inside a button's label would swallow
/// their taps in SwiftUI.
struct SongRowView: View {
    let song: Song
    var onTap: () -> Void
    /// When provided, shows a download button for the track.
    var offline: OfflineManager? = nil
    /// When `onToggleFavorite` is provided, shows a heart button in this state.
    var isFavorite: Bool = false
    var onToggleFavorite: ((Song) -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
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

            if let offline {
                DownloadButton(offline: offline, song: song)
                    .frame(width: 24, height: 24)
            }

            if let onToggleFavorite {
                FavoriteButton(isFavorite: isFavorite) {
                    onToggleFavorite(song)
                }
                .frame(width: 24, height: 24)
            }
        }
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
