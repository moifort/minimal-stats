# Stats

A lightweight macOS menu bar app that keeps essential system metrics always visible at a glance.

![Screenshot](screenshot.png)

## What it does

Stats lives in your menu bar and displays four widgets side by side:

- **Claude usage** — Three stacked dots (green / orange / red) that light up based on your Claude Code usage over the current 5-hour window (green below 50%, orange below 80%, red at 80% or above). The dots dim when the data is stale. This widget only appears if Claude Code is installed (`~/.claude`).
- **CPU usage** — A rolling line chart showing your processor activity over the last 5 minutes. Helps you quickly spot if something is consuming too many resources.
- **Network speed** — A mirrored chart showing upload speed on top and download speed on the bottom. Useful to monitor ongoing transfers or detect unexpected network activity.
- **Disk space** — A pie chart showing how much storage is used vs free on your main drive.

Clicking on the menu bar icon opens a popover with quick actions (Activity Monitor, Quit, Uninstall) and the app version. When Claude Code is installed, the popover also shows a **Claude Usage** section at the top with your 5-hour and weekly usage (percentage plus reset time), updated live while the popover is open. The app checks for updates automatically and shows an update button in the popover when a new version is available.

The app starts automatically at login and runs silently in the background with no dock icon or window.

## Install

### Download

1. Go to the [latest release](https://github.com/moifort/minimal-stats/releases/latest)
2. Download `Stats.app.zip`
3. Unzip and move `Stats.app` to your Applications folder
4. Since the app is not notarized, macOS will block it on first launch. Use one of these methods to open it:
   - **Right-click > Open** — right-click the app, select Open, then click Open in the dialog
   - **System Settings** — go to **Privacy & Security**, scroll down, and click **Open Anyway**
   - **Terminal** — run `xattr -cr /Applications/Stats.app` then open normally

### From source

Requires Xcode command line tools and macOS 26+.

```sh
git clone https://github.com/moifort/minimal-stats.git
cd minimal-stats
make install
```

This builds the app and copies it to `/Applications`.

## Update

The app checks for updates automatically once a day. When a new version is available, an update button appears in the popover. Clicking it shows the changelog and installs the update in-place — no need to re-download manually.

### Uninstall

Click the menu bar icon and select **Uninstall** — this removes the login item and moves the app to the Trash. You can also manually delete `Stats.app` from your Applications folder.
