# 🧭 Ram Stats

Similar to iStat Menus/Stats, but focused on **memory monitoring** for multiple users.

A **menu bar macOS app** that shows:

* Runs continuously with **minimal CPU + memory overhead**
* Shows **RAM by user (donut)**, **swap**, **pressure**
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
  * `ps -axo user,pid,rss,command` → processes
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

    * 🟢 / 🟡 / 🔴

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

👉 Process parsing is the expensive part.

---

### 5.2 Avoid heavy SwiftUI redraw

* Use:

  * `@Published` minimal fields
* Split ViewModels:

  * `MemoryVM`
  * `ProcessVM`

---

### 5.3 Limit process list size

* Only keep:

  * top 8 processes
* Not full list

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

* Total used RAM
* Swap used
* Memory pressure
* selected user only (if any)

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

* Show **all users**

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
* Lines:

  * total usage
  * swap
  * pressure

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
* Donut (RAM by user + free)
* Memory pressure + swap
* Short history (bounded)
* Top processes (filterable)

### System

* Lightweight sampling
* Run at login
* Context menu

### Note

* RAM per user is approximated using RSS
* Shared memory may be double-counted
* Values are indicative, not exact
