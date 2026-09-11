#!/usr/bin/env bash
# Wraps a binary built for the iOS Simulator as an installable .app.
#
#     beansc build app.b --target arm64-apple-ios-sim -o build/app
#     tools/bundle_ios.sh build/app Gallery org.example.gallery
#     xcrun simctl install booted build/Gallery.app
#     xcrun simctl launch booted org.example.gallery
#
# An iOS bundle is flatter than a macOS one — the binary sits at the top rather
# than under Contents/MacOS — and it needs three keys a Mac does not:
# CFBundleSupportedPlatforms, a launch-screen declaration, and a device family.
# Without the launch screen iOS runs the application in a letterboxed 320x480
# box as if it were an iPhone 4 application, which looks like a layout bug and
# is not one.
#
# Device only, not distribution: a simulator build is not signed for a phone,
# and putting one on hardware needs a provisioning profile and a real identity.
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "usage: tools/bundle_ios.sh <binary> <Name> [bundle-id]" >&2
    exit 2
fi

binary="$1"
name="$2"
identifier="${3:-org.beans-lang.cortado.$(echo "$name" | tr '[:upper:] ' '[:lower:]-')}"

[[ -f "$binary" ]] || { echo "bundle_ios: $binary does not exist" >&2; exit 1; }
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "bundle_ios: iOS SDKs only exist on macOS" >&2
    exit 1
fi

root="$(cd "$(dirname "$binary")" && pwd)"
app="$root/$name.app"
rm -rf "$app"
mkdir -p "$app"
cp "$binary" "$app/$name"

{
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    echo '<plist version="1.0">'
    echo '<dict>'
    echo "  <key>CFBundleName</key><string>$name</string>"
    echo "  <key>CFBundleDisplayName</key><string>$name</string>"
    echo "  <key>CFBundleExecutable</key><string>$name</string>"
    echo "  <key>CFBundleIdentifier</key><string>$identifier</string>"
    echo '  <key>CFBundleVersion</key><string>1</string>'
    echo '  <key>CFBundleShortVersionString</key><string>1.0</string>'
    echo '  <key>CFBundlePackageType</key><string>APPL</string>'
    echo '  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>'
    echo '  <key>MinimumOSVersion</key><string>14.0</string>'
    echo '  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>'
    echo '  <key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>'
    # An empty dictionary is enough: its presence is what tells iOS the
    # application is built for modern screens. Without it every window is
    # letterboxed at 320x480 and the layout looks broken.
    echo '  <key>UILaunchScreen</key><dict/>'
    echo '  <key>UIApplicationSupportsMultipleScenes</key><false/>'
    echo '</dict>'
    echo '</plist>'
} >"$app/Info.plist"

plutil -lint "$app/Info.plist" >/dev/null
codesign --force --sign - --timestamp=none "$app" >/dev/null 2>&1 || true

echo "built $app"
echo "  xcrun simctl install booted $app && xcrun simctl launch booted $identifier"
