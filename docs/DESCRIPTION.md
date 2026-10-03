# 🧭 MemStats

Similar to iStat Menus/Stats, but focused on **memory monitoring** for multiple users.

A **menu bar macOS app** that shows:

* Runs continuously with **minimal CPU + memory overhead**
* Shows **Top Users (donut)** with swap/pressure status context
* Shows **Top Apps** (helper processes grouped into their parent app)
* Provides **short-term history (bounded window)**
* Show **Top processes (global or per selected user)**
* Has **native macOS UX (no custom-heavy UI nonsense)**

All inside **one popup window**.

---

## 1. Architecture Overview

### Stack

* UI: SwiftUI
* Menu bar: `NSStatusBar` + `NSPopover`
* Data layer:

  * `host_statistics64` → memory stats
    * Used RAM = App Memory (`internal_page_count - purgeable_count`) + Wired + Compressed, matching Activity Monitor "Memory Used"
    * Free (available) = Total - Used, so file cache counts as available
  * `sysctl` → total RAM
  * `sysctl kern.memorystatus_vm_pressure_level` → memory pressure level (1 normal, 2 warning, 4 critical), same source as Activity Monitor
    * `vm.memory_pressure` is not used: it is a reclaim activity counter, not a level
    * Fallback when the sysctl is unavailable: used/total ratio (≥ 75% warning, ≥ 90% critical)
  * `top -l 1 -o mem -stats pid,user,mem,command` → processes
  * `proc_pidpath(pid)` → executable path, used to group processes by app
* State:

  * `ObservableObject` (single source of truth)

---

## 2. UI Layout (Single Popup)

```text
┌──────────────────────────────────┐
│ [|||]                        [⚙] |
├──────────────────────────────────┤
│                                  │
│          Donut Chart             │
│        (% total usage)           │
│                                  │
├──────────────────────────────────┤
│        History Chart             │
├──────────────────────────────────┤
│        Top Apps                  │
│   (filtered by selected user)    │
├──────────────────────────────────┤
│        Top Processes             │
│   (filtered by selected user)    │
└──────────────────────────────────┘
```

---

## 3. Menu Bar

### Menu Bar Item

* Default:

  * Icon + % usage
  * Color reflects **memory pressure**

    * 🟢 / 🟡 / 🔴 (system pressure level)
    * Color is baked into a non-template icon and an attributed title, because the active display's menu bar renders template content and `contentTintColor` as monochrome
    * Title uses monospaced digits so the item width stays stable

* Click:
  → show **popover (main UI)**

* Right-click OR option-click:
  → show **context menu**

---

### Context Menu

```text
• Open at Login [✓]
• Show System Users [✓]
• About
• Quit
```

#### Implementation

* Use:

  * `SMAppService.mainApp.register()` → run at login
* Persist toggle via:

  * `UserDefaults`
* The checkmark always reflects `SMAppService.mainApp.status` (re-read after each change and each time the menu opens)
* If macOS needs approval (`.requiresApproval`), show an alert that opens System Settings > Login Items
* `Show System Users`: see §14.5

---

## 4. Popup UI

### Header

```text
[Activity Monitor Icon]          [Options Icon (gear icon)]
```

* Left: **Open Activity Monitor**

  * launch:

    ```bash
    open -a "Activity Monitor"
    ```

* Right: ***Open Context Menu**

---

## 5. Performance-first Design (VERY IMPORTANT)

This is where most people mess up.

### 5.1 Sampling Strategy

DO NOT run everything every second.

#### Suggested

```text
Memory stats: every 5s
Process list: every 5s
UI refresh: every 5s
```

👉 Process parsing is the expensive part (`top` snapshot + parse).

* Opening/closing the popover switches the interval. If a sample started less than 2s ago, the next one waits for the new interval instead of running immediately.
* `Refresh Now` samples immediately and pushes the next scheduled tick a full interval out.

---

### 5.2 Avoid heavy SwiftUI redraw

* Use:

  * `@Published` minimal fields
* Split ViewModels:

  * `MemoryVM`
  * `ProcessVM`

---

### 5.3 Limit process list size

* Runtime snapshot:

  * keep a broader process set (for example top 500 from `top`) to support donut/user aggregation accurately
* UI list:

  * show top 8 processes in the popover

---

### 5.4 Avoid constant grouping

* Cache last result
* Only recompute when process list updates
* Donut slices are built once per sample in `MemStatsAppState` and published only when they change, so hover never regroups processes

---

## 6. Donut Chart

### Data

* Each slice = **user total RAM**
* Last slice = **Free memory**
* If slice < 2% → merge into "Others"
* Memory not covered by sampled processes → "Unattributed Used"
* Sort users by memory DESC
* User colors are picked with a stable hash (FNV-1a) so a user keeps the same color across launches

### Center label

* Default: `% used RAM`
* Focused slice (hover or selected): slice label + `%`

### Info row (below the donut)

* Left: `All Users`, or the focused slice label
* Right:
  * nothing focused: system `Used X / Total (GB)`
  * slice focused: `<slice GB> / Used X`, which replaces the system summary while focused

### Interaction

* Hover on slice:

  * highlight slice (larger radius)
  * dim others
  * show slice info in the center label and in the info row (no floating tooltip):

    * user name (center label and info row)
    * memory (GB) (info row only)
    * % (center label only)

* Click slice:

  * set `selectedUser`
  * filter process list
  * show a "Clear Filter" button in the Top Users header (overlaid, so it does not shift the layout)

* Click again:

  * reset filter
  * If selectedUser no longer exists → auto reset selection

* VoiceOver: the donut is one element with a value listing every slice, plus actions to filter or clear each user

---

## 7. History Chart

### Metrics (In-memory)

* Total used RAM (primary plotted series)
* Selected user series (optional when a user is selected), scaled the same way as the donut so it matches the donut value and stays within the used RAM range
* Swap used + memory pressure shown as latest status badges
* Used RAM chart segment color follows memory pressure at that sample:
  * Green = normal
  * Yellow = warning
  * Red = critical
  * Each pair of adjacent samples is its own chart series, colored by the later sample's pressure, so the line never joins non-adjacent samples
  * The "Used" legend swatch uses the current pressure color
  * Legend items never wrap internally; when the row is full, only the overflowing items move to the next row
* Memory growth hints (see §14.3) are shown below the badges

### Time ranges

Don’t sample processes too frequently -> 5-10s interval

* Keep last:

```swift
let maxSamples = 120 // ~10 minutes if 5s interval
```

### Behavior

* Auto-drop old data
* No persistence (MVP)

👉 DO NOT store long-term → keeps app light

---

## 8. Process List

### Default

* Runtime keeps all sampled processes (all users by default)
* UI shows **Top 8 processes** in descending memory order

### When user selected

* Filter instantly (no recompute)

  ```swift
  process.user == selectedUser
  ```

### Columns

* Process name
* PID
* User
* Memory (MB/GB)

### Sorting

* Always by memory DESC

---

## 8.1 Top Apps

### Grouping

* Resolve executable path per PID with `proc_pidpath` (public libproc API)
* Path inside an `.app` bundle → group by the **outermost** `.app` bundle
  * e.g. `Visual Studio Code.app/.../Code Helper (Renderer).app/...` → `Visual Studio Code`
* Path outside any bundle → group by executable path (name = executable file name)
* Path not resolvable → fallback to the `top` command name

### Display

* Top 8 apps in descending memory order
* Columns: App, process count, Memory
* Hover an app row → tooltip with bundle/executable path
* When a user is selected, only that user's processes are aggregated
* Top Apps and Top Processes each have one section title with the row count; when filtered it reads `Top Apps · <user>`

---

## 9. Native macOS Design Rules

### Follow Apple style strictly

* Surfaces: solid semantic system colors instead of materials (project rule: solid colors, few gradients)

  * popover background: `windowBackgroundColor`
  * sections: native `GroupBox` on `controlBackgroundColor`
  * both adapt to light/dark mode automatically
* Font:

  * system text styles (`.headline`, `.footnote`, `.caption`)
  * live numbers use monospaced digits
* Spacing:

  * 8pt grid as the base, with small optical adjustments
* Icons: SF Symbols only, kept to a minimum (header buttons, menu bar)

### Avoid UI

* flashy gradients
* custom UI libraries
* over-animation

---

## 10. Charts Implementation

## Donut Chart

* Native `Charts` framework: `SectorMark` with `innerRadius: .ratio(0.62)`
* Each arc = user %
* Hover/click hit-testing is done in a `chartOverlay` by converting the pointer angle into a slice

---

## History Chart

* Use:

  * native `Charts` framework
* Primary plotted series:

  * total usage
  * selected user usage (optional)
* Swap + pressure:

  * shown as latest-value badges below chart for readability

---

## 11. Power & Resource Optimization

Critical for long-running app

### 11.1 Use background QoS

```swift
DispatchQueue.global(qos: .utility)
```

---

### 11.2 Debounce updates

* Only update UI if:

  * diff > threshold
  * threshold = max(100MB, 1–2% of total RAM)

---

### 11.3 Lazy load UI sections

* Chart:

  * render only when visible

---

## 12. Permissions & Stability

### Avoid API

* private APIs → App Store rejection

---

## 13. Project Structure

* Clean Architecture:

* MVVM pattern:

---

## 14. Additional Improvements (Recommended)

### 14.1 Idle mode optimization

* When popup closed:

  * reduce sampling:

    ```text
    Memory stats: every 15s
    Process list: every 15s
    UI refresh: every 15s
    ```

### 14.2 Smart highlighting (dropped)

* Not implemented: the donut already shows which user uses the most RAM (sorted, largest slice first).

### 14.3 Memory leak hint

* Detect per user (only users in the current snapshot):

  * continuous growth: memory rises on each of the last 12 samples, with at least 100 MB total growth
  * sudden jump: growth between the last two samples > max(500 MB, 5% of total RAM)
* A user missing from a snapshot loses its history, so coming back is not counted as a jump
* Up to 2 hints show as orange caption lines in the History section

### 14.4 Alert system (dropped)

* No notifications: memory pressure is already shown by the menu bar color (🟢 / 🟡 / 🔴) and swap by the history badges.

### 14.5 Show/Hide system users

System users can add noise, so they can be hidden with the `Show System Users` context menu option.

* System users: `root` and `_*`
* Default: shown, to match Activity Monitor's all-users view
* When hidden: excluded from the sampled processes, so they disappear from the donut, history (selected user series), Top Apps and Top Processes. Their memory is still part of the system "Used" total, so it shows up in the "Unattributed Used" donut slice.
* The choice persists via `UserDefaults` and triggers an immediate resample

---

## 🚀 Final Scope (Clean & Sharp)

### Core

* Menu bar app
* Donut (Top Users + free)
* Top apps (helpers grouped, filterable)
* Memory pressure + swap
* Short history (bounded) + memory growth hints
* Top processes (filterable)

### System

* Lightweight sampling
* Run at login
* Context menu (Open at Login, Show System Users, About, Quit)

### Note

* Process memory comes from `top` (`mem`) snapshot and is best-effort relative to Activity Monitor
* Memory pressure prefers system pressure signals from `sysctl` and only falls back to usage-ratio heuristic if unavailable
* Shared memory may still be accounted differently than Activity Monitor internals
* Values are indicative and optimized for lightweight monitoring
