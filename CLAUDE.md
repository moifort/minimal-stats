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

A `v*` tag releases: `.github/workflows/release.yml` tests, builds, signs with
Developer ID, notarizes, publishes `Stats.dmg` and `Stats.app.zip` on the
GitHub release, and uploads the Mac App Store build once its secrets exist
(`docs/app-store.md`). Nothing is built or uploaded by hand.

1. **Pick the version** with `gh release list`: higher than every release.
2. **Bump** `CFBundleShortVersionString` and `CFBundleVersion` in
   `Sources/Stats/Info.plist` (the version `swift run` shows; the release
   build takes the tag's number and the commit count) and commit
   `chore: bump version to x.y.z`.
3. **Tag with the notes**: the annotation is the release notes, which the
   updater shows as the changelog.
   ```bash
   git tag -a vx.y.z -m "What changes in this version…"
   git push origin main
   git push origin vx.y.z
   ```
4. **Watch the run**: `gh run watch`. Without `DEVELOPER_ID_P12` a tag fails
   on purpose rather than publish an unsigned build.
5. **Install locally**: `make install VERSION=x.y.z`.

Keep the asset names: every installed copy up to 1.11 downloads the
release's only `.zip`, and the site links to
`releases/latest/download/Stats.dmg`. The Homebrew cask
(`docs/homebrew`) follows the latest release on its own.

## Distribution

- **Identifier** `com.polyforms.stats` for both builds (`AppIdentity`); the
  updater accepts an update from the old `com.stats.menubar`.
- **Mac App Store build**: `scripts/build-app-store.sh`, `APP_STORE` flag,
  `Distribution` hides what the sandbox refuses (`docs/app-store.md`).
- **Disk image**: `scripts/build-dmg.sh`, `make dmg VERSION=x.y.z`.
- **Icon**: `scripts/icon/build-icns.sh` writes `AppIcon.icns`.
- **Site**: `site/`, published by `.github/workflows/pages.yml`. Texts in
  French in `index.html`, the 24 other languages in
  `scripts/site/translations_*.py`, then `python3 scripts/site/build-i18n.py`.

## Key Files

- `Sources/Stats/` — all source code
- `Sources/Stats/Info.plist` — app metadata and version
- `Makefile` — build, sign, install, dmg, app-store targets
- `scripts/` — app bundle, disk image, App Store build and Connect scripts, icon, site
- `.github/workflows/` — tests on every push, release on tags, Pages
- `screenshot.png` — README screenshot
