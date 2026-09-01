# Echo Music — iOS

A native iOS client for YouTube Music (Swift + SwiftUI), designed as a clean, ad-free
streaming client in the spirit of the [Echo Music Android app](https://github.com/iamsmmh/Echo-Music).
This directory contains the **blueprint** (`BLUEPRINT.md`) and a **starter architecture**
(working Swift code) for that client.

> ⚠️ **Legal note.** YouTube Music's InnerTube API is private and undocumented. The
> Android app this is modeled on is open source and self-hosted for personal use.
> A native client that streams from YouTube Music is not something Apple's App Store
> review is friendly to. Plan to distribute via TestFlight/TestFlight-like sideloading
> or personal builds, not the public App Store. Use responsibly and respect
> YouTube's Terms of Service.

## What's here

```
ios/
├── BLUEPRINT.md                  ← the full blueprint (5 phases, build plan)
├── project.yml                   ← XcodeGen manifest (optional)
└── EchoMusic/
    ├── App/                      ← app entry, DI container, Info.plist
    ├── Core/                     ← extensions & small utilities
    ├── Networking/
    │   ├── Innertube/            ← InnerTube API: client, models, parser, streams
    │   ├── LrcLibClient.swift    ← synced lyrics (LRCLIB)
    │   └── Models/               ← clean domain models
    ├── Playback/                 ← AVPlayer engine, audio session, lock screen
    ├── Storage/                  ← SwiftData (favorites, history, playlists, offline)
    ├── ViewModels/               ← MVVM view models
    └── Views/                    ← SwiftUI screens
```

## Quick start

**Option A — XcodeGen (recommended)**

```bash
brew install xcodegen
cd ios
xcodegen generate
open EchoMusic.xcodeproj
```

**Option B — manual**

Create a new iOS App project in Xcode (SwiftUI, iOS 17+), then drag the
`EchoMusic/` folder in. Set:

- Bundle identifier: anything you own
- Info.plist → `EchoMusic/App/Info.plist` (contains `UIBackgroundModes: audio`)

## First run

1. Build & run on a simulator or device.
2. Open the **Search** tab and type a query.
3. Tap a result to play — audio starts streaming immediately.
4. Lock the screen: controls and metadata appear on the lock screen.

## Architecture at a glance

- **MVVM** — views are dumb SwiftUI; view models (`ObservableObject`, `@MainActor`)
  own state; the `PlaybackManager` doubles as the playback view model.
- **Networking** — `InnertubeClient` (URLSession transport + headers) →
  `InnertubeAPI` (typed endpoints) → `MediaParser` (renderer JSON → domain models).
- **Playback** — `AVPlayer` + `AVAudioSession` (background) +
  `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter` (lock screen).
- **Persistence** — SwiftData for favorites, search history, playlists, offline tracks.

See `BLUEPRINT.md` for the full design and the milestone-by-milestone build plan.
