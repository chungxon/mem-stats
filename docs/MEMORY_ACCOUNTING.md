# Memory Accounting vs Activity Monitor

Why MemStats (and Stats) show numbers that differ from Activity Monitor. These gaps are expected, not bugs. Decision (2026-10-06): keep the current behavior.

## 1. Per-process memory: ~7.4% gap from units

All three apps read the same value, `phys_footprint` (`top` MEM column = `footprint -p <pid>`). Only the display unit differs:

| App | Unit | Divisor |
|---|---|---|
| Activity Monitor (process table) | decimal GB | 1000³ |
| MemStats, Stats | binary GiB | 1024³ (`MemoryFormat.bytesPerGigabyte`) |

Ratio is always 1024³ / 1000³ ≈ 1.074. Example: Maccy 3.33 GB in MemStats = 3.58 GB in Activity Monitor.

Activity Monitor mixes units: the process table is decimal, but the summary panel (Physical Memory 16.00 GB) is binary. Switching MemStats to decimal would make total RAM read 17.18 GB.

## 2. "Memory Used" total: ~0.5 GB gap from formula

| App | Formula |
|---|---|
| MemStats, Stats | `App (internal - purgeable) + Wired + Compressed` (`MemoryStatsService.usedMemoryBytes`) |
| Activity Monitor | roughly `Physical - Free - Cached Files` |

Activity Monitor's own sub-items do not add up to its Used value (example: App 2.25 + Wired 6.34 + Compressed 5.46 = 14.05, but Used shows 14.60).

The difference is RAM that `vm_stat` does not put in any counter (kernel / GPU / firmware reservations). Check:

```
free + active + inactive + speculative + wired + occupied-by-compressor  <  hw.memsize / pagesize
```

On a 16 GB M-series Mac: 1,012,546 of 1,048,576 pages accounted, ~36k pages × 16 KB ≈ 0.55 GB missing. 14.05 + 0.55 = 14.60.

Small differences between MemStats and Stats (e.g. 14.02 vs 14.05) come from different sampling moments.

## If we ever want to match Activity Monitor

- Total: use `total - free - speculative - fileBacked`. Downside: App + Wired + Compressed no longer sums to Used.
- Processes: format process sizes with 1000³. Downside: inconsistent units inside the popup.
