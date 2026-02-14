# Stats

A lightweight macOS menu bar app that keeps essential system metrics always visible at a glance.

![Screenshot](screenshot.png)

## What it does

Stats lives in your menu bar and displays three widgets side by side:

- **CPU usage** — A rolling line chart showing your processor activity over the last 5 minutes. Helps you quickly spot if something is consuming too many resources.
- **Network speed** — A mirrored chart showing upload speed on top and download speed on the bottom. Useful to monitor ongoing transfers or detect unexpected network activity.
- **Disk space** — A pie chart showing how much storage is used vs free on your main drive.

Clicking on the menu bar icon opens **Activity Monitor** for a deeper look.

The app starts automatically at login and runs silently in the background with no dock icon or window.

## Install

### From source

Requires Xcode command line tools and macOS 14+.

```sh
git clone https://github.com/your-username/stats.git
cd stats
make install
```

This builds the app and copies it to `/Applications`.

Then open it from your Applications folder or with:

```sh
open /Applications/Stats.app
```

### Uninstall

Simply delete `Stats.app` from your Applications folder and remove it from Login Items in System Settings.
