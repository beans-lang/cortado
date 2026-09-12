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
    echo "usage: tools/bundle.sh <binary> <Name> [bundle-id] [icon.icns] [KEY=sentence]..." >&2
    echo "" >&2
    echo "  KEY=sentence adds a usage description to the Info.plist, e.g." >&2
    echo "    NSCameraUsageDescription='to scan a receipt'" >&2
    echo "" >&2
    echo "  macOS kills a program that touches a privacy-gated framework" >&2
    echo "  without the matching key, on a later turn of the run loop, with" >&2
    echo "  nothing on stderr. cortado refuses to ask without one, so the" >&2
    echo "  key is what turns 'unavailable' into a real answer." >&2
    exit 2
fi

# The positional four, and then any number of KEY=sentence pairs. Positional
# because that is what every caller of this script already passes, and
# KEY=sentence after them because a usage description is a pair and writing it
# as one word is what an Info.plist entry is.
binary=""
name=""
identifier=""
icon=""
usage_keys=()
usage_words=()
for argument in "$@"; do
    case "$argument" in
        *=*)
            key="${argument%%=*}"
            sentence="${argument#*=}"
            if [[ "$key" != NS*UsageDescription ]]; then
                echo "bundle: $key is not a usage-description key — they all" >&2
                echo "        look like NSCameraUsageDescription." >&2
                exit 2
            fi
            if [[ -z "$sentence" ]]; then
                echo "bundle: $key has no sentence after the =. macOS shows it" >&2
                echo "        to the user, and an empty one is a prompt that" >&2
                echo "        does not say what for." >&2
                exit 2
            fi
            usage_keys+=("$key")
            usage_words+=("$sentence")
            ;;
        *)
            if [[ -z "$binary" ]]; then binary="$argument"
            elif [[ -z "$name" ]]; then name="$argument"
            elif [[ -z "$identifier" ]]; then identifier="$argument"
            elif [[ -z "$icon" ]]; then icon="$argument"
            else
                echo "bundle: $argument is one argument too many" >&2
                exit 2
            fi
            ;;
    esac
done
if [[ -z "$name" ]]; then
    echo "bundle: a .app needs a name" >&2
    exit 2
fi
identifier="${identifier:-org.beans-lang.cortado.$(echo "$name" | tr '[:upper:] ' '[:lower:]-')}"

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
    # The usage descriptions, each a sentence macOS shows in the prompt. A
    # program that touches the framework without one is killed rather than
    # refused, which is why cortado will not even ask without one.
    #
    # Inside the dict, obviously — and it is worth saying why that is worth
    # saying. The first version wrote them after `</plist>`, and
    # `plutil -lint` called the file OK, because a plist parser stops at the
    # closing tag and never sees what follows. The app launched, the bundle was
    # recognised, and every usage description was silently missing. Which is
    # why the check below reads a key *back* rather than trusting the file.
    index=0
    while [[ $index -lt ${#usage_keys[@]} ]]; do
        echo "  <key>${usage_keys[$index]}</key><string>${usage_words[$index]}</string>"
        index=$((index + 1))
    done
    echo '</dict>'
    echo '</plist>'
} >"$app/Contents/Info.plist"

# Every key that was asked for is readable from the finished bundle.
#
# Not "the file contains it" and not "the file lints" — both of those were true
# of a plist whose keys were all outside the dict. `plutil -extract` reads it
# the way macOS reads it, which is the only reading that counts.
index=0
while [[ $index -lt ${#usage_keys[@]} ]]; do
    key="${usage_keys[$index]}"
    if ! plutil -extract "$key" raw -o - "$app/Contents/Info.plist" >/dev/null 2>&1; then
        echo "bundle: $key is not readable from the Info.plist it was just" >&2
        echo "        written into. macOS would show no prompt and cortado" >&2
        echo "        would answer 'unavailable' with nothing to explain it." >&2
        exit 1
    fi
    index=$((index + 1))
done

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
