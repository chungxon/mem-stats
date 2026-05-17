# 🧭 Product Definition

A **menu bar macOS app** that shows:

* RAM usage by **user (donut chart)**
* **Memory pressure + swap**
* **History timeline**
* **Top processes (global or per selected user)**
* **Quick kill process**

All inside **one popup window**.

---

# 🧱 1. Architecture Overview

### Stack

* UI: SwiftUI
* Menu bar: `NSStatusBar` + `NSPopover`
* Data layer:

  * `host_statistics64` → memory stats
  * `sysctl` → total RAM
  * `libproc` OR `ps` → processes
* State:

  * `ObservableObject` (single source of truth)

---

# 🪟 2. UI Layout (Single Popup)

```
┌──────────────────────────────────┐
│ [Open Activity Monitor]   [Quit] │
├──────────────────────────────────┤
│                                  │
│          Donut Chart             │
│        (% total usage)           │
│                                  │
├──────────────────────────────────┤
│        History Chart             │
├──────────────────────────────────┤
│        Top Processes             │
│ (filtered by selected user)      │
└──────────────────────────────────┘
```

---

# 🎯 3. Core UX Behavior

## 3.1 Header

* Left: **Open Activity Monitor**

  * launch:

    ```bash
    open -a "Activity Monitor"
    ```

* Right: **Quit**

---

## 3.2 Donut Chart (Key Interaction)

### Data

* Each slice = **user total RAM**
* Last slice = **Free memory**

### Center label

* Default: `% used RAM`
* On hover/press:
  → show: `Used / Total (GB)`

### Interaction

* Hover / long press on slice:

  * show tooltip:

    * user name
    * memory (GB)
    * %
* Click slice:

  * set `selectedUser`
  * filter process list

---

## 3.3 History Chart

### Metrics

* Total used RAM
* Swap used
* Memory pressure
* Optional: per-user lines (toggle)

### Time ranges

* last 5 min
* last 1 hour
* last 24h (optional later)

---

## 3.4 Top Processes

### Default

* Show **all users**

### When user selected

* Filter:

  ```swift
  process.user == selectedUser
  ```

### Columns

* Process name
* PID
* User
* Memory (MB/GB)

### Sorting

* By memory DESC

### Interaction

* Click process:

  * confirm dialog:

    * “Kill process?”
* Action:

  ```swift
  kill(pid, SIGKILL)
  ```

---

# ⚙️ 4. Data Model

```swift
struct MemoryStats {
    let total: UInt64
    let used: UInt64
    let free: UInt64
    let compressed: UInt64
    let swapUsed: UInt64
    let pressure: Double
}

struct ProcessInfo {
    let pid: Int
    let user: String
    let name: String
    let memory: UInt64 // bytes
}

struct UserMemory {
    let user: String
    let totalMemory: UInt64
}

struct Snapshot {
    let timestamp: Date
    let totalUsed: UInt64
    let swapUsed: UInt64
    let pressure: Double
    let perUser: [UserMemory]
}
```

---

# 🔄 5. Data Flow

### Sampling loop

```swift
Timer (every 2 seconds)
  → fetchMemoryStats()
  → fetchProcesses()
  → groupByUser()
  → computePressure()
  → appendSnapshot()
  → publish state
```

---

# 🧠 6. Memory Calculation

## 6.1 Total memory

```swift
sysctl("hw.memsize")
```

---

## 6.2 Used memory

```swift
used = active + wired + compressed
```

---

## 6.3 Pressure (custom logic)

```swift
pressure = used / total
```

Mapping:

* `< 0.6` → green
* `< 0.8` → yellow
* `>= 0.8` → red

---

# 🧩 7. Process Collection

## Option A (MVP – fast)

```bash
ps -axo user,pid,rss,comm
```

Parse:

* RSS = KB → convert to bytes

---

## Option B (advanced – later)

* `proc_pidinfo`
* more accurate but complex

---

# 🧮 8. Grouping Logic

```swift
Dictionary(grouping: processes, by: \.user)
  .map {
    UserMemory(
      user: $0.key,
      totalMemory: $0.value.reduce(0) { $0 + $1.memory }
    )
  }
```

---

# 📊 9. Charts Implementation

## Donut Chart

* SwiftUI:

  * `Canvas` OR
  * custom `Shape`
* Each arc = user %

---

## History Chart

* Use:

  * `Charts` framework (macOS 13+)
* Lines:

  * total usage
  * swap
  * pressure

---

# 💾 10. History Storage

### In-memory (MVP)

* Keep last:

  * 300 samples (≈10 min)

### Optional upgrade

* SQLite
* persist across sessions

---

# 🔔 11. Optional Enhancements (Recommended)

## 11.1 Alert system

* Notify when:

  * pressure = red
  * swap > threshold

---

## 11.2 Memory spike detection

* detect sudden jump per user

---

## 11.3 Menu bar mini indicator

* Show:

  * RAM %
  * color (pressure)

---

## 11.4 Hover preview (pro UX)

* Hover donut slice:

  * highlight slice
  * dim others

---

## 11.5 Exclude system users

* hide:

  * `_windowserver`
  * `_kernel`

---

# 🔐 12. Permissions & Safety

* Killing process:

  * may require:

    ```bash
    sudo
    ```

* For MVP:

  * allow killing only same-user processes

---

# 🧱 13. Project Structure

```
/App
  MenuBarApp.swift

/Core
  MemoryService.swift
  ProcessService.swift
  PressureCalculator.swift

/Models
  MemoryStats.swift
  ProcessInfo.swift
  UserMemory.swift
  Snapshot.swift

/ViewModels
  DashboardViewModel.swift

/UI
  PopupView.swift
  DonutChartView.swift
  HistoryChartView.swift
  ProcessListView.swift
```

---

# 🚀 14. Build Roadmap

## Phase 1 (MVP)

* menu bar app
* fetch memory + processes
* show table (no charts yet)

## Phase 2

* donut chart + selection logic

## Phase 3

* history chart

## Phase 4

* process kill + confirmation

## Phase 5

* polish UX (hover, animation, color)

---

# ⚠️ Important Notes

* RSS is approximate (good enough)
* macOS memory compression affects accuracy
* shared memory (Chrome, Electron) may double count
