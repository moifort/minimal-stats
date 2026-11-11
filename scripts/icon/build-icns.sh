#!/bin/bash
# Renders the app icon and writes Sources/Stats/AppIcon.icns, every size
# macOS asks for, from scripts/icon/render-icon.swift.
#
#   scripts/icon/build-icns.sh [dark|light|widgets]
set -euo pipefail
cd "$(dirname "$0")/../.."

WORK="$(mktemp -d -t stats-icon)"
trap 'rm -rf "$WORK"' EXIT
swift scripts/icon/render-icon.swift "$WORK/icon.png" "${1:-dark}"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" "$WORK/icon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  sips -z $((SIZE * 2)) $((SIZE * 2)) "$WORK/icon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Sources/Stats/AppIcon.icns
echo "Wrote Sources/Stats/AppIcon.icns"
