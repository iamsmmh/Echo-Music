import Foundation

// MARK: - Domain models
// These are the "clean" models the UI consumes. The raw InnerTube renderer types
// (in `InnertubeModels.swift`) are mapped onto these by `MediaParser`.

struct Artist: Identifiable, Hashable {
    let id: String?
    let name: String

    var identifier: String { id ?? name }
}

struct Album: Identifiable, Hashable {
    let id: String?
    let name: String

    var identifier: String { id ?? name }
}

struct Song: Identifiable, Hashable {
    let id: String
    let title: String
    let artists: [Artist]
    let album: Album?
    let duration: TimeInterval
    let thumbnail: String
    let explicit: Bool
    let videoType: String?
    /// Queue context used by the `next` endpoint for automix / up-next.
    var watchEndpoint: WatchEndpoint?

    var artistNames: String { artists.map(\.name).joined(separator: ", ") }
    var subtitle: String { artistNames }
}

struct AlbumItem: Identifiable, Hashable {
    let browseId: String
    let playlistId: String?
    let title: String
    let subtitle: String?
    let thumbnail: String

    var id: String { browseId }
}

struct ArtistItem: Identifiable, Hashable {
    let browseId: String
    let title: String
    let subtitle: String?
    let thumbnail: String

    var id: String { browseId }
}

struct PlaylistItem: Identifiable, Hashable {
    let browseId: String
    let playlistId: String?
    let title: String
    let subtitle: String?
    let thumbnail: String

    var id: String { browseId }
}

/// A generic search/browse result item, mirroring the Android `YTItem` sealed class.
enum SearchItem: Identifiable, Hashable {
    case song(Song)
    case album(AlbumItem)
    case artist(ArtistItem)
    case playlist(PlaylistItem)

    var id: String {
        switch self {
        case .song(let song): "song-\(song.id)"
        case .album(let item): "album-\(item.browseId)"
        case .artist(let item): "artist-\(item.browseId)"
        case .playlist(let item): "playlist-\(item.browseId)"
        }
    }

    var title: String {
        switch self {
        case .song(let song): song.title
        case .album(let item): item.title
        case .artist(let item): item.title
        case .playlist(let item): item.title
        }
    }

    var subtitle: String {
        switch self {
        case .song(let song): song.subtitle
        case .album(let item): item.subtitle ?? ""
        case .artist(let item): item.subtitle ?? ""
        case .playlist(let item): item.subtitle ?? ""
        }
    }

    var thumbnail: String {
        switch self {
        case .song(let song): song.thumbnail
        case .album(let item): item.thumbnail
        case .artist(let item): item.thumbnail
        case .playlist(let item): item.thumbnail
        }
    }
}

/// One shelf of results on the search page (mirrors `MusicShelfRenderer`).
struct SearchSection: Identifiable, Hashable {
    let id: String
    let title: String
    let items: [SearchItem]
    let continuation: String?
}

/// A carousel on the home feed (mirrors `MusicCarouselShelfRenderer`).
struct HomeSection: Identifiable, Hashable {
    let id: String
    let title: String
    let items: [SearchItem]
}

/// A playlist or album page resolved from a `browse` call.
struct PlaylistDetail: Identifiable, Hashable {
    let browseId: String
    let playlistId: String?
    let title: String
    let subtitle: String?
    let thumbnail: String
    let songs: [Song]
    let continuation: String?

    var id: String { browseId }
}

/// The parsed `next` response: the up-next queue plus tab endpoints.
struct QueueResult: Hashable {
    let songs: [Song]
    let currentIndex: Int?
    let lyricsEndpoint: BrowseEndpoint?
    let relatedEndpoint: BrowseEndpoint?
    let title: String?
    let continuation: String?
    let automixEndpoint: WatchPlaylistEndpoint?
}
