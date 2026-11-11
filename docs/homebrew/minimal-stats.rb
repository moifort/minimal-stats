# For moifort/homebrew-tap, next to dictate.rb: Casks/minimal-stats.rb.
# Not pushed from here (docs/homebrew/README.md).
#
# The token is minimal-stats, not stats: homebrew/cask's `stats` (exelban)
# installs another app also named Stats.app, and the two would overwrite
# each other in /Applications.
cask "minimal-stats" do
  version "1.12.0"
  sha256 :no_check # replaced by the tap's workflow on the first release with a disk image

  url "https://github.com/moifort/minimal-stats/releases/download/v#{version}/Stats.dmg"
  name "Stats"
  desc "Menu bar CPU, network, memory and disk charts"
  homepage "https://moifort.github.io/minimal-stats/"

  livecheck do
    url :url
    strategy :github_latest
  end

  # The app updates itself; `brew upgrade` leaves it alone unless --greedy.
  auto_updates true
  conflicts_with cask: "stats"
  depends_on arch: :arm64
  depends_on macos: ">= :tahoe"

  app "Stats.app"

  uninstall quit: "com.polyforms.stats"

  zap trash: [
    "~/Library/Preferences/com.polyforms.stats.plist",
    "~/Library/Preferences/com.stats.menubar.plist",
  ]
end
