#!/usr/bin/env bash
# Builds and runs the AppKit motion recorder. A bundle is required for the same
# reason the still capture needs one: only a key window animates like the real thing.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
out="${1:-$root/build/motion}"
bundle="$root/build/reference-tool/AppleMotion.app"
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AppleMotion</string>
<key>CFBundleIdentifier</key><string>dev.cortado.apple-motion</string>
<key>CFBundleName</key><string>AppleMotion</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
swiftc -O "$here/apple_motion.swift" -o "$bundle/Contents/MacOS/AppleMotion"
mkdir -p "$out"
"$bundle/Contents/MacOS/AppleMotion" "$out"
