# MemStats

A lightweight macOS menu bar app focused on memory monitoring for multiple users: top users donut, top apps, top processes, memory pressure, swap and a short bounded history, all in one popover.

See [docs/DESCRIPTION.md](docs/DESCRIPTION.md) for the full feature and architecture description.

## Requirements

* macOS 14.0 (Sonoma) or later
* Apple Silicon or Intel Mac

## Install

### GitHub Releases

1. Download `MemStats-<version>.zip` from [GitHub Releases](https://github.com/chungxon/ram-stats/releases).
2. Unzip it and drag `MemStats.app` into `/Applications`.
3. Open it once as described in [First launch](#first-launch).

### Homebrew

```bash
brew install --cask chungxon/tap/memstats
```

MemStats is distributed outside the Mac App Store, because it needs the App Sandbox turned off to run `top` and read processes of other users.

## First Launch

MemStats is signed ad hoc and not notarized yet, so macOS blocks it the first time you open it. Use one of these:

* Open the app once, then go to System Settings > Privacy & Security and click "Open Anyway" next to the MemStats message.
* Or remove the quarantine flag in Terminal:

  ```bash
  xattr -dr com.apple.quarantine /Applications/MemStats.app
  ```

After that, MemStats opens normally. It lives in the menu bar only (no Dock icon). Right-click (or Option-click) the menu bar item for Open at Login, Show System Users, About and Quit.

## Update

There is no automatic update check.

* GitHub Releases: compare the version in About (menu bar item > right-click > About) with the latest version on [GitHub Releases](https://github.com/chungxon/ram-stats/releases), then download and replace the app.
* Homebrew:

  ```bash
  brew upgrade --cask memstats
  ```

## Build From Source

Requires Xcode 26 or later.

```bash
git clone https://github.com/chungxon/ram-stats.git
cd ram-stats
xcodebuild -project MemStats/MemStats.xcodeproj -scheme MemStats -configuration Release -derivedDataPath build build
open build/Build/Products/Release/MemStats.app
```

Run the unit tests:

```bash
xcodebuild -project MemStats/MemStats.xcodeproj -scheme MemStats -destination 'platform=macOS' test
```

## Resource Usage

Snapshot from Activity Monitor (Debug build, running under Xcode `debugserver`, on 2026-10-03):

| Metric | Value | Assessment |
| --- | --- | --- |
| Real Memory | 45.1 MB | Normal. A minimal SwiftUI + AppKit app usually sits at 30 to 60 MB. This is all resident pages, so it also includes clean file-backed pages (framework code, fonts, assets) and graphics memory, which is why it is larger than Private + Shared |
| Private Memory | 4.9 MB | Very low. This is the memory the app allocates itself and the most meaningful number |
| Shared Memory | 12.8 MB | Normal. Frameworks shared with other processes |
| Virtual Memory | 415.44 GB | Not a concern. Reserved address space (shared cache, GPU, malloc zones), not physical RAM. Typical for any app on Apple Silicon |
| % CPU | 0.20 | Good for an app that samples periodically |
| Recent hangs | 0 | Good |

Notes:

* A Release build is expected to be slightly lighter, since there is no debugger attached and optimizations are enabled.
* One snapshot is not enough to rule out leaks. To check long-running behavior:
  1. Leave the app running for 30 to 60 minutes and confirm Real/Private Memory stays stable.
  2. Open and close the popover several times and confirm memory returns to its previous level.
  3. If memory keeps growing, use Instruments (Leaks / Allocations) or the Xcode Memory Graph Debugger.
