#!/usr/bin/env bash
# Wraps a built binary as a macOS .app bundle.
#
#     tools/bundle.sh build/gallery "Gallery" com.example.gallery
#     open build/Gallery.app
#
# A bare Mach-O binary runs and shows a window, which is why cortado's examples
# work without this. What it does *not* get is a name in the Dock, a name in
# the menu bar, a place in Launch Services, a document type, an icon, or the
# ability to be signed and notarised — all of which come from being a bundle
# with an Info.plist. A program nobody can double-click is not shipped.
#
# Codesigning is ad-hoc by default (`-s -`), which is enough to run locally on
# Apple silicon and is *not* enough to distribute: that needs a Developer ID and
# notarisation, which need an account, so this script does the part that can be
# automated and says so rather than pretending.
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "usage: tools/bundle.sh <binary> <Name> [bundle-id] [icon.icns]" >&2
    exit 2
fi

binary="$1"
name="$2"
identifier="${3:-org.beans-lang.cortado.$(echo "$name" | tr '[:upper:] ' '[:lower:]-')}"
icon="${4:-}"

if [[ ! -f "$binary" ]]; then
    echo "bundle: $binary does not exist — build it first" >&2
    exit 1
fi
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "bundle: a .app is a macOS thing, and this is $(uname -s)." >&2
    echo "        Windows wants an .exe beside a manifest; Linux wants a" >&2
    echo "        .desktop file. Those are separate scripts, unwritten." >&2
    exit 1
fi

root="$(cd "$(dirname "$binary")" && pwd)"
app="$root/$name.app"
version="$(sed -n 's/^## \[\([0-9][^]]*\)\].*/\1/p' \
    "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/CHANGELOG.md" 2>/dev/null | head -1)"
[[ -z "$version" ]] && version="0.1.0"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/$name"

# LSMinimumSystemVersion is 11.0 because that is the first release with Apple
# silicon, and cortado's host uses nothing older. CFBundleIconFile is written
# only when there is an icon: a key naming a file that is not there makes the
# Finder show the generic icon rather than falling back to the default one.
{
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    echo '<plist version="1.0">'
    echo '<dict>'
    echo "  <key>CFBundleName</key><string>$name</string>"
    echo "  <key>CFBundleDisplayName</key><string>$name</string>"
    echo "  <key>CFBundleExecutable</key><string>$name</string>"
    echo "  <key>CFBundleIdentifier</key><string>$identifier</string>"
    echo "  <key>CFBundleVersion</key><string>$version</string>"
    echo "  <key>CFBundleShortVersionString</key><string>$version</string>"
    echo '  <key>CFBundlePackageType</key><string>APPL</string>'
    echo '  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>'
    echo '  <key>LSMinimumSystemVersion</key><string>11.0</string>'
    echo '  <key>NSHighResolutionCapable</key><true/>'
    if [[ -n "$icon" ]]; then
        echo "  <key>CFBundleIconFile</key><string>$(basename "${icon%.icns}")</string>"
    fi
    echo '</dict>'
    echo '</plist>'
} >"$app/Contents/Info.plist"

if [[ -n "$icon" ]]; then
    cp "$icon" "$app/Contents/Resources/"
fi

# A malformed plist is not a warning — the Finder refuses to launch the bundle
# and says nothing useful — so it is checked here rather than discovered.
plutil -lint "$app/Contents/Info.plist" >/dev/null

identity="${CORTADO_SIGN_IDENTITY:--}"
codesign --force --sign "$identity" --timestamp=none "$app" >/dev/null 2>&1 || {
    echo "bundle: codesign failed with identity '$identity'" >&2
    exit 1
}
codesign --verify --strict "$app"

echo "built $app"
echo "  identifier $identifier, version $version"
if [[ "$identity" == "-" ]]; then
    echo "  signed ad-hoc: runs on this machine, and is not distributable."
    echo "  For that, set CORTADO_SIGN_IDENTITY to a Developer ID and notarise."
fi
