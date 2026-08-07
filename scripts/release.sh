#!/bin/bash
# Builds, signs (Developer ID + hardened runtime), notarizes, staples, and
# zips a distributable Duplex release for Homebrew/GitHub Releases.
#
# One-time prerequisites (Apple account owner):
#   1. A "Developer ID Application" certificate in the login keychain
#      (Xcode -> Settings -> Accounts -> Manage Certificates -> + ).
#   2. Notary credentials stored as a keychain profile:
#      xcrun notarytool store-credentials duplex-notary \
#        --apple-id YOU@EXAMPLE.COM --team-id YOURTEAMID
#
# Usage: ./scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY=${DUPLEX_SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
  | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')}
if [ -z "$IDENTITY" ]; then
  echo "error: no 'Developer ID Application' certificate found in the keychain." >&2
  echo "Create one in Xcode -> Settings -> Accounts -> Manage Certificates." >&2
  exit 1
fi
PROFILE=${DUPLEX_NOTARY_PROFILE:-duplex-notary}
echo "Signing identity: $IDENTITY"

./scripts/build-app.sh

APP=dist/Duplex.app
VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")
ZIP="dist/Duplex-$VERSION.zip"

# The launcher lives in Resources, which bundle signing does NOT descend
# into — notarization rejects unsigned nested Mach-O binaries, so sign it
# explicitly first.
codesign --force --options runtime --timestamp -s "$IDENTITY" \
  "$APP/Contents/Resources/duplex-launcher"
codesign --force --options runtime --timestamp -s "$IDENTITY" "$APP"
codesign --verify --strict --deep "$APP"

ditto -c -k --keepParent "$APP" "$ZIP"
echo "Submitting to Apple notary service (this waits for the verdict)..."
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

xcrun stapler staple "$APP"
# Rebuild the zip so the published artifact contains the stapled ticket.
rm "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "--- Gatekeeper check ---"
spctl -a -vv "$APP"
echo "--- Release artifact ---"
shasum -a 256 "$ZIP"
echo
echo "Next: create the GitHub release and update the cask:"
echo "  gh release create v$VERSION $ZIP --title \"Duplex $VERSION\" --repo bnimit/duplex"
echo "  then paste the sha256 above into packaging/duplex.rb"
