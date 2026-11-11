# Homebrew

Stats installs with `brew install --cask moifort/tap/minimal-stats`, from the
same tap as Dictate ([moifort/homebrew-tap](https://github.com/moifort/homebrew-tap)).
Nothing here is pushed to the tap by this repository: the two files are copied
there by hand, once, after the first release that carries `Stats.dmg`.

| File here | Goes to the tap as |
|---|---|
| [minimal-stats.rb](minimal-stats.rb) | `Casks/minimal-stats.rb` |
| [update-cask.yml](update-cask.yml) | `.github/workflows/update-cask.yml`, replacing Dictate's own |

The cask downloads `Stats.dmg` from the tag's release; the workflow then
follows every release hourly, as it does for Dictate, and rewrites `version`
and `sha256` (the `:no_check` placeholder included). The tap's README lists
both apps.

The token is `minimal-stats`, after the repository: homebrew/cask already has a
`stats` (another menu bar monitor, also installed as `Stats.app`), so the cask
declares the conflict.
