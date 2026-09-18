#!/usr/bin/env bash
# Builds the AppKit reference capture into an app bundle and runs it.
# A bundle is required: a bare binary never becomes the key application, and
# without a key window the default button, focus ring and active states are wrong.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
out="${1:-$root/build/reference}"
bundle="$root/build/reference-tool/AppleReference.app"
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AppleReference</string>
<key>CFBundleIdentifier</key><string>dev.cortado.apple-reference</string>
<key>CFBundleName</key><string>AppleReference</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSUIElement</key><false/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
swiftc -O "$here/apple_reference.swift" -o "$bundle/Contents/MacOS/AppleReference"
mkdir -p "$out"
"$bundle/Contents/MacOS/AppleReference" "$out"
