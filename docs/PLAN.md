# Ram Stats - Project Plan

## Goal

Build a lightweight macOS menu bar app that monitors RAM usage by user, memory pressure, swap, short history, and top processes in a single native popover UI.

## Working Rules

- Scope first, optimize early for low overhead.
- Keep native macOS UI style and solid colors.
- After each task: stop, send update, and wait for review before continuing.

## High-Level Milestones

1. Project scaffold and menu bar shell
2. System data collection layer
3. State management and sampling engine
4. Popup UI foundation
5. Charting and interactions
6. Context menu and app lifecycle features
7. Performance hardening
8. QA, lint, and release prep

## Task Breakdown

### Task 1 - Scaffold Menu Bar App

Objective:

- Create macOS SwiftUI app skeleton with `NSStatusBar` item and `NSPopover`.
- Open popover on click and context menu on right-click or option-click.

Deliverables:

- Basic runnable app shell
- Menu bar icon + placeholder percent text
- Empty popover container view

Acceptance criteria:

- App launches without dock icon (menu bar utility mode)
- Left click opens popover
- Right click shows context menu

Task 1 TODO:

- [x] Switch SwiftUI app entry to menu bar lifecycle (`NSApplicationDelegateAdaptor`)
- [x] Add `NSStatusBar` item with placeholder usage text
- [x] Add `NSPopover` container and connect left-click toggle behavior
- [x] Add context menu on right-click or option-click
- [x] Set app utility mode (hide dock icon)

Review gate:

- Stop and request review before Task 2.

---

### Task 2 - Build Memory and Process Data Services

Objective:

- Implement data collectors:
  - `host_statistics64` for memory stats
  - `sysctl` for total RAM
  - `ps -axo user,pid,rss,command` for process snapshots

Deliverables:

- `MemoryStatsService`
- `ProcessSnapshotService`
- Parsed models for memory/process entities

Acceptance criteria:

- Services return valid values on local machine
- Process list sorted by RSS desc
- Result capped to top 8 processes

Task 2 TODO:

- [x] Add memory model and process model for service outputs
- [x] Implement `MemoryStatsService` using `host_statistics64`, `sysctl hw.memsize`, and `vm.swapusage`
- [x] Implement `ProcessSnapshotService` using `ps -axo user,pid,rss,command`
- [x] Ensure process snapshots are sorted by RSS descending
- [x] Cap process snapshots to top 8 entries
- [x] Add parser/service tests for core acceptance behavior

Review gate:

- Stop and request review before Task 3.

---

### Task 3 - Implement MVVM State and Sampling

Objective:

- Create `MemoryVM`, `ProcessVM`, and shared app state.
- Add periodic sampling with lightweight scheduling.

Deliverables:

- 5s sampling while popover is open
- 15s sampling in idle mode (popover closed)
- Bounded history buffer (`maxSamples = 120`)

Acceptance criteria:

- UI-bound state updates correctly
- Old samples are removed automatically
- No aggressive redraw loops

Task 3 TODO:

- [x] Add `MemoryVM` with bounded history buffer (`maxSamples = 120`)
- [x] Add `ProcessVM` for top-process state and user selection consistency
- [x] Add shared `RamStatsAppState` to coordinate sampling and services
- [x] Implement 5s sampling when popover is open
- [x] Implement 15s sampling when popover is closed
- [x] Wire popover open/close lifecycle to sampling mode
- [x] Add tests for bounded history and sampling interval behavior

Review gate:

- Stop and request review before Task 4.

---

### Task 4 - Build Popup Layout (MVP)

Objective:

- Implement single popup layout with three main sections:
  - Header
  - Donut chart area
  - History + top process area

Deliverables:

- Header with actions:
  - Open Activity Monitor
  - Open options/context menu
- Native spacing and typography

Acceptance criteria:

- Layout is stable on common macOS scaling
- Uses solid colors and native material style
- No heavy custom visual effects

Task 4 TODO:

- [x] Build popup header with native typography and balanced spacing
- [x] Add header action to open Activity Monitor
- [x] Add header action to open options/context menu
- [x] Add three-section popup structure: RAM area, history area, top process area
- [x] Use native solid-color surfaces (`windowBackground`/`controlBackground`) without heavy effects
- [x] Keep layout stable for common macOS scaling in fixed popover bounds

Review gate:

- Stop and request review before Task 5.

---

### Task 5 - Donut and Process Filtering Interactions

Objective:

- Render RAM-by-user donut with free-memory slice.
- Add interactive selection/filtering behavior.

Deliverables:

- User slices sorted by memory desc
- Merge tiny slices (<2%) into "Others"
- Click slice to set/reset `selectedUser`
- Process list filtered by selected user

Acceptance criteria:

- Selection and reset behavior works reliably
- If selected user disappears, state auto-resets
- Process filtering is instant (no full recompute)

Task 5 TODO:

- [x] Build RAM-by-user donut data pipeline from process snapshots plus free-memory slice
- [x] Sort user slices by memory descending
- [x] Merge tiny slices (`<2%`) into `Others`
- [x] Keep `Free` as final slice in donut
- [x] Add slice click behavior to set/reset `selectedUser`
- [x] Filter process list by selected user in real time
- [x] Auto-reset selection when selected user disappears from slices
- [x] Add tests for donut merge/selection mapping and process filtering behavior

Review gate:

- Stop and request review before Task 6.

---

### Task 6 - History Chart and Pressure/Swap Tracking

Objective:

- Plot short-term memory metrics using native Charts.

Deliverables:

- History lines for:
  - Total used RAM
  - Swap used
  - Memory pressure
- Optional selected-user history overlay

Acceptance criteria:

- Chart updates only on new sample ticks
- History remains bounded in memory
- Data remains readable and consistent

Task 6 TODO:

- [x] Replace history placeholder with native `Charts` line chart
- [x] Plot total used RAM series from bounded memory history
- [x] Plot swap-used series from bounded memory history
- [x] Plot memory-pressure series with consistent scaling for readability
- [x] Add optional selected-user history overlay when a user is selected
- [x] Keep chart updates driven by sampling ticks only (history append path)
- [x] Add tests for selected-user history tracking with bounded samples

Review gate:

- Stop and request review before Task 7.

---

### Task 7 - Context Menu, Login Item, and App Options

Objective:

- Add utility actions and lifecycle features.

Deliverables:

- Context menu entries:
  - Open at Login
  - About
  - Quit
- Open at login integration via `SMAppService.mainApp.register()`
- Toggle persistence in `UserDefaults`

Acceptance criteria:

- Toggle state persists after relaunch
- App can be quit cleanly from menu
- About action is available

Task 7 TODO:

- [x] Add context menu entries: `Open at Login`, `About`, `Quit`
- [x] Implement login-item integration using `SMAppService.mainApp.register()/unregister()`
- [x] Persist `Open at Login` state in `UserDefaults`
- [x] Sync persisted state from system login-item status on launch
- [x] Keep `Quit` action terminating app cleanly
- [x] Keep `About` action available from context menu
- [x] Add tests for login-item state sync and toggle persistence

Review gate:

- Stop and request review before Task 8.

---

### Task 8 - Performance Hardening and Final QA

Objective:

- Minimize overhead and finalize release readiness.

Deliverables:

- Debounced UI updates with threshold:
  - `max(100MB, 1-2% total RAM)`
- Background sampling on utility QoS
- System user filtering defaults (`_*`, optional `root`)
- Final lint/build/test verification

Acceptance criteria:

- Stable runtime with low CPU impact
- No obvious redraw/perf spikes
- Lint and test commands pass

Task 8 TODO:

- [x] Add status-item debounce threshold using `max(100MB, 1% total RAM)` to reduce unnecessary UI churn
- [x] Keep sampling work on utility QoS queue
- [x] Filter system users by default in process snapshots (`_*`, and `root` excluded by default)
- [x] Preserve optional root inclusion path for future toggles/config
- [x] Extend tests for new process filtering behavior
- [x] Run lint on all changed files
- [x] Run build verification
- [x] Run test command verification (environment still sandbox-limited)

Review gate:

- Stop and request final review and sign-off.

## Task Tracking Checklist

- [x] Task 1 - Scaffold Menu Bar App
- [x] Task 2 - Build Memory and Process Data Services
- [x] Task 3 - Implement MVVM State and Sampling
- [x] Task 4 - Build Popup Layout (MVP)
- [x] Task 5 - Donut and Process Filtering Interactions
- [x] Task 6 - History Chart and Pressure/Swap Tracking
- [x] Task 7 - Context Menu, Login Item, and App Options
- [x] Task 8 - Performance Hardening and Final QA
