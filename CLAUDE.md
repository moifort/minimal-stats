# Stats - Claude Code Project Guide

## Project

macOS menu bar app (Swift/SwiftUI) displaying system stats (CPU, network, disk). Built with Swift Package Manager.

## Build

```bash
make clean && make bundle VERSION=x.y.z   # Build app bundle
make sign VERSION=x.y.z                   # Build + sign
make install VERSION=x.y.z               # Build + sign + install to /Applications
```

Always pass `VERSION=x.y.z` — the Makefile defaults to `0.0.0`.

## Release Process

1. **Bump version** in `Sources/Stats/Info.plist` (CFBundleVersion + CFBundleShortVersionString)
2. **Check existing releases** with `gh release list` to pick the right version number (must be higher than all existing releases)
3. **Commit** the version bump
4. **Build, sign, zip**:
   ```bash
   make clean && make sign VERSION=x.y.z
   zip -r Stats.app.zip Stats.app
   ```
5. **Tag and push**:
   ```bash
   git tag vx.y.z
   git push origin main
   git push origin vx.y.z
   ```
6. **Create GitHub release**:
   ```bash
   gh release create vx.y.z Stats.app.zip --title "vx.y.z" --notes "release notes here"
   ```
7. **Install locally**: `make install VERSION=x.y.z`

## Key Files

- `Sources/Stats/` — all source code
- `Sources/Stats/Info.plist` — app metadata and version
- `Makefile` — build, sign, install targets
- `screenshot.png` — README screenshot
