#!/bin/bash
# Builds Stats.app from the Swift package: the release binary, Info.plist with
# the version numbers, the icon. Left with the linker's ad-hoc signature: the
# caller signs (Makefile, release workflow, scripts/build-app-store.sh).
#
#   scripts/build-app.sh [--app-store] [output folder]     # default: build
#   MARKETING=1.12.0 BUILD=245 scripts/build-app.sh
#
# --app-store compiles the APP_STORE flag (Sources/Stats/Distribution.swift)
# into its own scratch folder, so switching flavour never rebuilds the other,
# and adds the compiled asset catalog the Mac App Store expects.
#
# MARKETING defaults to the latest v* tag, BUILD to the commit count: each
# build carries a higher number than the one before, which the App Store
# requires.
set -euo pipefail
cd "$(dirname "$0")/.."

FLAVOUR=developer-id
if [ "${1:-}" = "--app-store" ]; then
  FLAVOUR=app-store
  shift
fi
OUT="${1:-build}"
MARKETING="${MARKETING:-$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null | sed 's/^v//' || true)}"
MARKETING="${MARKETING:-0.0.0}"
BUILD="${BUILD:-$(git rev-list --count HEAD)}"

SWIFT_ARGS=(-c release)
if [ "$FLAVOUR" = app-store ]; then
  SWIFT_ARGS+=(--scratch-path .build/app-store -Xswiftc -DAPP_STORE)
fi

echo "Stats $MARKETING ($BUILD), $FLAVOUR build"
swift build "${SWIFT_ARGS[@]}"
BINARY="$(swift build "${SWIFT_ARGS[@]}" --show-bin-path)/Stats"

APP="$OUT/Stats.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Stats"
cp Sources/Stats/Info.plist "$APP/Contents/Info.plist"
cp Sources/Stats/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"

if [ "$FLAVOUR" = app-store ]; then
  # The store reads the icon from a compiled asset catalog (CFBundleIconName);
  # the .icns stays for older readers. Built from the .icns, the one source.
  WORK="$(mktemp -d -t stats-assets)"
  trap 'rm -rf "$WORK"' EXIT
  ICONSET="$WORK/Assets.xcassets/AppIcon.appiconset"
  mkdir -p "$ICONSET"
  iconutil -c iconset Sources/Stats/AppIcon.icns -o "$WORK/AppIcon.iconset"
  IMAGES=""
  for SIZE in 16 32 128 256 512; do
    for SCALE in 1 2; do
      SUFFIX=""; [ "$SCALE" = 2 ] && SUFFIX="@2x"
      FILE="icon_${SIZE}x${SIZE}${SUFFIX}.png"
      cp "$WORK/AppIcon.iconset/$FILE" "$ICONSET/$FILE"
      IMAGES="$IMAGES{\"idiom\":\"mac\",\"size\":\"${SIZE}x${SIZE}\",\"scale\":\"${SCALE}x\",\"filename\":\"$FILE\"},"
    done
  done
  printf '{"images":[%s],"info":{"author":"xcode","version":1}}\n' "${IMAGES%,}" > "$ICONSET/Contents.json"
  printf '{"info":{"author":"xcode","version":1}}\n' > "$WORK/Assets.xcassets/Contents.json"
  MINIMUM=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$APP/Contents/Info.plist")
  xcrun actool --compile "$APP/Contents/Resources" --platform macosx \
    --minimum-deployment-target "$MINIMUM" --app-icon AppIcon \
    --output-partial-info-plist "$WORK/partial.plist" \
    --errors --warnings "$WORK/Assets.xcassets" >/dev/null
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "$APP/Contents/Info.plist"
fi

echo "Built $APP"
