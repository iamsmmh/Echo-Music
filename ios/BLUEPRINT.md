# Echo Music for iOS — Blueprint & Starter Architecture

> A native iOS client for YouTube Music, built with **Swift + SwiftUI**. Clean, ad-free,
> background-audio streaming client in the spirit of the Echo Music Android app.
>
> Every API detail in this document was **verified against the Echo Music Android
> codebase** in this repository (`innertube/` and `app/` modules) — the request bodies,
> headers, client IDs, and response JSON paths below are the ones the Android app
> actually uses in production. The Swift starter code in `ios/EchoMusic/` mirrors them
> 1:1 so you can start from a proven baseline instead of reverse-engineering from scratch.

---

## Table of contents

1. [Overview, goals & key decisions](#1-overview-goals--key-decisions)
2. [Phase 1 — Project structure & architecture (MVVM)](#phase-1--project-structure--architecture-mvvm)
3. [Phase 2 — The networking & API layer](#phase-2--the-networking--api-layer)
4. [Phase 3 — Audio playback & background audio](#phase-3--audio-playback--background-audio)
5. [Phase 4 — Core UI layout](#phase-4--core-ui-layout)
6. [Phase 5 — Step-by-step build plan](#phase-5--step-by-step-build-plan)
7. [Appendix A — Reference card](#appendix-a--reference-card)
8. [Appendix B — Glossary](#appendix-b--glossary)

---

## 1. Overview, goals & key decisions

### 1.1 Goals

| Goal | How |
|---|---|
| Stream any YouTube Music track, ad-free | InnerTube `player` endpoint → audio stream URL → `AVPlayer` |
| Search, playlists, albums, home feed | InnerTube `search` / `browse` / `next` endpoints |
| Background audio + lock screen controls | `AVAudioSession`, `UIBackgroundModes: audio`, `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter` |
| Favorites, history, user playlists | SwiftData (iOS 17+) |
| Offline playback (later milestone) | Download stream to `Documents/Offline` via `URLSessionDownloadTask` |
| Synced lyrics (later milestone) | LRCLIB API (same source the Android app's `lrclib` module uses) |

### 1.2 Non-goals (v1)

- Sign-in / personal library sync (cookies, likes) — designed for, stubbed for later.
- Signature deciphering (`s` / `n` parameters) — avoided by using stream clients that
  return direct URLs (see §3.6). The fallback is documented but not implemented.
- Video playback, casting, Chromecast, AirPlay **audio** is free via iOS.
- App Store distribution (see legal note in `README.md`).

### 1.3 Tech stack & key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Language / UI | Swift 5.9, SwiftUI, iOS 17+ | Native, modern, minimal boilerplate |
| Networking | `URLSession` + `Codable` | No third-party deps; mirrors Android's Ktor setup |
| Audio | `AVPlayer` (single instance) | Full control over queue, headers, error handling; `AVQueuePlayer` is an alternative for a simpler-but-less-flexible queue |
| Persistence | SwiftData | Built-in, type-safe; enough for favorites/history/offline metadata |
| DI | A single `AppEnvironment` container | Small app; avoids a DI framework |
| State management | `ObservableObject` + `@MainActor` | Predictable, compile-checked main-thread publishing |
| Project generation | XcodeGen (`project.yml`) | Text-friendly, diffable; plain Xcode works too |

### 1.4 The single most important discovery

The Android repo comments state it plainly: **VISIONOS and ANDROID_VR 1.65.10 are the
only InnerTube clients that currently mint fully readable stream URLs** — no signature
deobfuscation, no `n`-parameter transform, no PoToken:

> `VISIONOS` … "the only clients that currently mint a fully readable stream URL — without
> one they answer UNPLAYABLE / LOGIN_REQUIRED with zero formats"
> — `innertube/.../models/YouTubeClient.kt`

This is huge for an iOS client, because implementing YouTube's JS deciphering algorithm
is the hardest and most fragile part of any YT client. **The iOS app routes playback
through `VISIONOS` (→ `IOS` → `ANDROID_VR` fallbacks) and gets playable URLs directly.**
The `player` request still needs a `visitorData`, but nothing else.

---

## Phase 1 — Project structure & architecture (MVVM)

### 1.1 Folder layout

```
ios/
├── BLUEPRINT.md                  ← this document
├── README.md                     ← quick start
├── project.yml                   ← XcodeGen manifest
└── EchoMusic/
    ├── App/
    │   ├── EchoMusicApp.swift    ← @main, wires environment + SwiftData container
    │   ├── AppEnvironment.swift  ← DI container (client, api, player, database)
    │   └── Info.plist            ← UIBackgroundModes: audio
    ├── Core/
    │   └── Extensions.swift      ← safe subscripts, run-array helpers, TimeParser
    ├── Networking/
    │   ├── Innertube/
    │   │   ├── InnertubeClient.swift   ← URLSession transport + headers + retry
    │   │   ├── InnertubeAPI.swift      ← typed endpoints (search/browse/player/next)
    │   │   ├── InnertubeModels.swift   ← Codable request/response models
    │   │   ├── MediaParser.swift       ← renderer JSON → domain models
    │   │   └── StreamURLResolver.swift ← format selection (AAC only on iOS)
    │   ├── LrcLibClient.swift          ← synced lyrics (LRCLIB)
    │   └── Models/
    │       └── AppModels.swift         ← Song, Album, Artist, SearchItem, ...
    ├── Playback/
    │   ├── PlaybackManager.swift       ← queue + AVPlayer + now-playing state
    │   ├── AudioSessionManager.swift   ← AVAudioSession + interruptions/routes
    │   └── NowPlayingManager.swift     ← lock screen info + remote commands
    ├── Storage/
    │   └── AppDatabase.swift           ← SwiftData models + queries
    ├── ViewModels/
    │   ├── SearchViewModel.swift
    │   ├── HomeViewModel.swift
    │   └── PlaylistViewModel.swift
    └── Views/
        ├── RootView.swift              ← TabView + mini player + player cover
        ├── MiniPlayerBar.swift
        ├── PlayerScreen.swift
        ├── SearchView.swift
        ├── HomeView.swift
        ├── PlaylistView.swift
        ├── LibraryView.swift
        ├── SongRowView.swift
        └── Components.swift            ← artwork, blurred background, tokens
```

### 1.2 MVVM responsibilities

```
┌─────────────────────────── SWIFTUI VIEWS (dumb, declarative) ──────────────────────────┐
│  RootView · MiniPlayerBar · PlayerScreen · SearchView · HomeView · PlaylistView        │
│  Bind only to view models; never touch URLSession / AVPlayer / SwiftData directly.     │
└──────────────▲───────────────────────────────────────────────┬─────────────────────────┘
               │ binds                                          │ publishes
┌──────────────┴────────────────── VIEW MODELS ────────────────▼─────────────────────────┐
│  @MainActor final class X: ObservableObject  (@Published state, async funcs)           │
│  SearchViewModel · HomeViewModel · PlaylistViewModel                                   │
│  PlaybackManager *is* the playback view model (queue, isPlaying, currentTime, ...)     │
└──────────────▲───────────────────────────────────────────────┬─────────────────────────┘
               │ calls (async/throws)                           │ callbacks / notifications
┌──────────────┴─────────────────── SERVICES ──────────────────▼─────────────────────────┐
│  InnertubeAPI (typed endpoints)          PlaybackManager (AVPlayer)                    │
│  InnertubeClient (URLSession transport)  AudioSessionManager (AVAudioSession)          │
│  MediaParser (renderer → models)         NowPlayingManager (MediaPlayer)               │
│  AppDatabase (SwiftData)                 LrcLibClient (lyrics)                         │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

Rules that keep the architecture clean:

1. **Views never call services directly.** Everything goes through a view model (or
   `PlaybackManager`, which *is* a view model for playback).
2. **View models are `@MainActor`** and publish via `@Published`. Async service calls
   hop off the main actor automatically (URLSession does its own threading).
3. **Domain models are value types** (`Song`, `Album`, `Artist`, `SearchItem`).
   Renderer types from the API layer never leak into views.
4. **One `AppEnvironment` container** (`@EnvironmentObject`) wires everything. Swap in
   mocks per-target for tests later.

### 1.3 Error handling strategy

- Services throw typed errors (`InnertubeError`, `PlaybackError`).
- View models catch, map to a `@Published errorMessage`, and views render
  `ContentUnavailableView` or an inline message.
- Transport errors are retried (3×, exponential backoff) inside `InnertubeClient` —
  exactly like the Android `withRetry`.

---

## Phase 2 — The networking & API layer

### 2.1 The InnerTube protocol in one paragraph

YouTube Music (like all of YouTube) is driven by **InnerTube**: a JSON-over-POST
"API" served from `music.youtube.com/youtubei/v1/`. You send a body with a `context`
describing which "client" you're impersonating, plus endpoint-specific fields, and get
back a giant renderer tree. The Android app treats it as a black box; so do we.

### 2.2 Endpoints

| Endpoint | Purpose | Android reference |
|---|---|---|
| `search` | Search + pagination (`continuation`/`ctoken` params) | `InnerTube.search()` |
| `browse` | Home feed, playlists, albums, lyrics (by `browseId`) | `InnerTube.browse()` |
| `player` | Playability + stream formats for a `videoId` | `InnerTube.player()` |
| `next` | Up-next queue, lyrics/related tab endpoints, automix | `InnerTube.next()` |
| `music/get_search_suggestions` | Type-ahead suggestions | `InnerTube.getSearchSuggestions()` |
| `music/get_queue` | Explicit queue fetch | `InnerTube.getQueue()` |
| `get_transcript` | Auto-generated captions (params = base64 of `\n\u{000B}<videoId>`) | `InnerTube.getTranscript()` |

Base URL: `https://music.youtube.com/youtubei/v1/`
Public key (query param): `key=AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX3` (also add `prettyPrint=false`).

### 2.3 Request anatomy — headers

Every request carries these headers (this is the Android `ytClient()` exactly):

| Header | Value |
|---|---|
| `Content-Type` | `application/json` |
| `Accept` | `application/json` |
| `Accept-Language` | `<hl>,<gl>;q=0.9,en;q=0.8` |
| `Cache-Control` | `no-cache` |
| `X-Goog-Api-Format-Version` | `1` |
| `X-YouTube-Client-Name` | numeric client ID (e.g. `67`, `101`, `5`) |
| `X-YouTube-Client-Version` | client version string |
| `X-Origin` | `https://music.youtube.com` |
| `Referer` | `https://music.youtube.com/` |
| `X-Goog-Visitor-Id` | `visitorData` (fetched at startup) |
| `User-Agent` | per-client string |
| `Cookie` / `Authorization` | only when signed in (later milestone) |

The `Authorization` for signed-in requests is `SAPISIDHASH <ts>_<sha1("<ts> <SAPISID> https://music.youtube.com")>` — implement it in the login milestone; the plumbing is already in `InnertubeClient`.

### 2.4 Request anatomy — body

```jsonc
{
  "context": {
    "client": {
      "clientName": "VISIONOS",          // which client we impersonate
      "clientVersion": "0.1",
      "osName": "visionOS", "osVersion": "1.3.21O771",
      "deviceMake": "Apple", "deviceModel": "RealityDevice14,1",
      "gl": "US", "hl": "en-US",
      "visitorData": "Cgt…"              // from sw.js_data
    },
    "user": { "lockedSafetyMode": false, "onBehalfOfUser": null },
    "request": { "useSsl": true }
  },
  "videoId": "dQw4w9WgXcQ",              // endpoint-specific fields follow
  "playlistId": null,
  "contentCheckOk": true,
  "racyCheckOk": true
}
```

Per-endpoint extra fields (all mirrored in `InnertubeModels.swift`):

| Endpoint | Extra body fields |
|---|---|
| `search` | `query`, `params` (filter token) |
| `browse` | `browseId` (e.g. `FEmusic_home`), `params`, `continuation` |
| `player` | `videoId`, `playlistId`, `playbackContext.contentPlaybackContext.signatureTimestamp`, `contentCheckOk: true`, `racyCheckOk: true` |
| `next` | `videoId`, `playlistId`, `playlistSetVideoId`, `index`, `params`, `continuation` |
| `music/get_search_suggestions` | `input` |

### 2.5 Client profiles (the table that matters)

Verified from `innertube/.../models/YouTubeClient.kt`:

| Name | Version | ID | UA (short) | Use |
|---|---|---|---|---|
| `WEB_REMIX` | 1.20260213.01.00 | 67 | Firefox 140 UA | **search / browse / next** (main client) |
| `VISIONOS` | 0.1 | 101 | Safari 18 UA | **player — direct stream URLs** ⭐ |
| `IOS` | 21.03.1 | 5 | `com.google.ios.youtube/21.03.1 (iPhone16,2; …)` | player fallback |
| `ANDROID_VR` | 1.65.10 | 28 | Oculus Quest 3 UA | player fallback (also direct URLs) |
| `WEB` | 2.20260213.00.00 | 1 | Firefox UA | general fallback |

Rules of thumb:

- **Search/browse/queue → `WEB_REMIX`** (it's what the Android app uses; supports
  `dataSyncId` for signed-in browsing).
- **Player/streams → `VISIONOS` first** (direct URLs), then `IOS`, then `ANDROID_VR`.
- `WEB_REMIX` streams need a PoToken + signature timestamp and often return ciphered
  URLs — avoid for playback until the decipher milestone.
- **Pin recent versions.** YouTube bot-gates stale client versions (the repo shows
  measured 403s / `LOGIN_REQUIRED` on old pins). Bump periodically.

### 2.6 Session bootstrap — visitorData

Most endpoints 403 without a visitor ID. Get it like the Android app does:

1. `GET https://music.youtube.com/sw.js_data`
2. Regex `"visitorData":"([^"]+)"` out of the JS payload
3. Fallback: same regex over the `ytcfg` block in `https://www.youtube.com` HTML

Implemented in `InnertubeClient.ensureVisitorData()`.

### 2.7 Codable strategy for renderer trees

InnerTube responses are enormous, deeply nested, and *type-tagged*: an array element is
`{"musicShelfRenderer": {...}}` or `{"musicCarouselShelfRenderer": {...}}`, etc. The
Android code models this with wrapper structs holding **one optional field per possible
renderer**. Swift does the same, and `JSONDecoder` ignores unknown keys by default:

```swift
struct SectionContent: Decodable {
    let musicShelfRenderer: MusicShelfRenderer?
    let musicCarouselShelfRenderer: MusicCarouselShelfRenderer?
    let musicPlaylistShelfRenderer: MusicPlaylistShelfRenderer?
    let musicDescriptionShelfRenderer: MusicDescriptionShelfRenderer?
}
```

Only model the branches you read. Adding a new renderer later is a 5-line change.
One gotcha handled in `Format`: YouTube sometimes serializes `contentLength` as a string —
the custom `init(from:)` tolerates both.

### 2.8 Response paths cheat-sheet (all verified in the Android parser)

```
search  → contents.tabbedSearchResultsRenderer.tabs[0].tabRenderer.content
          .sectionListRenderer.contents[].musicShelfRenderer
          .title / .contents[] / .continuations[0].nextContinuationData.continuation
search continuation → continuationContents.musicShelfContinuation
home    → contents.singleColumnBrowseResultsRenderer.tabs[0].tabRenderer.content
          .sectionListRenderer.contents[].musicCarouselShelfRenderer
playlist/album → contents.{single|two}ColumnBrowseResultsRenderer.tabs[0].tabRenderer
          .content.sectionListRenderer.contents[].musicPlaylistShelfRenderer
          title/subtitle/artwork from response.header.*HeaderRenderer
          playlistId from microformat.microformatDataRenderer.urlCanonical (after '=')
lyrics  → sectionListRenderer.contents[].musicDescriptionShelfRenderer.description.runs
queue (next) → contents.singleColumnMusicWatchNextResultsRenderer.tabbedRenderer
          .watchNextTabbedResultsRenderer.tabs[0].tabRenderer.content
          .musicQueueRenderer.content.playlistPanelRenderer.contents[]
          .playlistPanelVideoRenderer (selected: Bool = current track)
          tabs[1].tabRenderer.endpoint.browseEndpoint = lyrics tab
          tabs[2].tabRenderer.endpoint.browseEndpoint = related tab
player  → playabilityStatus.status ("OK") · streamingData.adaptiveFormats[]
          .formats[] · streamingData.expiresInSeconds · videoDetails
          · playbackTracking.videostatsPlaybackUrl.baseUrl
```

### 2.9 Mapping renderers → domain models (`MediaParser`)

The Android `SearchPage.toYTItem()` is the gold standard for row parsing; the Swift
`MediaParser` mirrors it exactly:

- **Song id cascade**: `playlistItemData.videoId` → `navigationEndpoint.watchEndpoint.videoId`
  → overlay play-button endpoint → first flex-column run endpoint.
- **Secondary line** (`flexColumns[1].text.runs`) is a run array split on the literal
  `" • "` separator → segments `[artists, album, duration]`.
- **Artists** = first segment at *even* indices (`oddElements()` — separators sit at odd
  indices). Each artist run carries an optional `browseEndpoint` id.
- **Album** = second segment's first run that has a `browseEndpoint`.
- **Duration** = last segment's text parsed as `m:ss` / `h:mm:ss` (`TimeParser`).
- **Explicit** = any badge with `iconType == "MUSIC_EXPLICIT_BADGE"`.
- **Thumbnail** = last thumbnail URL (largest), resized with YouTube's
  `=wN-hN-l90-rj` suffix scheme (`MediaParser.thumbnailURL`).

### 2.10 Pagination (continuations)

Search, playlists and the queue are paginated with opaque continuation tokens:

- Search: POST `search` with **query params** `continuation=<token>&ctoken=<token>`
  (body has no query), read `continuationContents.musicShelfContinuation`.
- Playlist: POST `browse` with `continuation` **in the body**.
- Queue: `next` with `continuation` in the body → `playlistPanelContinuation`.

### 2.11 Stream URL resolution (`StreamURLResolver`)

1. Call `player` with `VISIONOS` → fall back through `IOS` / `ANDROID_VR`.
2. Accept only responses where `playabilityStatus.status == "OK"` and
   `adaptiveFormats` is non-empty.
3. Filter audio-only formats (`width == nil`).
4. **Prefer AAC `audio/mp4` (itag 141 → 140 → 139).** Critical iOS constraint:
   `AVPlayer` cannot decode Opus-in-WebM (itags 249/250/251) — the Android app plays
   those via ExoPlayer. If no AAC exists, take the best remaining audio format.
5. If `format.url` is nil but `signatureCipher`/`cipher` is present, the stream needs
   deciphering — not implemented in the starter (the chosen clients return direct URLs).

Stream URLs expire (`expiresInSeconds`, typically ~6 h). On a 403 mid-playback, re-run
`player` for a fresh URL (TODO in the error-handling milestone).

### 2.12 Transport details

- `URLSession` with 60 s request / 120 s resource timeouts.
- Retry transport errors (`URLError`) 3× with exponential backoff (500 ms → 1 s → 2 s).
  Do **not** retry HTTP 4xx.
- `URLCache` (20 MB memory / 200 MB disk) for thumbnails and other GETs. InnerTube POSTs
  are `Cache-Control: no-cache`.
- A playback-registration beacon (`playbackTracking.videostatsPlaybackUrl.baseUrl`,
  host rewritten `s.youtube.com` → `music.youtube.com`, plus `ver=2&c=WEB_REMIX&cpn=<16-char>`
  and `list`/`referrer`) is fired when a track starts — mirroring
  `InnerTube.registerPlayback()`.

---

## Phase 3 — Audio playback & background audio

### 3.1 The three pillars of background audio

| Requirement | Where |
|---|---|
| `AVAudioSession` category `.playback` | `AudioSessionManager.configure()` (set once at startup) |
| Info.plist `UIBackgroundModes: [audio]` | `EchoMusic/App/Info.plist` |
| Lock screen metadata + controls | `NowPlayingManager` (`MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`) |

Without all three, audio stops when the app backgrounds. With them, `AVPlayer` keeps
running and the lock screen/Control Center gains full control.

### 3.2 The playback pipeline

`PlaybackManager.play(_:startingAt:playlistId:)`:

```
1. Store queue + index, call playCurrentItem()
2. Task:
   a. api.player(videoId:playlistId:)          → PlayerResponse
   b. StreamURLResolver.bestAudioFormat(in:)   → Format (AAC-first)
   c. makePlayerItem(url:)                     → AVPlayerItem
        AVURLAsset(url:options:["AVURLAssetHTTPHeaderFieldsKey":
            ["User-Agent": <same UA as player request>]])
        item.preferredForwardBufferDuration = 30
   d. replaceCurrentItem(item)                 → wires observers, resets currentTime
   e. nowPlaying.update(for: song, ...)        → lock screen metadata + artwork
   f. player.play()
   g. registerPlaybackIfPossible(response)     → fire-and-forget beacon
3. KVO drives @Published state:
   - item.status → .failed → errorMessage
   - item.duration → duration
   - player.timeControlStatus → isPlaying
   - periodic time observer (0.5 s) → currentTime + lock screen progress
4. .AVPlayerItemDidPlayToEndTime → itemDidFinish() → repeat one? seek 0 : skipToNext()
```

### 3.3 Lock screen (MPNowPlayingInfoCenter)

Keys the app writes (`NowPlayingManager.update`):

- `MPMediaItemPropertyTitle` / `MPMediaItemPropertyArtist` / `MPMediaItemPropertyAlbumTitle`
- `MPMediaItemPropertyPlaybackDuration`
- `MPNowPlayingInfoPropertyElapsedPlaybackTime` (updated every 0.5 s while playing)
- `MPNowPlayingInfoPropertyPlaybackRate` (1 playing / 0 paused)
- `MPMediaItemPropertyArtwork` = `MPMediaItemArtwork(boundsSize:) { _ in image }`,
  loaded async from the song thumbnail (resized via `MediaParser.thumbnailURL`).

### 3.4 Remote command center

Registered once at startup (`NowPlayingManager.configureRemoteCommands`):

| Command | Action |
|---|---|
| `playCommand` / `pauseCommand` / `togglePlayPauseCommand` | transport |
| `nextTrackCommand` / `previousTrackCommand` | `skipToNext()` / `skipToPrevious()` |
| `changePlaybackPositionCommand` | `seek(to: event.positionTime)` |
| `skipForward/BackwardCommand` | disabled (we use the scrubber) |

### 3.5 Interruptions & route changes (`AudioSessionManager`)

- **Interruption began** (call, Siri, alarm): remember `wasPlayingBeforeInterruption`,
  pause.
- **Interruption ended** with `.shouldResume`: resume if it was playing before.
- **Route change `.oldDeviceUnavailable`** (headphones unplugged): pause.
- All handlers run on the main queue and hop to `@MainActor` before touching
  `PlaybackManager`.

### 3.6 Stream headers & the direct-URL strategy

- Stream URLs from the `player` response are HTTPS googlevideo URLs. `AVPlayer` is happy
  with them, but send the **same `User-Agent` used for the `player` request** via
  `AVURLAssetHTTPHeaderFieldsKey` — some streams 403 without it.
- Because playback uses `VISIONOS`/`IOS`/`ANDROID_VR`, URLs arrive pre-deciphered. If a
  future client (`WEB_REMIX`) returns `signatureCipher`, you'd need to implement
  `s`-signature deciphering + `n`-parameter transform. Pragmatic approach if you ever go
  there: run the relevant `player.js` snippet in a `WKWebView`, or port an open-source
  Swift decipherer. The starter deliberately avoids this.
- Stream URLs expire (~6 h). Add a 403 → re-fetch `player` handler in the polish
  milestone.

### 3.7 Quality, gapless & preloading notes

- `preferredForwardBufferDuration = 30` smooths playback on flaky networks.
- The starter swaps `AVPlayerItem` at track boundaries (a few hundred ms gap, typical of
  non-gapless players). For gapless: preload the next item's asset before the boundary
  and swap at `AVPlayerItemDidPlayToEndTime`; true gapless needs
  `AVQueuePlayer`+`AVQueuePlayerItem`s or `AVSampleBufferRenderSynchronizer`.
- Opus (`audio/webm`) is skipped on iOS — see `StreamURLResolver`.

---

## Phase 4 — Core UI layout

### 4.1 View hierarchy

```
EchoMusicApp
└── RootView
    ├── TabView
    │   ├── NavigationStack → HomeView       (carousel sections)
    │   ├── NavigationStack → SearchView     (field + shelf sections)
    │   └── NavigationStack → LibraryView    (favorites)
    │       └── navigationDestination → PlaylistView
    ├── safeAreaInset(.bottom)
    │   └── MiniPlayerBar  ← shown when currentSong != nil
    └── fullScreenCover
        └── PlayerScreen
```

- The mini-player is pinned above the tab bar with `safeAreaInset(edge: .bottom)` —
  it never overlaps the tab bar and animates in/out for free.
- The full player is a `.fullScreenCover` (YouTube Music behavior: it slides up over
  everything).

### 4.2 Mini player (`MiniPlayerBar`)

```
[art 44pt]  Title                     [▶/⏸]  [⏭]
            Artist(s)
────────────────────────────────────────────── (ultraThinMaterial)
```

Tap anywhere → open `PlayerScreen`. Play/pause + next inline. Observed from
`PlaybackManager` (`currentSong`, `isPlaying`).

### 4.3 Player screen (`PlayerScreen`)

```
┌──────────────────────────────────────┐
│  ⌄      Now Playing            ⋯    │  top bar
│                                      │
│          ┌──────────────┐            │
│          │   album art  │  up to     │  ArtworkView + shadow
│          │    (380pt)   │  380pt     │
│          └──────────────┘            │
│                                      │
│   Title (2 lines, bold)              │
│   Artist(s) (secondary)              │
│                                      │
│  ───────────────●────────────        │  Slider (scrub: drag → seek on release)
│  0:37                   3:12         │  monospaced digits
│                                      │
│  🔀    ⏮      ▶/⏸      ⏭    🔁      │  shuffle · prev · play · next · repeat
└──────────────────────────────────────┘
Background: blurred artwork + 55% black overlay (BlurredArtworkBackground)
```

The slider uses a two-state binding: while dragging it shows the scrub position, and
only on release does it call `seek(to:)` — no mid-drag seeking spam.

### 4.4 Search view (`SearchView`)

- Custom `TextField` with 350 ms debounce (`SearchViewModel.queryChanged`).
- Type-ahead suggestions fetched in parallel with results.
- Results render as `List` sections, one per `MusicShelfRenderer` ("Top result",
  "Songs", "Albums", …) — each section's rows map to `SearchItem` (song → plays the
  section's songs from that index; album/playlist → `NavigationLink` to `PlaylistView`).
- Infinite scroll: the trailing `ProgressView` fires `loadMore()` while a
  `continuation` token exists.
- Empty state shows recent searches from SwiftData.

### 4.5 Home & playlist views

- `HomeView`: `LazyVStack` of `HomeSectionView` carousels (horizontal `ScrollView` of
  150 pt cards). Pull-to-refresh re-fetches `browse(FEmusic_home)`.
- `PlaylistView`: header (artwork, title, subtitle, Play) + track list + pagination
  footer. Works for both playlists and albums since both come from `browse`.

### 4.6 Design tokens

Dark-first, YouTube-Music-inspired: `AppTheme.accent = .red`, `.preferredColorScheme(.dark)`,
`Color(.secondarySystemBackground)` for placeholders, `.ultraThinMaterial` for the mini
player, white-on-blurred-artwork text on the player screen.

---

## Phase 5 — Step-by-step build plan

Chronological milestones. Each has a clear **definition of done** — build in this order
because each milestone is a working app, not a half-finished feature.

### M0 — Project scaffold (0.5–1 day)
- [ ] Create project (XcodeGen `ios/project.yml` or manual Xcode project)
- [ ] Info.plist: `UIBackgroundModes: [audio]`, dark appearance
- [ ] `AppEnvironment` DI container compiles; empty `RootView` with 3 tabs
- [ ] **Done:** app builds and launches on device + simulator.

### M1 — Networking spike: search only (1–2 days)
- [ ] `InnertubeClient` transport (headers, key, retry) + `visitorData` bootstrap
- [ ] `search(query:)` returning parsed `Song`s (prove the whole chain: POST → decode → parse)
- [ ] **Done:** in a scratch view, type a query and see real tracks with titles/artists/artwork.
  *(If this milestone stalls, nothing else matters — debug it first.)*

### M2 — Search UI (1 day)
- [ ] `SearchView` + `SearchViewModel` with debounce and shelf sections
- [ ] **Done:** full search experience with results list.

### M3 — Audio playback core (2–3 days) ⭐
- [ ] `PlaybackManager` with single `AVPlayer`, play one track end-to-end
- [ ] `StreamURLResolver` (AAC-first), `makePlayerItem` with UA header
- [ ] Progress slider + transport controls on a basic player screen
- [ ] **Done:** tap a search result, music plays, seek works. **Test on a physical device —
  the simulator cannot exercise background audio.**

### M4 — Background audio + lock screen (1–2 days)
- [ ] `AudioSessionManager` (category, interruptions, route changes)
- [ ] `NowPlayingManager` (metadata, artwork, remote commands)
- [ ] **Done:** background the app and audio continues; lock screen shows
  title/artist/artwork and play/pause/next/previous/scrub all work.

### M5 — Full player + mini player (1–2 days)
- [ ] `PlayerScreen` (blurred art, scrubber, shuffle/repeat)
- [ ] `MiniPlayerBar` in `safeAreaInset` + `fullScreenCover` presentation
- [ ] **Done:** YouTube-Music-like now-playing experience.

### M6 — Playlists, albums & queue (2–3 days)
- [ ] `browse` → `PlaylistView` (header + tracks + continuation pagination)
- [ ] `next` → up-next queue, `skipToNext/Previous`, repeat/shuffle modes
- [ ] Automix: when the queue ends, call `next` with the current track's
  `watchEndpoint` to fetch the next batch (implemented in `PlaybackManager.autoplayNextBatch`)
- [ ] **Done:** play a whole album end-to-end with correct next-track flow.

### M7 — Home feed + library (1–2 days)
- [ ] `HomeView` carousels from `browse("FEmusic_home")`
- [ ] SwiftData: favorites (heart on rows), search history, "recently played" (from
  `PlaybackManager` events)
- [ ] **Done:** home feed loads; favorites persist across launches.

### M8 — Search polish (1 day)
- [ ] Type-ahead suggestions, filter chips (song/album/artist/playlist params),
  infinite scroll, recent-search history
- [ ] **Done:** search feels like a first-class product.

### M9 — Offline downloads & caching (2–3 days)
- [ ] `URLSessionDownloadTask` audio → `Documents/Offline/<videoId>.m4a`, resume support
- [ ] `OfflineTrack` SwiftData metadata; play offline file URLs in `PlaybackManager`
- [ ] Cache thumbnails (`URLCache`) and thumbnail-sized artwork
- [ ] **Done:** download a track, airplane-mode, play it.

### M10 — Lyrics (1–2 days)
- [ ] YouTube's static lyrics via the `next` tab-1 endpoint → `browse`
- [ ] Synced LRC via `LrcLibClient` (LRCLIB), rendered in a lyrics view synced to
  `currentTime`
- [ ] **Done:** swipe up on the player to see scrolling synced lyrics.

### M11 — Sign-in & personalization (2–4 days, optional)
- [ ] `ASWebAuthenticationSession` → extract cookies (`SAPISID`, …), store in Keychain
- [ ] `SAPISIDHASH` Authorization header in `InnertubeClient`
- [ ] Likes, personal playlists via `browse/edit_playlist`
- [ ] **Done:** liked songs appear in Library.

### M12 — Hardening (ongoing)
- [ ] Stream 403/expiry handling (re-fetch `player`)
- [ ] Offline-first: cache search/home JSON, show cached on no network
- [ ] Accessibility (labels, dynamic type), error states, telemetry-light logging
- [ ] **Done:** a week of daily-driver use with no crashes.

### Ordering rationale

1. **Audio first** (M3–M4): the app is worthless if it can't play music in the
   background — the hardest and most uncertain part. Everything after is incremental.
2. **Search before home** (M1–M2): search is the smallest end-to-end slice through the
   whole stack (network → parse → UI → play). Home/browse reuse the same machinery.
3. **Queue before lyrics/offline** (M6 before M9/M10): automix needs `next`; offline
   needs queue; lyrics needs `next`'s tab endpoint.
4. **Auth last**: every feature works anonymously; sign-in only enriches.

---

## Appendix A — Reference card

| Thing | Value |
|---|---|
| Base URL | `https://music.youtube.com/youtubei/v1/` |
| API key | `AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX3` |
| Search: song filter params | `EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D` |
| Search: video filter params | `EgWKAQIQAWoKEAkQChAFEAMQBA%3D%3D` |
| Search: album filter params | `EgWKAQIYAWoKEAkQChAFEAMQBA%3D%3D` |
| Search: artist filter params | `EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D` |
| Search: featured playlist filter | `EgeKAQQoADgBagwQDhAKEAMQBRAJEAQ%3D` |
| Home browseId | `FEmusic_home` |
| Audio itags (AAC, playable on iOS) | 141 (256 kbps) · 140 (128 kbps) · 139 (48 kbps) |
| Opus itags (NOT playable on iOS) | 251 (160 kbps) · 250 (70 kbps) · 249 (50 kbps) |
| Stream URL lifetime | `expiresInSeconds` in the player response (~6 h) |
| Playback beacon | `playbackTracking.videostatsPlaybackUrl.baseUrl` + `ver=2&c&cpn&list&referrer` |
| Synced lyrics | `GET https://lrclib.net/api/search?track_name=…&artist_name=…&duration=…` |

## Appendix B — Glossary

- **InnerTube** — YouTube's private JSON API used by every official client; the
  "backend" this app talks to.
- **Renderer** — a type-tagged JSON node describing a UI element
  (`musicShelfRenderer`, `playlistPanelVideoRenderer`, …).
- **Client** — an impersonated app profile (`WEB_REMIX`, `VISIONOS`, …) shaping
  `context` + headers.
- **`visitorData`** — an anonymous session ID required by most endpoints.
- **Continuation** — an opaque pagination token (`ctoken`).
- **itag** — YouTube's format ID (141 = AAC 256 kbps, etc.).
- **PoToken** — a bot-check token (`serviceIntegrityDimensions.poToken`) required by
  some clients for playable streams.
- **CPN** — a random 16-char client playback nonce sent with the playback beacon.
- **Automix** — YouTube Music's auto-generated "similar songs" continuation of a queue.
