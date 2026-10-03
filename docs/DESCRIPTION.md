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

  * `memorychip` icon + title `RAM N%` (used RAM / total, rounded)
  * Color reflects **memory pressure**

    * 🟢 / 🟠 / 🔴 (system pressure level): green normal, orange warning, red critical
    * Orange instead of yellow, since yellow is hard to read on a light menu bar. The menu bar and the popover share one color source, and orange is used for nothing else (not swap, growth hints or user colors)
    * Color is baked into a non-template icon and an attributed title, because the active display's menu bar renders template content and `contentTintColor` as monochrome
    * Title uses monospaced digits so the item width stays stable
    * Before the first sample the title reads `RAM --%` in a neutral color, instead of a green `RAM 0%`
  * Tooltip and VoiceOver label: `Memory 45%, pressure Normal`

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

  * launched by bundle id `com.apple.ActivityMonitor` through `NSWorkspace.urlForApplication(withBundleIdentifier:)` + `openApplication(at:configuration:)`, so it works regardless of the app name or language

* Right: **Open Context Menu** (same menu as right-clicking the menu bar item)

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

* Opening the popover switches to the active interval and samples right away, unless a sample started less than 2s ago; then the next one waits for the new interval.
* Closing the popover only switches to the idle interval. It never samples right away: the next sample runs one idle interval after the last one.
* `Refresh Now` samples immediately and pushes the next scheduled tick a full interval out.
* Only one sample runs at a time. `Refresh Now` (or any other immediate request) while a sample is running marks one follow-up sample instead of queueing another `top` run, so repeated clicks run `top` at most once more. A timer tick that lands during a running sample is skipped.
* `top` gets 6s before it is stopped (it takes about 1.4s on an idle machine). Its output is only read after both pipe readers finish.
* The `top` mem column can end with `+` or `-` (changed since the last sample); the marker is ignored, and values are clamped before converting to bytes.

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
  * user, "Others" or "Unattributed Used" slice focused: `<slice GB> / Used X`, which replaces the system summary while focused
  * "Free" slice focused: `<free GB> / Total Y`, since free memory is not part of used RAM
* Both texts stay on one line; the right side keeps priority, so a long user name truncates instead of the numbers
* Percentages (center label, VoiceOver value) are rounded to the nearest whole number, the same way as the total

### Interaction

* Hover on slice:

  * highlight slice (larger radius)
  * dim others
  * show slice info in the center label and in the info row (no floating tooltip):

    * user name (center label and info row)
    * memory (GB) (info row only)
    * % (center label only)

* Click slice:

  * only user slices can be selected; "Free", "Others" and "Unattributed Used" respond to hover only
  * set `selectedUser`
  * filter process list
  * show a "Clear Filter" button in the Top Users header (overlaid, so it does not shift the layout)

* Click again:

  * reset filter

* Auto reset: the filter clears itself when the selected user no longer has its own slice on the donut, either because it was merged into "Others" (< 2%) or because it has no processes left. This keeps the highlighted slice, center label and info row in sync with the filtered lists.

* VoiceOver: the donut is one element with a value listing every slice, plus actions to filter or clear each user

---

## 7. History Chart

### Status rows

* `Sampling`: current mode and interval, `Active (5s)` while the popover is open, `Idle (15s)` while it is closed
* `History Samples`: number of samples currently kept

### Metrics (In-memory)

* Total used RAM (primary plotted series)
* Selected user series (optional when a user is selected), scaled the same way as the donut so it matches the donut value and stays within the used RAM range
* Swap used + memory pressure shown as latest status badges (swap uses a neutral gray swatch)
* Used RAM chart segment color follows memory pressure at that sample:
  * Green = normal
  * Orange = warning
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

* In display order: `USER`, `PID`, `PROCESS`, `MEM`
* `PROCESS` is the executable name parsed from the command (quotes and escapes handled); hovering shows the full command line
* Memory (MB/GB)

### Footer

* The last sampling error (if any) shows in red below the list
* `Refresh Now` samples immediately (see §5.1 for how repeated clicks are coalesced)

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

* Applies to the menu bar title only: it is redrawn when used RAM moved by at least max(100 MB, 1% of total RAM) since the last redraw, or when the pressure level changed
* The popover updates on every sample (it is only sampled at the active interval while open)

---

### 11.3 Lazy load UI sections (not implemented)

* Not lazy: the popover is small and always shows every section, so the charts render with the popover. Nothing is rendered while the popover is closed.

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
* Up to 2 hints show as secondary caption lines in the History section, each with a swatch in the user's stable palette color, the same one its donut slice uses when it has its own slice (orange is reserved for the warning pressure level)

### 14.4 Alert system (dropped)

* No notifications: memory pressure is already shown by the menu bar color (🟢 / 🟠 / 🔴) and swap by the history badges.

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
