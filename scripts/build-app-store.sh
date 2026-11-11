#!/bin/bash
# The Mac App Store build: the sandboxed APP_STORE flavour
# (Sources/Stats/Distribution.swift), signed for distribution and packaged as
# an installer, or uploaded to App Store Connect.
#
#   scripts/build-app-store.sh            # build/app-store/Stats.pkg
#   scripts/build-app-store.sh --upload   # the same, then upload it
#
# Dictate archives an Xcode configuration and lets `xcodebuild -exportArchive`
# sign and package it. Stats is a Swift package with no Xcode project, and
# SwiftPM cannot archive an app, so this script does by hand what the export
# does: embed the provisioning profile, sign the bundle with its entitlements
# plus the application and team identifiers the profile grants, and build the
# installer package with productbuild.
#
# Signing needs, like Dictate's release workflow:
# - MAS_PROFILE: path to a Mac App Store provisioning profile for
#   com.polyforms.stats (developer portal: Profiles, +, Mac App Store Connect);
# - the "Apple Distribution" and "3rd Party Mac Developer Installer"
#   identities in a keychain.
# Without MAS_PROFILE the app is signed ad hoc with the sandbox entitlements:
# enough to run the sandboxed build locally, not to upload it.
#
# Uploading reads the App Store Connect API key from ASC_KEY_ID and
# ASC_ISSUER_ID, its .p8 in ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8.
#
# Version and build number follow the Developer ID release: the latest tag and
# the commit count (scripts/build-app.sh), so each upload carries a higher
# build number.
set -euo pipefail

cd "$(dirname "$0")/.."

UPLOAD=false
[ "${1:-}" = "--upload" ] && UPLOAD=true

OUT=build/app-store
APP="$OUT/Stats.app"
PKG="$OUT/Stats.pkg"
ENTITLEMENTS=Sources/Stats/StatsAppStore.entitlements
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Sources/Stats/Info.plist)

rm -rf "$OUT"
mkdir -p "$OUT"
scripts/build-app.sh --app-store "$OUT"

if [ -z "${MAS_PROFILE:-}" ]; then
  if [ "$UPLOAD" = true ]; then
    echo "MAS_PROFILE is not set: nothing signed for the App Store to upload" >&2
    exit 1
  fi
  codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign - "$APP"
  codesign --verify --strict --verbose=2 "$APP"
  echo "MAS_PROFILE is not set: $APP is signed ad hoc, sandboxed, for local runs only (no package)"
  exit 0
fi

WORK="$(mktemp -d -t stats-mas)"
trap 'rm -rf "$WORK"' EXIT

# The profile names the team and the application identifier the signature
# must claim: read them rather than repeat them here.
security cms -D -i "$MAS_PROFILE" > "$WORK/profile.plist"
TEAM_ID=$(/usr/libexec/PlistBuddy -c "Print :TeamIdentifier:0" "$WORK/profile.plist")
APP_ID=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.application-identifier" "$WORK/profile.plist")
if [ "$APP_ID" != "$TEAM_ID.$BUNDLE_ID" ]; then
  echo "The profile is for $APP_ID, not $TEAM_ID.$BUNDLE_ID" >&2
  exit 1
fi
cp "$MAS_PROFILE" "$APP/Contents/embedded.provisionprofile"

cp "$ENTITLEMENTS" "$WORK/entitlements.plist"
/usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $APP_ID" "$WORK/entitlements.plist"
/usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$WORK/entitlements.plist"

codesign --force --options runtime --timestamp \
  --entitlements "$WORK/entitlements.plist" \
  --sign "Apple Distribution" "$APP"
codesign --verify --strict --deep --verbose=2 "$APP"

productbuild --component "$APP" /Applications \
  --sign "3rd Party Mac Developer Installer" "$PKG"
pkgutil --check-signature "$PKG"
echo "Built $PKG"

if [ "$UPLOAD" = true ]; then
  xcrun altool --upload-app --type macos --file "$PKG" \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  echo "Uploaded: the build appears in App Store Connect once processed."
fi
