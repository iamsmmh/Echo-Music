import SwiftUI

/// Lyrics sheet (blueprint M10). Prefers synced LRC from LRCLIB, falls back to
/// YouTube's static lyrics. While synced lyrics are available, the current line is
/// highlighted and auto-scrolled to the center as playback progresses.
struct LyricsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = LyricsViewModel(api: AppEnvironment.shared.api)

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Lyrics")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
                .task(id: env.player.currentSong?.id) {
                    // The lyrics tab endpoint lives in the `next` response, so make
                    // sure the up-next panel (and its endpoints) are loaded first.
                    await env.player.fetchUpNext()
                    await viewModel.load(
                        song: env.player.currentSong,
                        endpoint: env.player.lyricsEndpoint
                    )
                }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !viewModel.lines.isEmpty {
            syncedLyrics
        } else if let staticLyrics = viewModel.staticLyrics, !staticLyrics.isEmpty {
            staticScroll(staticLyrics)
        } else {
            ContentUnavailableView(
                "No lyrics found",
                systemImage: "text.quote",
                description: Text(viewModel.errorMessage ?? "Try a different track.")
            )
        }
    }

    // MARK: - Synced lyrics

    private var syncedLyrics: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(viewModel.lines) { line in
                        Text(line.text)
                            .font(.title3)
                            .fontWeight(line.time == currentLineID ? .bold : .regular)
                            .foregroundStyle(line.time == currentLineID ? Color.red : Color.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .id(line.time)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 180) // breathing room so the active line can sit centered
            }
            .onChange(of: currentLineID) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    /// The timestamp of the line currently being sung (last line with time <= playback).
    private var currentLineID: TimeInterval? {
        let time = env.player.currentTime
        return viewModel.lines.last(where: { $0.time <= time })?.time
    }

    // MARK: - Static lyrics

    private func staticScroll(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
                .textSelection(.enabled)
        }
    }
}

#Preview {
    LyricsView()
        .environmentObject(AppEnvironment.shared)
}
