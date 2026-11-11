# Mac App Store

Stats ships twice, like Dictate: the Developer ID build from GitHub Releases
(and Homebrew), and a sandboxed build on the Mac App Store. Both carry the
identifier `com.polyforms.stats`.

## What differs in the App Store build

`scripts/build-app-store.sh` compiles the `APP_STORE` flag
(`swift build -Xswiftc -DAPP_STORE`, in its own scratch folder) and signs with
`Sources/Stats/StatsAppStore.entitlements`: the App Sandbox, and
`network.client` for `nettop` (below). `Distribution` in
[Sources/Stats/Distribution.swift](../Sources/Stats/Distribution.swift) then
hides what the sandbox refuses.

Measured on 2026-11-11, macOS 27.2, in a sandboxed build (an ad-hoc signed
probe with the same entitlements running every call Stats makes, then the
App Store build itself, watched for `nettop` children and sandbox denials):

| What Stats does | Sandboxed | In the App Store build |
|---|---|---|
| CPU, memory: `host_statistics`, `host_statistics64` | works | menu bar widget and popover figure |
| Network speed: `sysctl(NET_RT_IFLIST2)` | works | widget and figure |
| Disk: volume capacity of `/` | works | widget and figure |
| Process list: `/bin/ps` (setuid root) | **refused** (`Operation not permitted` at launch; `top`, also setuid, too) | replaced by `sysctl(KERN_PROC_ALL)`: names, parents, owners, no figures |
| Per-process CPU and memory: libproc | **refused** (`proc_listallpids` returns 0) | CPU and Memory tabs hidden |
| Per-process disk reads and writes: `proc_pid_rusage` | **refused** for every process but Stats itself (1 of 549 of the user's, `EPERM`) | Disk tab hidden, not sampled |
| Per-process network: `/usr/bin/nettop` (not setuid) | works with `network.client`, **exits 70 without** | Network tab kept, grouped by app |
| Quit another process: `kill`, `NSRunningApplication.terminate` | **refused** (`EPERM`, `false`) | no quit buttons |
| Updater: write next to the app bundle | **refused** | off: the App Store installs updates |
| Uninstaller: move the app to the Trash | **refused** | off: deleting the app removes its container |
| Open Activity Monitor (Launch Services) | found (`urlForApplication`); opening it not exercised, Launch Services is open to sandboxed apps | kept |
| Open at login (`SMAppService.mainApp`) | works | opt-in item in the right-click menu (guideline 2.4.5(iii)), never automatic |

The popover keeps its style: the same sections, the tab picker with its one
remaining tab (Network), the Activity Monitor and Quit buttons. The
right-click menu offers "Open at Login" instead of "Uninstall…".

### Is it enough for App Review?

What remains is the four live widgets, the popover's figures and the apps
that used the network over the last five minutes. That is a complete, if
small, menu bar monitor, which the store has many of; guideline 4.2
(minimum functionality) is a risk but not a likely refusal. Two things to
expect from a reviewer:

- the `network.client` entitlement on an app that connects to nothing: the
  review notes (`scripts/app-store/review.rb`) explain that `nettop` needs it;
- running `/usr/bin/nettop` as a child process: allowed by the sandbox (the
  child inherits it), but if App Review objects, the Network tab goes too and
  the build is down to widgets and figures, which would then be thin for 4.2.

## Building

```bash
scripts/build-app-store.sh            # build/app-store/Stats.pkg
scripts/build-app-store.sh --upload   # and upload it to App Store Connect
make app-store VERSION=1.12.0         # the same, with a version
```

Dictate archives an Xcode configuration and lets `xcodebuild -exportArchive`
sign it. Stats is a Swift package without an Xcode project, and SwiftPM cannot
archive an app, so the script does what the export does: it embeds the
provisioning profile, signs the bundle with the sandbox entitlements plus the
application and team identifiers read from the profile, and builds the
installer with `productbuild`. It also compiles an asset catalog from
`AppIcon.icns`, as the store expects.

Signing needs `MAS_PROFILE`, the path to a Mac App Store profile for
`com.polyforms.stats`, and the "Apple Distribution" and "3rd Party Mac
Developer Installer" identities in a keychain (both are in this Mac's login
keychain). `ruby scripts/app-store/profile.rb` registers the identifier and
creates the profile through the API, saving it to
`build/app-store/Stats.provisionprofile`:

```bash
MAS_PROFILE=build/app-store/Stats.provisionprofile scripts/build-app-store.sh
```

Without `MAS_PROFILE` the app is signed ad hoc, sandboxed, to run locally:
`open build/app-store/Stats.app`. The first `productbuild` may ask for
keychain access to the installer key: answer "Always Allow".

## Automatic upload on each release

Every `v*` tag runs the `app-store` job of the release workflow next to the
Developer ID build: it builds the App Store flavour, signs it with the
secrets below and uploads the package with `altool`. A manual run builds and
signs but does not upload, and a tag only uploads once the repository
variable `APP_STORE_UPLOAD` is `true`. Until the secrets exist, the job only
prints a notice and the GitHub release goes out alone.

| Secret | Content |
|---|---|
| `MAS_DIST_CERT_P12`, `MAS_DIST_CERT_PASSWORD` | "Apple Distribution" identity exported from Keychain Access as .p12, base64 |
| `MAS_INSTALLER_CERT_P12`, `MAS_INSTALLER_CERT_PASSWORD` | "3rd Party Mac Developer Installer" identity as .p12, base64 |
| `MAS_PROVISION_PROFILE` | the profile from `profile.rb`, base64 |
| `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` | App Store Connect API key, shared with notarization |

```bash
base64 -i distribution.p12 | gh secret set MAS_DIST_CERT_P12
base64 -i build/app-store/Stats.provisionprofile | gh secret set MAS_PROVISION_PROFILE
gh variable set APP_STORE_UPLOAD --body true
```

## App Store Connect

`scripts/app-store/` holds the same scripts as Dictate's, for
`com.polyforms.stats` (`asc.rb`):

- `profile.rb`: identifier and provisioning profile (new: Dictate's Xcode does it);
- `listing.rb`: name, subtitle, description, keywords, promotional text,
  what's new, URLs, categories (Utilities, Developer Tools), age rating,
  copyright, free price, every territory, for each locale of `listing.yml`
  (English and French, the app's two languages);
- `review.rb`: contact copied from Shiori, notes for the reviewer;
- `version.rb`: the App Store version takes the tag's number (release workflow);
- `screenshots.rb`: uploads `docs/app-store-screenshots/<locale>/*.jpg`;
- `submit.rb <version> <build>`: attaches the build and submits it.

The app record is "Minimal Stats" (`com.polyforms.stats`, SKU
`polyforms-stats-macos`, Apple ID 6833477318, primary language English),
created on 2026-11-11: "Minimal Stats" was free, and is `listing.rb`'s
default name (`APP_STORE_NAME` overrides it, 30 characters at most). The app
keeps "Stats" in the menu bar and in Applications. Its Mac App Store profile,
"Stats Mac App Store", expires on 2027-07-15.

Done on 2026-11-11: identifier registered, record created, `profile.rb`,
`listing.rb` (en-US, fr-FR, Utilities and Developer Tools, no age rating,
free, 175 territories), `review.rb`, and App Privacy published as Data Not
Collected. A package built locally with the profile passed
`altool --validate-app` with no error; nothing was uploaded. One screenshot
per locale is uploaded (`screenshots.rb`).

The screenshots, `docs/app-store-screenshots/<locale>/*.jpg`, are rendered
by `scripts/app-store/render-screenshots.swift` from two captures of the App
Store build itself: the widgets (`StatusBarView` drawn in a dark
`NSHostingView`) and the popover window (`screencapture -l`), opened in
English and in French (`-AppleLanguages "(fr)"`).

### Left to do, in order

1. **Secrets and variable** above, then **push a tag**: the release uploads
   the build, then `ruby scripts/app-store/submit.rb <version> <build>`
   submits it for review.

Once the app is live, set `APP_STORE_URL` in `site/main.js` to
`https://apps.apple.com/app/id6833477318?mt=12`: the site shows the App
Store badge only then. Add it to the README too.
