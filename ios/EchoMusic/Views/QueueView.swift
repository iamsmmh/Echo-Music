import SwiftUI

/// Up-next queue panel (blueprint M6). Shows the tracks that follow the current
/// one from the `next` endpoint, lets you jump to any of them, and paginates
/// through the panel's continuation token.
struct QueueView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if env.player.upNext.isEmpty {
                    ContentUnavailableView(
                        "Queue is empty",
                        systemImage: "list.bullet",
                        description: Text("Play a track and the up-next queue builds itself from the playlist or an automix.")
                    )
                } else {
                    queueList
                }
            }
            .navigationTitle("Up Next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await env.player.fetchUpNext() }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - List

    private var queueList: some View {
        List {
            ForEach(Array(env.player.upNext.enumerated()), id: \.element.id) { index, song in
                row(song, at: index)
            }

            if env.player.upNextContinuation != nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .onAppear {
                        Task { await env.player.loadMoreUpNext() }
                    }
            }
        }
        .listStyle(.plain)
    }

    private func row(_ song: Song, at index: Int) -> some View {
        let isCurrent = song.id == env.player.currentSong?.id
        return Button {
            env.player.playUpNext(at: index)
        } label: {
            HStack(spacing: 12) {
                ArtworkView(urlString: song.thumbnail, size: 44, cornerRadius: 6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? Color.red : Color.primary)
                        .lineLimit(1)
                    Text(song.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(Color.red)
                } else {
                    Text(TimeParser.string(song.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    QueueView()
        .environmentObject(AppEnvironment.shared)
}
