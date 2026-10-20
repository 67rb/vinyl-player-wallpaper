#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
STAGING_ROOT=$(mktemp -d /tmp/vinyl-wallpaper-build.XXXXXX)
trap 'rm -rf "$STAGING_ROOT"' EXIT
STAGED_APP="$STAGING_ROOT/Vinyl Wallpaper.app"
APP_DESTINATION="${VINYL_APP_DESTINATION:-$HOME/Applications/Vinyl Wallpaper.app}"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp .build/release/VinylWallpaper "$STAGED_APP/Contents/MacOS/VinylWallpaper"
ditto --norsrc --noextattr Resources "$STAGED_APP/Contents/Resources"
cp Info.plist "$STAGED_APP/Contents/Info.plist"
xattr -cr "$STAGED_APP"
codesign --force --sign - --identifier com.robeberry.vinylwallpaper "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"
mkdir -p "$(dirname "$APP_DESTINATION")"
ditto --norsrc --noextattr "$STAGED_APP" "$APP_DESTINATION"
codesign --verify --deep --strict "$APP_DESTINATION"
# Keep a workspace artifact, too. FileProvider may attach Finder metadata to
# that copy; launch the verified copy outside the synced project directory.
ditto --norsrc --noextattr "$STAGED_APP" "../Vinyl Wallpaper.app"
printf 'Built and verified %s\n' "$APP_DESTINATION"
