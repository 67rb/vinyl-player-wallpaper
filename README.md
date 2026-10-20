# Vinyl Player Wallpaper for Mac

> **Project status: 95% complete.** This is a work in progress; the percentage is the project's current self-reported status, not a release or testing guarantee.

Vinyl Player Wallpaper is a native macOS desktop experience that reflects the music currently playing in Spotify. A record spins during playback, the current album cover appears beside it, and recently played records build a visual history.

## Features

- Eight listening-room scenes: four room designs, three rain or storm moods, and a fireside scene.
- Spotify playback and album-art display, with previous tracks collected in the scene.
- Optional ambient rain, fire, and thunder sounds.
- Native macOS rendering for the desktop wallpaper and full-size preview.
- Per-display wallpapers with saved scene, playback history, and sound preferences.
- Local media assets so the scenes do not depend on remote image requests.

The wallpaper reads the current song and artwork from Spotify; playback stays in Spotify. macOS may ask you to allow the app to control Spotify through Apple Events. Scene preferences and playback history are stored locally.

## Requirements

- macOS 13 or later.
- Swift toolchain and Xcode Command Line Tools.
- Spotify installed for live music synchronization. The room scenes can be previewed independently.

## Build

    swift build -c release
    ./check-playback.sh
    ./build.sh

The build script packages and ad-hoc signs the app, then installs it at ~/Applications/Vinyl Wallpaper.app by default. Set VINYL_APP_DESTINATION to choose another install location.

Open the app and select Wallpapers & Spotify… to choose a scene, preview it, connect to Spotify, or set optional room sounds. Closing the collection window leaves the wallpaper running. Command-comma opens settings and Command-Q quits.

## Media credits

The fire footage and rain-window photograph are credited in asset-provenance.md. The bundled fire and rain media are used under the Pexels license. Room interiors and tonearms are generated artwork; ambient sound files are locally synthesized.

## Project layout

- Sources/VinylWallpaper/ — native macOS app and playback code.
- Resources/ — scene definitions, wallpaper UI resources, artwork, and bundled media.
- scripts/PlaybackChecks.swift — playback logic checks.
- Info.plist — app identity and macOS metadata.

## License

No software license has been added yet. The bundled third-party media remains subject to the license terms described in asset-provenance.md.
