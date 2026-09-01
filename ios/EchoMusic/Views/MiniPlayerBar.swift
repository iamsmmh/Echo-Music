import SwiftUI

/// The compact bottom bar shown while a track is loaded.
/// Tap anywhere to open the full player.
struct MiniPlayerBar: View {
    @EnvironmentObject private var env: AppEnvironment
    var onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(urlString: env.player.currentSong?.thumbnail, size: 44, cornerRadius: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(env.player.currentSong?.title ?? "")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(env.player.currentSong?.artistNames ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                env.player.togglePlayPause()
            } label: {
                Image(systemName: env.player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            Button {
                env.player.skipToNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title3)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
