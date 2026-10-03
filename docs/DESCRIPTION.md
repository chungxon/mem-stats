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
  * `sysctl` → total RAM
  * `sysctl vm.memory_pressure` + `kern.memorystatus_vm_pressure_level` → memory pressure level
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

* Click:
  → show **popover (main UI)**

* Right-click OR option-click:
  → show **context menu**

---

### Context Menu

```text
• Open at Login [✓]
• About
• Quit
```

#### Implementation

* Use:

  * `SMAppService.mainApp.register()` → run at login
* Persist toggle via:

  * `UserDefaults`

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

---

## 6. Donut Chart

### Data

* Each slice = **user total RAM**
* Last slice = **Free memory**
* If slice < 2% → merge into "Others"
* Sort users by memory DESC

### Center label

* Default: `% used RAM`
* On hover:
  → show tooltip: `Used / Total (GB)`

### Interaction

* Hover on slice:

  * highlight slice
  * dim others
  * show tooltip:

    * user name
    * memory (GB)
    * %

* Click slice:

  * set `selectedUser`
  * filter process list

* Click again:

  * reset filter
  * If selectedUser no longer exists → auto reset selection

---

## 7. History Chart

### Metrics (In-memory)

* Total used RAM (primary plotted series)
* Selected user series (optional when a user is selected)
* Swap used + memory pressure shown as latest status badges
* Used RAM chart segment color follows memory pressure at that sample:
  * Green = normal
  * Yellow = warning
  * Red = critical

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

---

## 9. Native macOS Design Rules

### Follow Apple style strictly

* Use:

  * `.ultraThinMaterial`
  * `.sidebar`
  * `.regularMaterial`
* Font:

  * `.system(.body)`
* Spacing:

  * 8pt grid

### Avoid UI

* flashy gradients
* custom UI libraries
* over-animation

---

## 10. Charts Implementation

## Donut Chart

* SwiftUI:

  * `Canvas` OR
  * custom `Shape`
* Each arc = user %

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

### 14.2 Smart highlighting

* Highlight:

  * user using >50% RAM

### 14.3 Memory leak hint

* Detect:

  * continuous growth over N samples
  * detect sudden jump per user

### 14.4 Alert system

* Notify when:

  * pressure = red
  * swap > threshold

### 14.5 Exclude system users

Don’t show ALL users in history chart to avoid noise.

* default hidden:
  * _*
  * root (optional)

---

## 🚀 Final Scope (Clean & Sharp)

### Core

* Menu bar app
* Donut (Top Users + free)
* Top apps (helpers grouped, filterable)
* Memory pressure + swap
* Short history (bounded)
* Top processes (filterable)

### System

* Lightweight sampling
* Run at login
* Context menu

### Note

* Process memory comes from `top` (`mem`) snapshot and is best-effort relative to Activity Monitor
* Memory pressure prefers system pressure signals from `sysctl` and only falls back to usage-ratio heuristic if unavailable
* Shared memory may still be accounted differently than Activity Monitor internals
* Values are indicative and optimized for lightweight monitoring
