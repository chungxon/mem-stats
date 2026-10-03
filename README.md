# MemStats

A lightweight macOS menu bar app focused on memory monitoring for multiple users: top users donut, top apps, top processes, memory pressure, swap and a short bounded history, all in one popover.

See [docs/DESCRIPTION.md](docs/DESCRIPTION.md) for the full feature and architecture description.

## Resource Usage

Snapshot from Activity Monitor (Debug build, running under Xcode `debugserver`, on 2026-10-03):

| Metric | Value | Assessment |
|---|---|---|
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
