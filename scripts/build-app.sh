#!/bin/bash
# Assembles dist/Duplex.app from the release build.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=dist/Duplex.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Duplex "$APP/Contents/MacOS/Duplex"
cp .build/release/duplex-launcher "$APP/Contents/Resources/duplex-launcher"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.duplex.app</string>
    <key>CFBundleName</key><string>Duplex</string>
    <key>CFBundleDisplayName</key><string>Duplex</string>
    <key>CFBundleExecutable</key><string>Duplex</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --deep -s - "$APP"
echo "Built $APP"
