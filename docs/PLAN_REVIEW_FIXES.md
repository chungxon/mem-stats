# MemStats - Review Fixes Plan (2026-10-03)

## Scope

Plan này tổng hợp kết quả review ngày 2026-10-03 (spec conformance, bug, UI). Mỗi task là **1 commit riêng**. Sau mỗi task: build, chạy unit test, check linter các file đã sửa, review bằng subagent, rồi commit.

## Decisions

- §14.2 (highlight user > 50% RAM): bỏ, donut đã thể hiện user dùng nhiều RAM nhất.
- §14.4 (alert/notify): bỏ, pressure đã thể hiện qua màu text trên menu bar.
- §14.5: thêm option show/hide system users (`root`, `_*`), cập nhật docs.
- §6 tooltip/center hover: giữ hành vi hiện tại (thông tin hiển thị bên dưới donut), cập nhật docs.
- §9/§10: giữ solid surfaces và `Charts.SectorMark`, cập nhật docs.

## Task 1 - Fix Used Memory Formula

Files: `Services/MemoryStatsService.swift`, `MemStatsTests.swift`

- [x] Tính `usedBytes` theo kiểu Activity Monitor: App Memory (`internal_page_count - purgeable_count`) + Wired + Compressed.
- [x] Tách công thức thành hàm pure, clamp về `0...totalBytes`.
- [x] Thêm test cho công thức.

Commit: `fix(memory): compute used memory like Activity Monitor`

## Task 2 - Sync Login Item State With System Status

Files: `Services/LoginItemService.swift`, `AppDelegate.swift`, `MemStatsTests.swift`

- [x] Sau `register()`/`unregister()`, đọc lại `registrant.status` thay vì tin input.
- [x] Nếu `.requiresApproval`: thông báo và mở System Settings > Login Items.
- [x] Re-sync status mỗi lần mở context menu.
- [x] Test với mock status `.requiresApproval`.

Commit: `fix(login): reflect real SMAppService status and handle requiresApproval`

## Task 3 - Fix Menu Bar Pressure Color On Active Display

Files: `AppDelegate.swift`

Bug: trên màn hình đang active, text menu bar luôn màu đen/trắng; màn hình không active mới hiện màu xanh/vàng/đỏ. Nguyên nhân: `contentTintColor` bị hệ thống bỏ qua khi status item được render với vibrancy trên menu bar active.

- [x] Dùng `attributedTitle` với `foregroundColor` tường minh thay cho `contentTintColor`.
- [x] Icon dùng symbol non-template với `SymbolConfiguration(paletteColors:)`.
- [~] Kiểm tra trên cả màn hình active và inactive, light và dark (chờ anh kiểm tra thủ công, em không chụp được màn hình).

Commit: `fix(menubar): render pressure color explicitly on all displays`

## Task 4 - Fix History Chart Coloring And Legend

Files: `PopoverRootView.swift`

- [x] Vẽ used RAM thành segment theo từng cặp sample liền kề, mỗi segment 1 series, màu theo pressure.
- [x] Legend "Used" dùng màu theo pressure hiện tại thay vì `.blue`.

Commit: `fix(history): draw pressure-colored segments and match legend color`

## Task 5 - Monospaced Digits For Live Numbers

Files: `AppDelegate.swift`, `PopoverRootView.swift`

- [x] Status item title dùng monospaced digit font.
- [x] Cột Memory ở Top Apps và Top Processes thêm `.monospacedDigit()`.

Commit: `fix(ui): use monospaced digits for live memory values`

## Task 6 - Remove Duplicate Section Titles

Files: `PopoverRootView.swift`

- [x] Mỗi section chỉ còn 1 tiêu đề, đổi theo trạng thái filter.

Commit: `fix(ui): show a single filter-aware title per section`

## Task 7 - Stable And Distinct Donut Colors

Files: `PopoverRootView.swift`, `MemStatsTests.swift`

- [x] Thay `hashValue` bằng hash ổn định (FNV-1a trên UTF-8 của username), không dùng `abs` trên `Int`.
- [x] Others và Unattributed dùng màu khác nhau rõ ràng.
- [x] Test: cùng user luôn cho cùng index.

Commit: `fix(donut): use stable user colors and distinguish others/unattributed`

## Task 8 - Cache Donut Slices

Files: `ViewModels/*`, `PopoverRootView.swift`

- [x] Tính `donutSlices` 1 lần khi có snapshot mới, lưu thành `@Published`.
- [x] View và hover hit-test đọc giá trị đã cache.

Commit: `perf(donut): cache slices and recompute only on new snapshots`

## Task 9 - Throttle Resample On Popover Toggle

Files: `ViewModels/MemStatsAppState.swift`, `MemStatsTests.swift`

- [x] Nếu sample gần nhất < 2s thì lên lịch theo interval mới thay vì sample ngay.
- [x] Test logic tính deadline.

Commit: `perf(sampling): avoid immediate resample when popover toggles rapidly`

## Task 10 - Small UI And API Polish

Files: `PopoverRootView.swift`, `AppDelegate.swift`

- [x] History `ForEach` dùng `timestamp` làm id.
- [x] `NSApp.activate(ignoringOtherApps:)` -> `NSApp.activate()`.
- [x] Accessibility label/value cho donut.

Commit: `chore(ui): stable chart ids, modern activate API, donut accessibility`

## Task 11 - Memory Leak Hint (§14.3)

Files: `ViewModels/*`, `PopoverRootView.swift`, `MemStatsTests.swift`

- [x] Detector dựa trên user history: tăng liên tục 12 sample, hoặc nhảy > max(500MB, 5% RAM) giữa 2 sample.
- [x] Hiện hint nhỏ cho user bị nghi.
- [x] Test cho cả 2 điều kiện.

Commit: `feat(history): add per-user memory growth and jump hints`

## Task 12 - Show/Hide System Users Option (§14.5)

Files: `ViewModels/MemStatsAppState.swift`, `AppDelegate.swift`, `docs/DESCRIPTION.md`, `MemStatsTests.swift`

- [x] Thêm toggle "Show System Users" trong context menu, persist bằng `UserDefaults`, mặc định bật (giữ hành vi hiện tại).
- [x] Khi tắt: ẩn `root` và `_*` khỏi donut, history, Top Apps, Top Processes.
- [x] Cập nhật §3 context menu và §14.5 trong docs.

Commit: `feat(users): add option to show or hide system users`

## Task 13 - Sync DESCRIPTION With Decisions

Files: `docs/DESCRIPTION.md`

- [x] Công thức used memory (Task 1).
- [x] §6: thông tin hover hiển thị bên dưới donut.
- [x] §9: solid surfaces thay cho materials. §10: donut dùng `Charts.SectorMark`.
- [x] §14.2 và §14.4: ghi rõ đã bỏ và lý do. §14.3: mô tả hint đã làm.

Commit: `docs: sync description with implemented behavior`

## Task 14 - Pressure Level Only From memorystatus

Files: `Services/MemoryStatsService.swift`, `MemStatsTests.swift`, `docs/DESCRIPTION.md`

Bug: app báo critical (đỏ) trong khi Activity Monitor vẫn normal. Nguyên nhân: `vm.memory_pressure` là bộ đếm hoạt động reclaim/pageout (đo được giá trị 476), không phải level, nhưng code map `>= 2` thành critical rồi lấy max với level thật.

- [x] `readSystemPressureLevel()` chỉ đọc `kern.memorystatus_vm_pressure_level` (1/2/4 = normal/warning/critical).
- [x] Xoá `levelFromVMMemoryPressure` và `maxPressureLevel` (không còn chỗ dùng) cùng test tương ứng.
- [x] Giữ fallback theo tỉ lệ used/total khi không đọc được sysctl.
- [x] Cập nhật nguồn pressure trong `docs/DESCRIPTION.md`.

Commit: `fix(pressure): derive level only from memorystatus pressure sysctl`

## Task 15 - Refine Top Users Info Row And History Legend

Files: `PopoverRootView.swift`, `docs/DESCRIPTION.md`

- [x] Bỏ dòng hint "Hover or click a slice..." và dòng summary riêng dưới donut.
- [x] Dòng info dưới donut: bên phải hiện `Used X / Total` của hệ thống khi không focus, khi hover/select thì đổi thành `<slice GB> / Used X` (so với used RAM của hệ thống).
- [x] Center label khi hover/select chỉ hiện tên slice + `%`, bỏ phần GB.
- [x] Nút "Clear Filter" chuyển lên header Top Users, dùng overlay để không đẩy layout.
- [x] Legend History dùng flow layout: label không bị wrap, chỉ item tràn mới xuống dòng.
- [x] Cập nhật §6 (center label, info row, Clear Filter) và §7 (legend) trong docs.

Commit: `feat(popover): refine Top Users info row and history legend layout`

## Task 16 - Anchor Options Menu To Popover Gear

Files: `AppDelegate.swift`, `PopoverRootView.swift`, `docs/DESCRIPTION.md`, `docs/PLAN_RELEASE.md`, `README.md`

- [x] Keep the gear behavior as the existing options menu instead of opening Settings directly.
- [x] Anchor the options menu to the gear inside the popover.
- [x] Keep the popover open when the gear menu is opened or dismissed.
- [x] Keep the menu bar context menu on right-click or Option-click of the menu bar item.
- [x] Update product documentation and release checklist.

Commit: `fix(popover): anchor options menu to gear button`
