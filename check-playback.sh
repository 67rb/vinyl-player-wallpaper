#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build
swiftc Sources/VinylWallpaper/Playback.swift scripts/PlaybackChecks.swift -o .build/playback-checks
.build/playback-checks
