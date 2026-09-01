import Foundation

// MARK: - Client profiles
// Values mirror the `YouTubeClient` table in the Android repo:
//   innertube/src/main/kotlin/com/music/innertube/models/YouTubeClient.kt

struct InnertubeClientProfile: Hashable {
    let name: String
    let version: String
    let clientID: String
    let userAgent: String
    let osName: String?
    let osVersion: String?
    let deviceMake: String?
    let deviceModel: String?

    init(
        name: String,
        version: String,
        clientID: String,
        userAgent: String,
        osName: String? = nil,
        osVersion: String? = nil,
        deviceMake: String? = nil,
        deviceModel: String? = nil
    ) {
        self.name = name
        self.version = version
        self.clientID = clientID
        self.userAgent = userAgent
        self.osName = osName
        self.osVersion = osVersion
        self.deviceMake = deviceMake
        self.deviceModel = deviceModel
    }

    /// The general client used for search / browse / queue (Android uses it everywhere).
    static let webRemix = InnertubeClientProfile(
        name: "WEB_REMIX",
        version: "1.20260213.01.00",
        clientID: "67",
        userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0"
    )

    /// Mints stream URLs that are directly playable — no signature or `n`-parameter
    /// transformation needed (the Android repo documents VISIONOS and ANDROID_VR 1.65.10
    /// as the only clients that do this). Prefer for audio playback.
    static let visionOS = InnertubeClientProfile(
        name: "VISIONOS",
        version: "0.1",
        clientID: "101",
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
        osName: "visionOS",
        osVersion: "1.3.21O771",
        deviceMake: "Apple",
        deviceModel: "RealityDevice14,1"
    )

    /// The actual iOS YouTube app client. A good playback fallback.
    static let ios = InnertubeClientProfile(
        name: "IOS",
        version: "21.03.1",
        clientID: "5",
        userAgent: "com.google.ios.youtube/21.03.1 (iPhone16,2; U; CPU iOS 18_2 like Mac OS X;)",
        osName: "iOS",
        osVersion: "18.2.22C152"
    )

    /// Quest client; also returns readable URLs. Useful backup for age-restricted content.
    static let androidVR16510 = InnertubeClientProfile(
        name: "ANDROID_VR",
        version: "1.65.10",
        clientID: "28",
        userAgent: "com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip",
        osName: "Android",
        osVersion: "12L",
        deviceMake: "Oculus",
        deviceModel: "Quest 3"
    )
}

// MARK: - Context & request bodies
// Shapes mirror the Android repo:
//   innertube/src/main/kotlin/com/music/innertube/models/Context.kt
//   innertube/src/main/kotlin/com/music/innertube/models/body/*.kt

struct InnerTubeContext: Codable {
    struct Client: Codable {
        var clientName: String
        var clientVersion: String
        var osName: String?
        var osVersion: String?
        var deviceMake: String?
        var deviceModel: String?
        var androidSdkVersion: String?
        var gl: String
        var hl: String
        var visitorData: String?
    }

    struct User: Codable {
        var lockedSafetyMode: Bool = false
        var onBehalfOfUser: String?
    }

    var client: Client
    var user: User = User()
}

struct SearchBody: Encodable {
    let context: InnerTubeContext
    let query: String?
    let params: String?
}

struct BrowseBody: Encodable {
    let context: InnerTubeContext
    let browseId: String?
    let params: String?
    let continuation: String?
}

struct PlayerBody: Encodable {
    struct PlaybackContext: Encodable {
        struct ContentPlaybackContext: Encodable {
            let signatureTimestamp: Int
        }
        let contentPlaybackContext: ContentPlaybackContext
    }

    let context: InnerTubeContext
    let videoId: String
    let playlistId: String?
    let playbackContext: PlaybackContext?
    let contentCheckOk: Bool
    let racyCheckOk: Bool
}

struct NextBody: Encodable {
    let context: InnerTubeContext
    let videoId: String?
    let playlistId: String?
    let playlistSetVideoId: String?
    let index: Int?
    let params: String?
    let continuation: String?
}

struct SuggestionsBody: Encodable {
    let context: InnerTubeContext
    let input: String
}

// MARK: - Response models
// InnerTube responses are big, deeply-nested renderer trees. The strategy (same as the
// Android code) is to model only the branches we read, with every renderer optional so
// that unknown shapes decode as `nil` instead of failing. `JSONDecoder` ignores unknown
// keys by default, so adding branches later is cheap.

struct Runs: Codable, Hashable {
    let runs: [Run]?

    var text: String { runs?.map(\.text).joined() ?? "" }
}

struct Run: Codable, Hashable {
    let text: String
    let navigationEndpoint: NavigationEndpoint?
}

struct NavigationEndpoint: Codable, Hashable {
    let browseEndpoint: BrowseEndpoint?
    let watchEndpoint: WatchEndpoint?
    let watchPlaylistEndpoint: WatchPlaylistEndpoint?
}

struct BrowseEndpoint: Codable, Hashable {
    let browseId: String
    let params: String?
}

struct WatchEndpoint: Codable, Hashable {
    let videoId: String
    let playlistId: String?
    let playlistSetVideoId: String?
    let index: Int?
    let params: String?
}

struct WatchPlaylistEndpoint: Codable, Hashable {
    let playlistId: String?
    let videoIds: [String]?
}

struct Continuation: Codable, Hashable {
    struct NextContinuationData: Codable, Hashable {
        let continuation: String
    }
    let nextContinuationData: NextContinuationData?
}

extension Array where Element == Continuation {
    var firstContinuationToken: String? {
        first?.nextContinuationData?.continuation
    }
}

struct Icon: Codable, Hashable {
    let iconType: String?
}

// MARK: - Shared renderer pieces

struct MusicThumbnailRenderer: Codable, Hashable {
    struct ThumbnailList: Codable, Hashable {
        struct ThumbnailItem: Codable, Hashable {
            let url: String
            let width: Int?
            let height: Int?
        }
        let thumbnails: [ThumbnailItem]?
    }

    let thumbnail: ThumbnailList?
    let croppedSquareThumbnailRenderer: ThumbnailList?

    var url: String? {
        croppedSquareThumbnailRenderer?.thumbnails?.last?.url
            ?? thumbnail?.thumbnails?.last?.url
    }
}

struct FlexColumn: Codable, Hashable {
    struct Renderer: Codable, Hashable {
        let text: Runs?
    }
    let musicResponsiveListItemFlexColumnRenderer: Renderer?
}

struct Overlay: Codable, Hashable {
    struct MusicItemThumbnailOverlayRenderer: Codable, Hashable {
        struct Content: Codable, Hashable {
            struct MusicPlayButtonRenderer: Codable, Hashable {
                let playNavigationEndpoint: NavigationEndpoint?
            }
            let musicPlayButtonRenderer: MusicPlayButtonRenderer?
        }
        let content: Content?
    }
    let musicItemThumbnailOverlayRenderer: MusicItemThumbnailOverlayRenderer?
}

struct Menu: Codable, Hashable {
    struct MenuRenderer: Codable, Hashable {
        struct Item: Codable, Hashable {
            struct MenuNavigationItemRenderer: Codable, Hashable {
                let icon: Icon?
                let navigationEndpoint: NavigationEndpoint?
            }
            let menuNavigationItemRenderer: MenuNavigationItemRenderer?
        }
        let items: [Item]?
    }
    let menuRenderer: MenuRenderer?
}

struct Badge: Codable, Hashable {
    struct MusicInlineBadgeRenderer: Codable, Hashable {
        let icon: Icon?
    }
    let musicInlineBadgeRenderer: MusicInlineBadgeRenderer?
}

// MARK: - List item renderer (search rows, playlist tracks)

struct MusicResponsiveListItemRenderer: Codable, Hashable {
    struct PlaylistItemData: Codable, Hashable {
        let videoId: String
    }

    let thumbnail: MusicThumbnailRenderer?
    let overlay: Overlay?
    let flexColumns: [FlexColumn]?
    let menu: Menu?
    let badges: [Badge]?
    let navigationEndpoint: NavigationEndpoint?
    let playlistItemData: PlaylistItemData?
    let musicVideoType: String?
}

struct MusicShelfItem: Codable, Hashable {
    let musicResponsiveListItemRenderer: MusicResponsiveListItemRenderer?
}

// MARK: - Two-row item renderer (home carousels: albums, artists, playlists)

struct MusicTwoRowItemRenderer: Codable, Hashable {
    let title: Runs?
    let subtitle: Runs?
    let thumbnailRenderer: MusicThumbnailRenderer?
    let navigationEndpoint: NavigationEndpoint?
    let overlay: Overlay?
    let menu: Menu?
}

// MARK: - Shelves

struct MusicShelfRenderer: Codable, Hashable {
    let title: Runs?
    let contents: [MusicShelfItem]?
    let continuations: [Continuation]?
}

struct MusicCarouselShelfRenderer: Codable, Hashable {
    struct Header: Codable, Hashable {
        struct BasicHeader: Codable, Hashable {
            let title: Runs?
        }
        let musicCarouselShelfBasicHeaderRenderer: BasicHeader?
    }
    struct Content: Codable, Hashable {
        let musicTwoRowItemRenderer: MusicTwoRowItemRenderer?
        let musicResponsiveListItemRenderer: MusicResponsiveListItemRenderer?
    }
    let header: Header?
    let contents: [Content]?
}

struct MusicPlaylistShelfRenderer: Codable, Hashable {
    let contents: [MusicShelfItem]?
    let continuations: [Continuation]?
}

struct MusicDescriptionShelfRenderer: Codable, Hashable {
    let description: Runs?
}

// MARK: - Search response

struct SearchResponse: Decodable {
    struct Contents: Decodable {
        struct TabbedSearchResultsRenderer: Decodable {
            let tabs: [Tab]?
        }
        struct Tab: Decodable {
            struct TabRenderer: Decodable {
                let content: TabContent?
            }
            let tabRenderer: TabRenderer?
        }
        struct TabContent: Decodable {
            let sectionListRenderer: SectionListRenderer?
        }
        struct SectionListRenderer: Decodable {
            let contents: [SectionContent]?
        }
        struct SectionContent: Decodable {
            let musicShelfRenderer: MusicShelfRenderer?
            let musicCarouselShelfRenderer: MusicCarouselShelfRenderer?
        }
        let tabbedSearchResultsRenderer: TabbedSearchResultsRenderer?
    }

    struct ContinuationContents: Decodable {
        struct MusicShelfContinuation: Decodable {
            let contents: [MusicShelfItem]?
            let continuations: [Continuation]?
        }
        let musicShelfContinuation: MusicShelfContinuation?
    }

    let contents: Contents?
    let continuationContents: ContinuationContents?
}

// MARK: - Browse response (home / playlists / albums / lyrics)

struct BrowseResponse: Decodable {
    struct Contents: Decodable {
        struct SingleColumn: Decodable {
            let tabs: [Tab]?
        }
        struct TwoColumn: Decodable {
            let tabs: [Tab]?
        }
        struct Tab: Decodable {
            struct TabRenderer: Decodable {
                let content: SectionList?
            }
            let tabRenderer: TabRenderer?
        }
        struct SectionList: Decodable {
            let contents: [SectionContent]?
        }
        struct SectionContent: Decodable {
            let musicPlaylistShelfRenderer: MusicPlaylistShelfRenderer?
            let musicShelfRenderer: MusicShelfRenderer?
            let musicCarouselShelfRenderer: MusicCarouselShelfRenderer?
            let musicDescriptionShelfRenderer: MusicDescriptionShelfRenderer?
            let musicResponsiveHeaderRenderer: Header.MusicResponsiveHeaderRenderer?
        }
        let singleColumnBrowseResultsRenderer: SingleColumn?
        let twoColumnBrowseResultsRenderer: TwoColumn?
    }

    struct Header: Decodable {
        struct MusicResponsiveHeaderRenderer: Decodable {
            let title: Runs?
            let subtitle: Runs?
            let thumbnail: MusicThumbnailRenderer?
        }
        struct MusicDetailHeaderRenderer: Decodable {
            let title: Runs?
            let subtitle: Runs?
            let thumbnail: MusicThumbnailRenderer?
        }
        struct MusicEditablePlaylistDetailHeaderRenderer: Decodable {
            struct Header: Decodable {
                let musicDetailHeaderRenderer: MusicDetailHeaderRenderer?
                let musicResponsiveHeaderRenderer: MusicResponsiveHeaderRenderer?
            }
            let header: Header?
        }
        struct MusicHeaderRenderer: Decodable {
            let title: Runs?
        }
        let musicResponsiveHeaderRenderer: MusicResponsiveHeaderRenderer?
        let musicDetailHeaderRenderer: MusicDetailHeaderRenderer?
        let musicEditablePlaylistDetailHeaderRenderer: MusicEditablePlaylistDetailHeaderRenderer?
        let musicHeaderRenderer: MusicHeaderRenderer?
    }

    struct Microformat: Decodable {
        struct DataRenderer: Decodable {
            let urlCanonical: String?
        }
        let microformatDataRenderer: DataRenderer?
    }

    struct ContinuationContents: Decodable {
        struct MusicPlaylistShelfContinuation: Decodable {
            let contents: [MusicShelfItem]?
            let continuations: [Continuation]?
        }
        let musicPlaylistShelfContinuation: MusicPlaylistShelfContinuation?
    }

    let contents: Contents?
    let header: Header?
    let microformat: Microformat?
    let continuationContents: ContinuationContents?
}

// MARK: - Player response

struct PlayerResponse: Decodable {
    struct PlayabilityStatus: Decodable {
        let status: String
        let reason: String?
    }

    struct VideoDetails: Decodable {
        struct Thumb: Decodable {
            let url: String
            let width: Int?
            let height: Int?
        }
        let videoId: String
        let title: String
        let author: String
        let lengthSeconds: String
        let thumbnails: [Thumb]?
    }

    struct StreamingData: Decodable {
        let formats: [Format]?
        let adaptiveFormats: [Format]?
        let expiresInSeconds: Int
    }

    struct PlaybackTracking: Decodable {
        struct PlaybackUrl: Decodable {
            let baseUrl: String?
        }
        let videostatsPlaybackUrl: PlaybackUrl?
    }

    let playabilityStatus: PlayabilityStatus
    let streamingData: StreamingData?
    let videoDetails: VideoDetails?
    let playbackTracking: PlaybackTracking?

    var isPlayable: Bool { playabilityStatus.status == "OK" }
}

struct Format: Decodable, Hashable {
    let itag: Int
    let url: String?
    let mimeType: String
    let bitrate: Int
    let width: Int?
    let height: Int?
    let contentLength: Int64?
    let quality: String?
    let audioQuality: String?
    let approxDurationMs: String?
    let audioSampleRate: Int?
    let audioChannels: Int?
    let signatureCipher: String?
    let cipher: String?

    /// Audio-only formats have no width/height (they live in `adaptiveFormats`).
    var isAudio: Bool { width == nil }

    enum CodingKeys: String, CodingKey {
        case itag, url, mimeType, bitrate, width, height, contentLength
        case quality, audioQuality, approxDurationMs, audioSampleRate, audioChannels
        case signatureCipher, cipher
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        itag = try c.decode(Int.self, forKey: .itag)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType) ?? ""
        bitrate = try c.decodeIfPresent(Int.self, forKey: .bitrate) ?? 0
        width = try c.decodeIfPresent(Int.self, forKey: .width)
        height = try c.decodeIfPresent(Int.self, forKey: .height)
        // YouTube occasionally serializes contentLength as a string.
        if let intValue = try? c.decodeIfPresent(Int64.self, forKey: .contentLength) {
            contentLength = intValue
        } else if let stringValue = try? c.decodeIfPresent(String.self, forKey: .contentLength) {
            contentLength = Int64(stringValue)
        } else {
            contentLength = nil
        }
        quality = try c.decodeIfPresent(String.self, forKey: .quality)
        audioQuality = try c.decodeIfPresent(String.self, forKey: .audioQuality)
        approxDurationMs = try c.decodeIfPresent(String.self, forKey: .approxDurationMs)
        audioSampleRate = try c.decodeIfPresent(Int.self, forKey: .audioSampleRate)
        audioChannels = try c.decodeIfPresent(Int.self, forKey: .audioChannels)
        signatureCipher = try c.decodeIfPresent(String.self, forKey: .signatureCipher)
        cipher = try c.decodeIfPresent(String.self, forKey: .cipher)
    }
}

// MARK: - Next response (up-next queue + tab endpoints)

struct NextResponse: Decodable {
    struct Contents: Decodable {
        struct WatchNext: Decodable {
            struct Tabbed: Decodable {
                struct WatchNextTabbedResults: Decodable {
                    struct Tab: Decodable {
                        struct TabRenderer: Decodable {
                            struct Content: Decodable {
                                struct MusicQueueRenderer: Decodable {
                                    struct QueueContent: Decodable {
                                        struct PlaylistPanelRenderer: Decodable {
                                            struct QueueItem: Decodable {
                                                let playlistPanelVideoRenderer: PlaylistPanelVideoRenderer?
                                                let automixPreviewVideoRenderer: AutomixPreviewVideoRenderer?
                                            }
                                            struct AutomixPreviewVideoRenderer: Decodable {
                                                struct Content: Decodable {
                                                    struct AutomixPlaylistVideoRenderer: Decodable {
                                                        let navigationEndpoint: NavigationEndpoint?
                                                    }
                                                    let automixPlaylistVideoRenderer: AutomixPlaylistVideoRenderer?
                                                }
                                                let content: Content?
                                            }
                                            let contents: [QueueItem]?
                                            let continuations: [Continuation]?
                                        }
                                        let playlistPanelRenderer: PlaylistPanelRenderer?
                                    }
                                    struct QueueHeader: Decodable {
                                        struct QueueHeaderRenderer: Decodable {
                                            let subtitle: Runs?
                                        }
                                        let musicQueueHeaderRenderer: QueueHeaderRenderer?
                                    }
                                    let content: QueueContent?
                                    let header: QueueHeader?
                                }
                                let musicQueueRenderer: MusicQueueRenderer?
                            }
                            let content: Content?
                            let endpoint: NavigationEndpoint?
                        }
                        let tabRenderer: TabRenderer?
                    }
                    let tabs: [Tab]?
                }
                let watchNextTabbedResultsRenderer: WatchNextTabbedResults?
            }
            let tabbedRenderer: Tabbed?
        }
        let singleColumnMusicWatchNextResultsRenderer: WatchNext?
    }

    struct ContinuationContents: Decodable {
        struct PlaylistPanelContinuation: Decodable {
            let contents: [Contents.WatchNext.Tabbed.WatchNextTabbedResults.Tab.TabRenderer.Content.MusicQueueRenderer.QueueContent.PlaylistPanelRenderer.QueueItem]?
            let continuations: [Continuation]?
        }
        let playlistPanelContinuation: PlaylistPanelContinuation?
    }

    let contents: Contents?
    let continuationContents: ContinuationContents?
}

struct PlaylistPanelVideoRenderer: Codable, Hashable {
    let videoId: String?
    let title: Runs?
    let longBylineText: Runs?
    let thumbnail: MusicThumbnailRenderer?
    let lengthText: Runs?
    let navigationEndpoint: NavigationEndpoint?
    let playlistSetVideoId: String?
    let selected: Bool?
}

// MARK: - Search suggestions

struct SuggestionsResponse: Decodable {
    struct Section: Decodable {
        struct SectionRenderer: Decodable {
            struct Item: Decodable {
                struct SuggestionRenderer: Decodable {
                    let suggestion: Runs?
                }
                let searchSuggestionRenderer: SuggestionRenderer?
            }
            let contents: [Item]?
        }
        let searchSuggestionsSectionRenderer: SectionRenderer?
    }
    let contents: [Section]?
}
