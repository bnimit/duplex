#!/bin/bash
# Resumes a release after notarytool's --wait died mid-poll: waits for the
# existing submission, then staples and finalizes the artifact.
set -euo pipefail
cd "$(dirname "$0")/.."
ID="${1:?usage: resume-notary.sh <submission-id>}"
APP=dist/Duplex.app
VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")
ZIP="dist/Duplex-$VERSION.zip"

# Retry the wait through transient network failures.
while true; do
  if xcrun notarytool wait "$ID" --keychain-profile duplex-notary; then break; fi
  echo "wait interrupted (network?); retrying in 60s..."
  sleep 60
done

STATUS=$(xcrun notarytool info "$ID" --keychain-profile duplex-notary 2>/dev/null | awk '/status:/ {print $2; exit}')
echo "final status: $STATUS"
if [ "$STATUS" != "Accepted" ]; then
  echo "Not accepted; fetching log:"
  xcrun notarytool log "$ID" --keychain-profile duplex-notary || true
  exit 1
fi

xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "--- Gatekeeper check ---"
spctl -a -vv "$APP"
echo "--- Release artifact ---"
shasum -a 256 "$ZIP"
