import Foundation

/// Maps raw InnerTube renderer JSON onto the clean domain models.
/// Every extraction path mirrors the Android repo's page mappers
/// (innertube/src/main/kotlin/com/music/innertube/pages/*.kt).
enum MediaParser {

    // MARK: - Thumbnail URLs

    /// Returns a thumbnail URL resized to the requested width using YouTube's
    /// `=wN-hN-l90-rj` suffix scheme.
    static func thumbnailURL(_ url: String, width: Int) -> String {
        let suffix = "=w\(width)-h\(width)-l90-rj"
        if let range = url.range(of: "=w[0-9]+-h[0-9]+", options: .regularExpression) {
            return String(url[..<range.lowerBound]) + suffix
        }
        return url + suffix
    }

    // MARK: - Search

    static func searchSections(from response: SearchResponse) -> [SearchSection] {
        let sectionList = response.contents?.tabbedSearchResultsRenderer?
            .tabs?.first?.tabRenderer?.content?.sectionListRenderer
        let contents = sectionList?.contents ?? []

        var sections: [SearchSection] = []
        for (index, content) in contents.enumerated() {
            guard let shelf = content.musicShelfRenderer else { continue }
            let items = (shelf.contents ?? []).compactMap { item in
                item.musicResponsiveListItemRenderer.flatMap(categorize)
            }
            guard !items.isEmpty else { continue }
            sections.append(SearchSection(
                id: "shelf-\(index)",
                title: shelf.title?.text ?? "Results",
                items: items,
                continuation: shelf.continuations?.firstContinuationToken
            ))
        }
        return sections
    }

    static func searchContinuation(from response: SearchResponse) -> (items: [SearchItem], continuation: String?) {
        let shelf = response.continuationContents?.musicShelfContinuation
        let items = (shelf?.contents ?? []).compactMap { item in
            item.musicResponsiveListItemRenderer.flatMap(categorize)
        }
        return (items, shelf?.continuations?.firstContinuationToken)
    }

    static func suggestions(from response: SuggestionsResponse) -> [String] {
        response.contents?.first?.searchSuggestionsSectionRenderer?.contents?
            .compactMap { $0.searchSuggestionRenderer?.suggestion?.text } ?? []
    }

    // MARK: - Home feed

    static func homeSections(from response: BrowseResponse) -> [HomeSection] {
        var sections: [HomeSection] = []
        for (index, content) in sectionContents(from: response).enumerated() {
            guard let carousel = content.musicCarouselShelfRenderer else { continue }
            let items = (carousel.contents ?? []).compactMap { content in
                if let twoRow = content.musicTwoRowItemRenderer {
                    return twoRowItem(from: twoRow)
                }
                if let listItem = content.musicResponsiveListItemRenderer {
                    return categorize(listItem)
                }
                return nil
            }
            guard !items.isEmpty else { continue }
            sections.append(HomeSection(
                id: "carousel-\(index)",
                title: carousel.header?.musicCarouselShelfBasicHeaderRenderer?.title?.text ?? "",
                items: items
            ))
        }
        return sections
    }

    // MARK: - Playlist / album pages

    static func playlistDetail(from response: BrowseResponse, browseId: String) -> PlaylistDetail? {
        let contents = sectionContents(from: response)
        let shelf = contents.compactMap(\.musicPlaylistShelfRenderer).first
        let header = response.header

        let title =
            header?.musicEditablePlaylistDetailHeaderRenderer?.header?.musicDetailHeaderRenderer?.title?.text
            ?? header?.musicEditablePlaylistDetailHeaderRenderer?.header?.musicResponsiveHeaderRenderer?.title?.text
            ?? header?.musicResponsiveHeaderRenderer?.title?.text
            ?? header?.musicDetailHeaderRenderer?.title?.text
            ?? header?.musicHeaderRenderer?.title?.text
            ?? contents.compactMap(\.musicResponsiveHeaderRenderer).first?.title?.text
            ?? ""

        let subtitle =
            header?.musicEditablePlaylistDetailHeaderRenderer?.header?.musicDetailHeaderRenderer?.subtitle?.text
            ?? header?.musicEditablePlaylistDetailHeaderRenderer?.header?.musicResponsiveHeaderRenderer?.subtitle?.text
            ?? header?.musicResponsiveHeaderRenderer?.subtitle?.text
            ?? header?.musicDetailHeaderRenderer?.subtitle?.text

        let thumbnail =
            header?.musicResponsiveHeaderRenderer?.thumbnail?.url
            ?? header?.musicDetailHeaderRenderer?.thumbnail?.url
            ?? header?.musicEditablePlaylistDetailHeaderRenderer?.header?.musicDetailHeaderRenderer?.thumbnail?.url
            ?? ""

        let playlistId = response.microformat?.microformatDataRenderer?.urlCanonical?
            .components(separatedBy: "=").last

        let songs = (shelf?.contents ?? []).compactMap { item in
            item.musicResponsiveListItemRenderer.flatMap(song)
        }

        guard !title.isEmpty || !songs.isEmpty else { return nil }

        return PlaylistDetail(
            browseId: browseId,
            playlistId: playlistId,
            title: title,
            subtitle: subtitle,
            thumbnail: thumbnail,
            songs: songs,
            continuation: shelf?.continuations?.firstContinuationToken
        )
    }

    static func playlistContinuation(from response: BrowseResponse) -> (songs: [Song], continuation: String?) {
        let shelf = response.continuationContents?.musicPlaylistShelfContinuation
        let songs = (shelf?.contents ?? []).compactMap { item in
            item.musicResponsiveListItemRenderer.flatMap(song)
        }
        return (songs, shelf?.continuations?.firstContinuationToken)
    }

    // MARK: - Lyrics (YouTube's own description-shelf lyrics)

    static func lyrics(from response: BrowseResponse) -> String? {
        sectionContents(from: response)
            .compactMap(\.musicDescriptionShelfRenderer)
            .first?.description?.text
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: - Queue (`next` response)

    static func queueResult(from response: NextResponse) -> QueueResult {
        let tabs = response.contents?.singleColumnMusicWatchNextResultsRenderer?
            .tabbedRenderer?.watchNextTabbedResultsRenderer?.tabs ?? []
        let firstTab = tabs.first
        let queueRenderer = firstTab?.tabRenderer?.content?.musicQueueRenderer

        let panelItems = queueRenderer?.content?.playlistPanelRenderer?.contents
            ?? response.continuationContents?.playlistPanelContinuation?.contents
            ?? []

        var songs: [Song] = []
        var currentIndex: Int?
        var automixEndpoint: WatchPlaylistEndpoint?

        for (index, item) in panelItems.enumerated() {
            if let renderer = item.playlistPanelVideoRenderer {
                if let song = song(from: renderer) {
                    songs.append(song)
                }
                if renderer.selected == true { currentIndex = index }
            }
            if let endpoint = item.automixPreviewVideoRenderer?.content?
                .automixPlaylistVideoRenderer?.navigationEndpoint?.watchPlaylistEndpoint {
                automixEndpoint = endpoint
            }
        }

        return QueueResult(
            songs: songs,
            currentIndex: currentIndex,
            lyricsEndpoint: tabs[safe: 1]?.tabRenderer?.endpoint?.browseEndpoint,
            relatedEndpoint: tabs[safe: 2]?.tabRenderer?.endpoint?.browseEndpoint,
            title: queueRenderer?.header?.musicQueueHeaderRenderer?.subtitle?.text,
            continuation: queueRenderer?.content?.playlistPanelRenderer?.continuations?.firstContinuationToken,
            automixEndpoint: automixEndpoint
        )
    }

    // MARK: - Item categorization
    // Mirrors SearchPage.toYTItem(): decide whether a list-item renderer is a song,
    // artist, album or playlist, then map it.

    static func categorize(_ renderer: MusicResponsiveListItemRenderer) -> SearchItem? {
        let isSong =
            renderer.overlay?.musicItemThumbnailOverlayRenderer?.content?.musicPlayButtonRenderer != nil
            || renderer.playlistItemData != nil
            || renderer.navigationEndpoint?.watchEndpoint != nil

        if isSong {
            guard let song = song(from: renderer) else { return nil }
            return .song(song)
        }

        guard let browseEndpoint = renderer.navigationEndpoint?.browseEndpoint else {
            return nil
        }

        let secondaryText = renderer.flexColumns?[safe: 1]?
            .musicResponsiveListItemFlexColumnRenderer?.text?.text ?? ""
        let thumbnail = renderer.thumbnail?.url ?? ""

        if secondaryText.contains("Artist") {
            return .artist(ArtistItem(
                browseId: browseEndpoint.browseId,
                title: renderer.flexColumns?.first?.musicResponsiveListItemFlexColumnRenderer?.text?.runs?.first?.text ?? "",
                subtitle: secondaryText,
                thumbnail: thumbnail
            ))
        }

        if secondaryText.contains("Album") || secondaryText.contains("Single") {
            return .album(AlbumItem(
                browseId: browseEndpoint.browseId,
                playlistId: playPlaylistId(from: renderer),
                title: renderer.flexColumns?.first?.musicResponsiveListItemFlexColumnRenderer?.text?.runs?.first?.text ?? "",
                subtitle: secondaryText,
                thumbnail: thumbnail
            ))
        }

        return .playlist(PlaylistItem(
            browseId: browseEndpoint.browseId,
            playlistId: playPlaylistId(from: renderer),
            title: renderer.flexColumns?.first?.musicResponsiveListItemFlexColumnRenderer?.text?.runs?.first?.text ?? "",
            subtitle: secondaryText,
            thumbnail: thumbnail
        ))
    }

    static func twoRowItem(from renderer: MusicTwoRowItemRenderer) -> SearchItem? {
        guard let title = renderer.title?.text else { return nil }
        let subtitle = renderer.subtitle?.text ?? ""
        let thumbnail = renderer.thumbnailRenderer?.url ?? ""

        if let watchEndpoint = renderer.navigationEndpoint?.watchEndpoint {
            return .song(Song(
                id: watchEndpoint.videoId,
                title: title,
                artists: parseArtists(subtitle),
                album: nil,
                duration: 0,
                thumbnail: thumbnail,
                explicit: false,
                videoType: nil,
                watchEndpoint: watchEndpoint
            ))
        }

        guard let browseEndpoint = renderer.navigationEndpoint?.browseEndpoint else { return nil }

        if subtitle.contains("Artist") {
            return .artist(ArtistItem(
                browseId: browseEndpoint.browseId,
                title: title,
                subtitle: subtitle,
                thumbnail: thumbnail
            ))
        }

        if subtitle.contains("Album") || subtitle.contains("Single") {
            return .album(AlbumItem(
                browseId: browseEndpoint.browseId,
                playlistId: playPlaylistId(from: renderer),
                title: title,
                subtitle: subtitle,
                thumbnail: thumbnail
            ))
        }

        return .playlist(PlaylistItem(
            browseId: browseEndpoint.browseId,
            playlistId: playPlaylistId(from: renderer),
            title: title,
            subtitle: subtitle,
            thumbnail: thumbnail
        ))
    }

    // MARK: - Song mapping (MusicResponsiveListItemRenderer)
    // Mirrors SearchPage.toYTItem()'s song branch exactly.

    static func song(from renderer: MusicResponsiveListItemRenderer) -> Song? {
        // Title
        guard let title = renderer.flexColumns?.first?
            .musicResponsiveListItemFlexColumnRenderer?.text?.runs?.first?.text else {
            return nil
        }

        // Secondary line: "Artist • Album • 3:45"
        guard let secondaryRuns = renderer.flexColumns?[safe: 1]?
            .musicResponsiveListItemFlexColumnRenderer?.text?.runs else {
            return nil
        }
        let segments = secondaryRuns.splitBySeparator()

        let artists = segments.first?.oddElements().map { run in
            Artist(
                id: run.navigationEndpoint?.browseEndpoint?.browseId,
                name: run.text
            )
        } ?? []

        let album = segments[safe: 1]?.first
            .flatMap { run in
                guard let browseId = run.navigationEndpoint?.browseEndpoint?.browseId else { return nil }
                return Album(id: browseId, name: run.text)
            }

        let duration = TimeParser.parse(segments.last?.first?.text) ?? 0

        // Video ID cascade — same order as the Android code:
        // playlistItemData → navigationEndpoint → overlay play button → flex column run.
        let videoId =
            renderer.playlistItemData?.videoId
            ?? renderer.navigationEndpoint?.watchEndpoint?.videoId
            ?? renderer.overlay?.musicItemThumbnailOverlayRenderer?.content?
                .musicPlayButtonRenderer?.playNavigationEndpoint?.watchEndpoint?.videoId
            ?? renderer.flexColumns?.first?.musicResponsiveListItemFlexColumnRenderer?
                .text?.runs?.first?.navigationEndpoint?.watchEndpoint?.videoId

        guard let videoId else { return nil }

        let explicit = renderer.badges?.contains {
            $0.musicInlineBadgeRenderer?.icon?.iconType == "MUSIC_EXPLICIT_BADGE"
        } ?? false

        return Song(
            id: videoId,
            title: title,
            artists: artists,
            album: album,
            duration: duration,
            thumbnail: renderer.thumbnail?.url ?? "",
            explicit: explicit,
            videoType: renderer.musicVideoType,
            watchEndpoint: renderer.navigationEndpoint?.watchEndpoint
        )
    }

    // MARK: - Song mapping (PlaylistPanelVideoRenderer — up-next queue)

    static func song(from renderer: PlaylistPanelVideoRenderer) -> Song? {
        let videoId = renderer.videoId ?? renderer.navigationEndpoint?.watchEndpoint?.videoId
        guard let videoId, let title = renderer.title?.text else { return nil }

        let segments = renderer.longBylineText?.runs?.splitBySeparator() ?? []
        let artists = segments.first?.oddElements().map { run in
            Artist(
                id: run.navigationEndpoint?.browseEndpoint?.browseId,
                name: run.text
            )
        } ?? []

        let album = segments[safe: 1]?.first.flatMap { run in
            guard let browseId = run.navigationEndpoint?.browseEndpoint?.browseId else { return nil }
            return Album(id: browseId, name: run.text)
        }

        return Song(
            id: videoId,
            title: title,
            artists: artists,
            album: album,
            duration: TimeParser.parse(renderer.lengthText?.text) ?? 0,
            thumbnail: renderer.thumbnail?.url ?? "",
            explicit: false,
            videoType: nil,
            watchEndpoint: renderer.navigationEndpoint?.watchEndpoint
        )
    }

    // MARK: - Helpers

    private static func sectionContents(from response: BrowseResponse) -> [BrowseResponse.Contents.SectionContent] {
        var contents: [BrowseResponse.Contents.SectionContent] = []
        if let tabs = response.contents?.singleColumnBrowseResultsRenderer?.tabs {
            for tab in tabs {
                if let tabContents = tab.tabRenderer?.content?.contents {
                    contents += tabContents
                }
            }
        }
        if let tabs = response.contents?.twoColumnBrowseResultsRenderer?.tabs {
            for tab in tabs {
                if let tabContents = tab.tabRenderer?.content?.contents {
                    contents += tabContents
                }
            }
        }
        return contents
    }

    private static func playPlaylistId(from renderer: MusicResponsiveListItemRenderer) -> String? {
        renderer.overlay?.musicItemThumbnailOverlayRenderer?.content?
            .musicPlayButtonRenderer?.playNavigationEndpoint?.watchPlaylistEndpoint?.playlistId
    }

    private static func playPlaylistId(from renderer: MusicTwoRowItemRenderer) -> String? {
        renderer.overlay?.musicItemThumbnailOverlayRenderer?.content?
            .musicPlayButtonRenderer?.playNavigationEndpoint?.watchPlaylistEndpoint?.playlistId
    }

    /// Parses a plain "Artist A • Artist B" string into artist models.
    static func parseArtists(_ string: String) -> [Artist] {
        string.split(separator: "•")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { Artist(id: nil, name: String($0)) }
    }
}
