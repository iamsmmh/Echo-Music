import SwiftUI
import UIKit

/// Navigation destination values (used with `navigationDestination(for:)`).
struct PlaylistDestination: Hashable {
    let browseId: String
}

// MARK: - Artwork

struct ArtworkView: View {
    let urlString: String?
    var size: CGFloat = 56
    var cornerRadius: CGFloat = 8

    var body: some View {
        let resolved = urlString.map { MediaParser.thumbnailURL($0, width: Int(size * 3)) }
        AsyncImage(url: resolved.flatMap(URL.init(string:))) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                placeholder
            default:
                placeholder
                    .overlay(ProgressView())
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(Color(.secondarySystemBackground))
            Image(systemName: "music.note")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Player screen background

struct BlurredArtworkBackground: View {
    let urlString: String?

    var body: some View {
        GeometryReader { proxy in
            AsyncImage(url: urlString.flatMap {
                URL(string: MediaParser.thumbnailURL($0, width: 1600))
            }) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .blur(radius: 60)
                        .overlay(Color.black.opacity(0.55))
                } else {
                    Color.black
                }
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Generic result row

struct SearchResultRow: View {
    let title: String
    let subtitle: String?
    let thumbnail: String

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(urlString: thumbnail, size: 48, cornerRadius: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Design tokens

enum AppTheme {
    /// YouTube Music accent red.
    static let accent = Color.red
}
