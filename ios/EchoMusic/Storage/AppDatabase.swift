import Foundation
import SwiftData

// MARK: - SwiftData models
// Local storage for favorites, user playlists, search history and offline tracks.
// (iOS 17+; swap for GRDB if you need heavier relational queries.)

@Model
final class FavoriteSong {
    @Attribute(.unique) var videoId: String
    var title: String
    var artistNames: String
    var albumName: String
    var thumbnailURL: String
    var duration: Double
    var addedAt: Date

    init(
        videoId: String,
        title: String,
        artistNames: String,
        albumName: String,
        thumbnailURL: String,
        duration: Double,
        addedAt: Date = .now
    ) {
        self.videoId = videoId
        self.title = title
        self.artistNames = artistNames
        self.albumName = albumName
        self.thumbnailURL = thumbnailURL
        self.duration = duration
        self.addedAt = addedAt
    }
}

@Model
final class UserPlaylist {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    /// Referential playlist contents (song IDs). Kept as plain IDs to avoid
    /// relationship-deletion surprises in SwiftData; resolve to `Song` via the network.
    var songIDs: [String]

    init(name: String, createdAt: Date = .now, songIDs: [String] = []) {
        self.id = UUID()
        self.name = name
        self.createdAt = createdAt
        self.songIDs = songIDs
    }
}

@Model
final class SearchHistoryEntry {
    var query: String
    var createdAt: Date

    init(query: String, createdAt: Date = .now) {
        self.query = query
        self.createdAt = createdAt
    }
}

@Model
final class OfflineTrack {
    @Attribute(.unique) var videoId: String
    var title: String
    var artistNames: String
    var thumbnailURL: String
    var duration: Double
    /// Absolute file URL inside the app's Documents/Offline directory.
    var localURL: String
    var completedAt: Date

    init(
        videoId: String,
        title: String,
        artistNames: String,
        thumbnailURL: String,
        duration: Double,
        localURL: String,
        completedAt: Date = .now
    ) {
        self.videoId = videoId
        self.title = title
        self.artistNames = artistNames
        self.thumbnailURL = thumbnailURL
        self.duration = duration
        self.localURL = localURL
        self.completedAt = completedAt
    }
}

// MARK: - Database

@MainActor
final class AppDatabase {

    let container: ModelContainer

    init() throws {
        let schema = Schema([
            FavoriteSong.self,
            UserPlaylist.self,
            SearchHistoryEntry.self,
            OfflineTrack.self
        ])
        container = try ModelContainer(for: schema)
    }

    // MARK: Favorites

    func favoriteSongs() throws -> [FavoriteSong] {
        let descriptor = FetchDescriptor<FavoriteSong>(
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        return try container.mainContext.fetch(descriptor)
    }

    func toggleFavorite(_ song: Song) throws {
        let context = container.mainContext
        let existing = try context.fetch(
            FetchDescriptor<FavoriteSong>(
                predicate: #Predicate { $0.videoId == song.id }
            )
        )
        if let record = existing.first {
            context.delete(record)
        } else {
            context.insert(FavoriteSong(
                videoId: song.id,
                title: song.title,
                artistNames: song.artistNames,
                albumName: song.album?.name ?? "",
                thumbnailURL: song.thumbnail,
                duration: song.duration
            ))
        }
        try context.save()
    }

    // MARK: Search history

    func recentSearches(limit: Int = 10) throws -> [String] {
        let descriptor = FetchDescriptor<SearchHistoryEntry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)],
            fetchLimit: limit
        )
        return try container.mainContext.fetch(descriptor).map(\.query)
    }

    func recordSearch(_ query: String) throws {
        let context = container.mainContext
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let existing = try context.fetch(
            FetchDescriptor<SearchHistoryEntry>(
                predicate: #Predicate { $0.query == trimmed }
            )
        )
        existing.forEach(context.delete)
        context.insert(SearchHistoryEntry(query: trimmed))
        try context.save()
    }

    // MARK: Offline tracks

    func offlineTracks() throws -> [OfflineTrack] {
        let descriptor = FetchDescriptor<OfflineTrack>(
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        return try container.mainContext.fetch(descriptor)
    }
}
