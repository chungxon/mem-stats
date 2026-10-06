# MemStats - Release Plan (2026-10-03)

## Scope

Plan này tổng hợp kết quả review trước release ngày 2026-10-03 (spec conformance, bug/release readiness, UI), đã đối chiếu lại với commit `909a1b1`. Mỗi task là **1 commit riêng**. Sau mỗi task: build, chạy unit test, check linter các file đã sửa, review bằng subagent, rồi commit.

Thứ tự ưu tiên:

- **P0**: phải xong trước release. Thứ tự: Task 1-6, Task 15 (Settings), Task 16 (Check for Updates, Report a Bug), cuối cùng Task 7 (publish).
- **P1**: nên làm trong bản release nếu kịp.
- **P2**: dọn dẹp, có thể để bản sau.

## Hiện trạng

- Unit test pass, Release build không có warning của app.
- Spec khớp ở các phần chính: sampling 5s/15s (process idle 60s từ Task 14) và rule 2s, công thức Used RAM, pressure sysctl + fallback, `top` top-500, gom app theo `.app` ngoài cùng, màu FNV-1a, growth detector, ẩn system users, login item.
- Đã xử lý trong `909a1b1`: info row/center label theo docs mới, Clear Filter dạng overlay, legend flow layout.

## Decisions (cần anh chốt)

- Giữ `top` làm nguồn process duy nhất, cả sau release (đổi ý 2026-10-06). App phục vụ máy nhiều user dùng chung, mà khi không có quyền đặc biệt, `proc_pid_rusage` chỉ đọc được process của user đang chạy app, nên không thay được `top`. Task 14 đổi sang giảm chi phí của `top`.
- Phân phối ngoài Mac App Store, chỉ qua GitHub Releases. Không lên Store vì sandbox phải tắt để chạy `top` và đọc process của user khác.
- Bỏ Homebrew khỏi bản 1.0 (2026-10-04): app chưa ký Developer ID/notarize nên khó lên `homebrew/cask` chính thức. Khi ký được app thì thêm lại (tap riêng hoặc `homebrew/cask`).
- Chưa có Apple Developer Program: bản 1.0 không notarize. README hướng dẫn mở app lần đầu ("Open Anyway" hoặc bỏ quarantine).
- Không làm tự động cập nhật (Sparkle) hay tự check update nền. Settings có nút "Check for Updates" (mở thẳng trang release mới nhất trên GitHub, không so version, app không gọi mạng) và nút "Report a Bug" mở trang tạo issue trên GitHub (Task 16).
- Hạ deployment target từ macOS 15.7 xuống 14.0 để hỗ trợ rộng hơn (API dùng tối đa macOS 14). Không giới hạn max, build bằng SDK mới nhất (Xcode 27).
- Context menu giữ `About` / `Quit` như hiện tại (menu ngắn, icon đã thể hiện app).
- Màu warning thống nhất: **orange** (dễ đọc hơn yellow trên menu bar sáng), cập nhật docs từ 🟡 sang 🟠. Swap và growth hint đổi sang màu khác.

---

## P0

## Task 1 - Fix Info Row For Non-User Slices

Files: `PopoverRootView.swift`, `docs/DESCRIPTION.md`

Bug: hover slice **Free** hiện `8.00 GB / 5.00 GB` (free so với used RAM), sai nghĩa.

- [x] `selectionSubtitle` theo loại slice:
  - User / Others / Unattributed: `<slice GB> / Used X` (giữ như hiện tại).
  - Free: `<free GB> / Total Y`.
  - Không hover/select: `Used X / Total Y` (giữ như hiện tại).
- [x] Làm tròn % thống nhất: center label của slice dùng `.rounded()` giống % tổng thay vì `Int(x * 100)`.
- [x] Thêm `.lineLimit(1)` cho 2 text của info row, subtitle có `.layoutPriority(1)` để tên user dài không đè số.
- [x] Cập nhật §6 Info row trong docs.

Commit: `fix(donut): show free slice against total RAM in the info row`

## Task 2 - Harden Process Sampling

Files: `Services/ProcessSnapshotService.swift`, `ViewModels/MemStatsAppState.swift`, `MemStatsTests.swift`

Bug: `top -l 1 -n 500` đo được 1.4s trên máy dev, timeout chỉ 2s. Khi máy tải nặng, mọi sample fail và banner lỗi đứng luôn. Bấm "Refresh Now" liên tục thì mỗi lần bấm xếp thêm 1 lần chạy `top` vào queue.

- [x] Nâng timeout `top` lên 6s.
- [x] Kiểm tra kết quả `readGroup.wait`, throw nếu reader chưa xong (tránh đọc buffer khi reader còn ghi).
- [x] Thêm cờ `isSampling`: nếu đang sample thì không enqueue thêm, chỉ đánh dấu `needsResample` và chạy thêm đúng 1 lần sau khi xong.
- [x] Đóng popover chỉ đổi interval, không sample ngay (chỉ mở popover mới sample ngay theo rule 2s).
- [x] Parser cột mem: bỏ hậu tố `+`/`-`, clamp giá trị trước khi đổi sang `UInt64`.
- [x] Test: parse `12G+`, `512K-`; coalesce nhiều lần refresh liên tiếp.
- [x] Cập nhật §5.1 trong docs (rule khi đóng popover, coalesce Refresh Now).

Current resilience note (2026-10-05): nếu snapshot 500 process timeout sau 6s, service tự dừng và
thử lại snapshot 150 process trong tối đa 4s. Chỉ timeout ở lần chính mới kích hoạt fallback; nếu
fallback thất bại thì lỗi của fallback được hiển thị, còn lỗi launch/read được hiển thị trực tiếp.

Commit: `fix(sampling): raise top timeout and coalesce overlapping samples`

## Task 3 - Clarify Selection Reset In Docs

Files: `docs/DESCRIPTION.md`

Giữ hành vi hiện tại: filter tự reset khi user không còn slice riêng trên donut. Lý do: user được chọn luôn có slice để highlight, center label và info row luôn khớp với danh sách đang lọc. Docs §6 chỉ ghi "no longer exists" nên chưa rõ.

- [x] §6: ghi rõ filter tự reset khi user không còn slice riêng (bị gộp vào "Others" vì < 2%, hoặc không còn process).
- [x] §6: ghi rõ chỉ slice user mới chọn được (Free, Others, Unattributed chỉ hover).

Commit: `docs(donut): clarify when the user filter resets`

## Task 4 - Unify Pressure Color And Menu Bar Accessibility

Files: `AppDelegate.swift`, `PopoverRootView.swift`, `ViewModels/DonutDataBuilder.swift`, `docs/DESCRIPTION.md`

- [x] Một nguồn màu pressure dùng chung cho menu bar và popover (normal green, warning orange, critical red).
- [x] Swap legend và growth hint không dùng orange nữa (swap dùng màu trung tính, hint dùng text `.secondary` + swatch).
- [x] Bỏ orange khỏi bảng màu user để không trùng warning.
- [x] Menu bar: thêm `toolTip` và accessibility label, ví dụ `Memory 45%, pressure Normal`.
- [x] Trước sample đầu tiên hiện `RAM --%` thay vì `RAM 0%` màu xanh.
- [x] Cập nhật §3, §7 trong docs.

Commit: `fix(pressure): unify warning color and label the menu bar item`

## Task 5 - Release Configuration

Files: `MemStats.xcodeproj/project.pbxproj`, scheme, `README.md`

- [x] Điền `INFOPLIST_KEY_NSHumanReadableCopyright` (About panel đang trống).
- [x] Thêm `INFOPLIST_KEY_LSApplicationCategoryType = public.app-category.utilities`.
- [x] Xoá entitlement `user-selected files` còn sót từ template.
- [x] `MACOSX_DEPLOYMENT_TARGET` = 14.0 cho tất cả target. Build lại, sửa mọi lỗi/warning về API chỉ có từ macOS 15 (thêm `if #available` nếu cần).
  - Đã build thử với target 14.0: chỉ lỗi 1 chỗ, `Color.mix(with:by:)` (macOS 15+) cho màu slice Unattributed ở `PopoverRootView.swift:530`. Thay bằng `NSColor(name:dynamicProvider:)` blend `systemGray` với trắng theo appearance, để màu vẫn đúng ở cả light/dark mode.
- [x] Bỏ target `MemStatsUITests` khỏi Test action của scheme (đang là template, test launch performance chậm và dễ fail), hoặc xoá hẳn target.
- [x] Kiểm tra version `1.0` (build `1`).
- [x] Release build ký ad-hoc (`CODE_SIGN_IDENTITY = "-"`, Sign to Run Locally) thay cho cert Apple Development của team cá nhân, để app chạy được trên máy khác mà không gắn với Apple ID dev.
- [x] README thêm các mục:
  - Requirements: macOS 14.0 trở lên.
  - Install qua GitHub Releases (tải zip, kéo vào Applications). (Homebrew đã bỏ, xem Decisions.)
  - Mở lần đầu: app chưa notarize nên macOS sẽ chặn. Vào System Settings > Privacy & Security > "Open Anyway", hoặc chạy `xattr -dr com.apple.quarantine /Applications/MemStats.app`.
  - Update: xem phiên bản trong About, so với trang GitHub Releases.
  - Build from source.

Commit: `chore(release): set app metadata and drop template UI tests`

## Task 6 - Sync Planning Docs

Files: `docs/PLAN.md`, `docs/PLAN_REMEDIATION.md`, `docs/DESCRIPTION.md`

- [x] `PLAN_REMEDIATION.md` Task 9-11 (`phys_footprint`, `proc_pidinfo`, merge `top mem`): đổi sang "dropped" theo Decision Note (vẫn dùng `top`).
- [x] `PLAN_REMEDIATION.md` Task 7 (đường swap nét đứt, dải pressure) và `PLAN.md` Task 6 (plot swap/pressure series): ghi rõ đã thay bằng badge.
- [x] `PLAN_REMEDIATION.md` Task 2/3: ghi chú hint text và tooltip % đã được thay bởi Task 15 trong `PLAN_REVIEW_FIXES.md`.
- [x] `DESCRIPTION.md`:
  - §4: mở Activity Monitor bằng bundle id `com.apple.ActivityMonitor` qua `NSWorkspace`.
  - §11.2: debounce hiện chỉ áp dụng cho menu bar title, popover cập nhật mỗi sample.
  - §11.3: ghi rõ chưa lazy (popover nhỏ, luôn hiện đủ) hoặc bỏ mục.
  - §8: thứ tự cột thực tế (USER, PID, PROCESS, MEM) hoặc sửa code theo spec.
  - Bổ sung: nút Refresh Now, dòng Sampling/History Samples, `top` timeout, title `RAM N%`.

Commit: `docs: sync plans and description before release`

## Task 15 - Settings Window (làm trước Task 7)

Files: `Services/SettingsStore.swift` (mới), `SettingsView.swift` (mới), `AppDelegate.swift`, `MemStatsApp.swift`, `ViewModels/MemStatsAppState.swift`, `ViewModels/ProcessViewModel.swift`, `ViewModels/MemoryViewModel.swift`, `MemStatsTests.swift`, `docs/DESCRIPTION.md`, `README.md`

Hiện tại RAM và process dùng chung 1 timer (5s khi mở popover, 15s khi đóng), Top Apps và Top Processes cố định 8 dòng.

Settings (lưu `UserDefaults`, đổi là áp dụng ngay, giá trị lưu sai thì về mặc định):

| Setting | Lựa chọn | Mặc định |
| --- | --- | --- |
| Update interval (RAM, pressure, swap, menu bar, history) | 1, 2, 3, 5, 10, 15, 30, 60s | 5s |
| Update interval for top processes (`top`) | 3, 5, 10, 15, 30, 60s | 5s |
| Number of top apps | 5, 8, 10, 15, 20 | 8 |
| Number of top processes | 5, 8, 10, 15, 20 | 8 |

`top` mất khoảng 1.4s mỗi lần chạy nên interval cho top processes thấp nhất là 3s.

Sampling:

- [x] `SettingsStore` (`ObservableObject`) giữ 4 setting trên, đọc/ghi `UserDefaults`, validate theo danh sách lựa chọn.
- [x] Tách thành 2 timer trên `samplingQueue`: (thực tế: timer chạy trên 1 queue, còn công việc sample chạy trên 2 serial queue riêng để `top` chậm không chặn memory sample; logic timer + coalesce gom vào `PeriodicSampler`)
  - Memory timer: `host_statistics64` + `sysctl`, cập nhật menu bar, history, donut (dùng process snapshot gần nhất).
  - Process timer: `top`, cập nhật Top Apps, Top Processes, donut, growth hints.
- [x] Giữ idle mode: khi popover mở dùng interval đã chọn, khi đóng dùng `max(interval đã chọn, 15s)` cho từng timer (process đổi thành 60s, xem Task 14).
- [x] Giữ rule 2s khi mở/đóng popover và coalesce sample (Task 2) cho cả 2 timer.
- [x] Refresh Now chạy ngay cả 2 loại sample.
- [x] History giữ cửa sổ khoảng 10 phút: `maxSamples = ceil(600 / memory interval)`, giới hạn trên 600 điểm.
- [x] Growth hint giữ rule "12 sample liên tiếp" theo process timer, ghi rõ trong docs là khoảng thời gian thay đổi theo interval.
- [x] Dòng "Sampling: Active (5s) / Idle (15s)" trong History hiện đúng interval thực tế.
- [x] `ProcessViewModel`: tách `topAppsLimit` và `topProcessesLimit`, đổi số dòng thì cắt lại danh sách hiện có, không cần resample.

Settings window:

- [x] Cửa sổ Settings tự quản lý (`NSWindow` + `NSHostingController`) trong `AppDelegate`, vì app là `LSUIElement` nên mở `Settings` scene của SwiftUI từ `NSMenu` không ổn định. Mở cửa sổ thì `NSApp.activate()` và đưa lên trước, mở lại thì dùng lại cửa sổ cũ.
- [x] `SettingsView`: `Form` với `.formStyle(.grouped)`, `Picker` kiểu `.menu`, giống ảnh mẫu:
  - Section 1: Update interval, Update interval for top processes.
  - Section 2: Number of top apps, Number of top processes.
  - Section 3: Open at Login, Show System Users (dùng chung logic với context menu, đồng bộ 2 chiều).
- [x] Context menu thêm "Settings…" (Cmd+,) phía trên About. Nút gear trong popover mở cùng context menu tại vị trí nút gear.
- [x] Bỏ `Settings { EmptyView() }` trong `MemStatsApp.swift` (thay bằng scene rỗng phù hợp) để Cmd+, không mở cửa sổ trống.

Tests và docs:

- [x] Test `SettingsStore`: mặc định, lưu/đọc lại, giá trị không hợp lệ về mặc định.
- [x] Test interval khi idle: `max(setting, 15)`.
- [x] Test `ProcessViewModel` với limit khác nhau cho apps và processes.
- [x] Test `maxSamples` theo interval.
- [x] Cập nhật docs: §3 (context menu thêm Settings…), §5.1, §5.3, §7 (maxSamples), §8, §8.1 (số dòng theo setting), §14.1, §14.3, thêm mục Settings.
- [x] README: ghi chú interval thấp làm tăng CPU (nhất là top processes).

Commit: `feat(settings): add settings window for update intervals and row counts`

## Task 16 - Check For Updates And Report A Bug In Settings (làm trước Task 7)

Files: `Services/AppLinks.swift` (mới), `SettingsView.swift`, `MemStatsTests.swift`, `docs/DESCRIPTION.md`, `README.md`

Repo: `https://github.com/chungxon/mem-stats`.

- [x] `AppLinks`: URL repo, trang Releases, `releases/latest`, trang tạo issue mới.
- [x] Report a Bug: mở `issues/new` với title và body điền sẵn (mô tả, các bước tái hiện, kỳ vọng, môi trường: version app, macOS, model máy, kiến trúc).
- [x] Check for Updates: mở thẳng `releases/latest` trên trình duyệt, không so version, không gọi GitHub API (đổi ý 2026-10-04, bỏ `UpdateChecker`).
- [x] Settings thêm section cuối: Version, Check for Updates, Report a Bug.
- [x] Test: URL `releases/latest`, URL issue có title, label và thông tin môi trường.
- [x] Fix crash khi mở Settings: `LabeledContent` trong Form gây vòng lặp Update Constraints, đổi sang `HStack`. Thêm test mở cửa sổ Settings.
- [x] Cập nhật docs §15 và README (Update, Report a Bug).

Commit: `feat(settings): add check for updates and bug report links`

## Task 7 - Publish Release On GitHub (thủ công)

Build và đóng gói:

- [ ] `xcodebuild -project MemStats/MemStats.xcodeproj -scheme MemStats -configuration Release -derivedDataPath build archive -archivePath build/MemStats.xcarchive`.
- [ ] Lấy `MemStats.app` trong archive, nén bằng `ditto -c -k --keepParent MemStats.app MemStats-1.0.zip` (giữ đúng symlink và chữ ký, không dùng Finder Compress hay `zip`).
- [ ] `codesign --verify --deep --strict MemStats.app` để chắc chữ ký ad-hoc hợp lệ.
- [ ] `shasum -a 256 MemStats-1.0.zip` để lấy checksum ghi vào release notes.

GitHub Release:

- [ ] Tạo tag `v1.0` và release trên `chungxon/mem-stats`, đính kèm `MemStats-1.0.zip` và ghi checksum.
- [ ] Release notes: tính năng chính, yêu cầu macOS, hướng dẫn mở lần đầu (giống README).
- [x] Đưa demo GIF vào `assets/output.gif` và nhúng vào README cho public release.

Kiểm tra:

- [ ] Kiểm tra trên máy sạch, cài từ zip tải trên GitHub về (có quarantine): mở lần đầu theo README, Open at Login, Show System Users, Settings, About (đúng version), Quit.
- [ ] Test trên các bản macOS: 14 (min, dùng máy ảo), 26.6 (máy dev), 27 (mới nhất). Chú ý: parse output `top`, pressure sysctl, Open at Login, giao diện control hệ thống và màu menu bar.
- [ ] Chạy 30-60 phút, xác nhận Real/Private Memory ổn định (theo README).
- [ ] Đóng mục manual verify còn `[~]` ở `PLAN_REVIEW_FIXES.md` Task 3 (màu menu bar trên màn hình active).

---

## P1

## Task 8 - Memory Units And Column Truncation

Files: `PopoverRootView.swift`, `docs/DESCRIPTION.md`

- [x] Dưới 1 GB hiển thị `%.0f MB`, từ 1 GB hiển thị `%.2f GB` (spec §8 yêu cầu MB/GB).
- [x] Cột MEM rộng khoảng 64pt.
- [x] Cột USER: `.lineLimit(1)`, `.truncationMode(.tail)`, `.help(user)`.
- [x] Tên app/process: `.truncationMode(.middle)`.
- [x] Trục Y history: tick dùng `%.0f GB`, tick 0 cũng có đơn vị. (tick đặt ở bội số GB tròn 1/2/4/8..., định dạng gom vào `Models/MemoryFormat.swift` có test)

Commit: `fix(ui): format memory as MB/GB and truncate long names`

## Task 9 - Loading State And Fixed Header

Files: `PopoverRootView.swift`, `ViewModels/ProcessViewModel.swift`

- [x] Hiện `Loading…` cho Top Apps / Top Processes đến khi có sample đầu tiên, sau đó mới hiện "No data".
- [x] Đưa header (Activity Monitor, gear) ra ngoài `ScrollView` để không bị cuộn mất, bật scroll indicator.
- [x] Header button: vùng bấm 24x24 (`contentShape`).
- [x] Pin kích thước popover trong SwiftUI (`.frame(width:height:)`) cho khớp `contentSize`.

Commit: `fix(ui): add loading state and keep header visible`

## Task 10 - Reduce Re-render On Hover

Files: `PopoverRootView.swift`, `ViewModels/MemoryViewModel.swift`, `ViewModels/ProcessViewModel.swift`

- [x] Tách donut thành subview riêng giữ state hover, chỉ cập nhật khi slice id đang hover thay đổi.
- [x] Sort history và tạo segment 1 lần trong ViewModel khi có sample mới, không sort trong body.
- [x] Cache `visibleProcesses` / `visibleApps` khi đổi selection hoặc có sample mới.
- [x] Cache tên hiển thị của process thay vì parse command mỗi lần render.

Commit: `perf(ui): avoid full popover re-render on donut hover`

## Task 11 - Accessibility

Files: `PopoverRootView.swift`

- [x] Mỗi dòng Top Apps / Top Processes là 1 element VoiceOver (thực tế: `.accessibilityElement(children: .ignore)` kèm label đọc rõ tên cột, vì `.combine` chỉ đọc "Safari, 12, 1.20 GB").
- [x] Header của bảng có trait `.isHeader`.
- [x] History chart có `accessibilityLabel` và `accessibilityValue` (used hiện tại, pressure, swap).
- [x] Màu slice Unattributed đủ tương phản trên nền sáng (thực tế: không dùng `tertiaryLabelColor` vì nó trong suốt và nhạt hơn; dùng xám đậm hơn ở light mode, sáng hơn ở dark mode).

Commit: `feat(a11y): improve VoiceOver for tables and history chart`

## Task 12 - Login Item Pending Approval Toggle

Files: `Services/LoginItemService.swift`, `AppDelegate.swift`, `MemStatsTests.swift`

Bug: khi trạng thái là `.requiresApproval`, bấm "Open at Login" lần nữa lại gọi `register()` và alert hiện lại, không có cách huỷ.

- [x] Coi `.requiresApproval` là "đang bật" khi toggle, lần bấm tiếp theo gọi `unregister()`.
- [x] Checkmark hiện trạng thái mixed hoặc kèm text "(needs approval)".
- [x] Test với mock status `.requiresApproval`.

Commit: `fix(login): allow cancelling a login item pending approval`

---

## P2

## Task 13 - Polish

Files: `AppDelegate.swift`, `PopoverRootView.swift`, `MemStatsTests.swift`

- [x] `...` đổi thành `…` trong text Loading.
- [x] `.monospacedDigit()` cho số History Samples, legend và subtitle donut.
- [x] Spacing 14pt đổi về 12 hoặc 16 (lưới 8pt).
- [x] Đường "Selected" trong history dùng màu slice của user đó thay vì teal.
- [x] Copy: `grew +X` đổi thành `grew by X`.
- [x] `ForEach` growth hint: id không trùng khi 1 user có 2 hint.
- [x] Sửa warning Swift 6 trong test: `MemoryGrowthHint` Equatable conformance bị isolate main actor (đánh dấu `nonisolated`).
- [x] Menu bar title giữ độ rộng cố định khi đổi giữa 1/2/3 chữ số.

Commit: `chore(ui): polish copy, spacing and digit alignment`

## Task 14 - (Sau release) Reduce top Cost

Files: `ViewModels/MemStatsAppState.swift`, `PopoverRootView.swift`, `SettingsView.swift`, `Localizable.xcstrings`, `MemStatsTests.swift`, `README.md`, `docs/DESCRIPTION.md`

Vì sao không thay `top` bằng libproc (đo trên macOS 26.6 ngày 2026-10-06, chạy với quyền user thường):

- `proc_pid_rusage` và `task_name_for_pid` lỗi với mọi process không thuộc user đang chạy app (181/902 process, khoảng 6% RAM, gồm WindowServer khoảng 1.5 GB). Trên máy nhiều user, process của các user người thật khác cũng bị chặn như vậy.
- `sysctl(KERN_PROC_PID)` đọc được pid, uid, tên của mọi process nhưng không có RAM.
- `top` và `ps` đọc được vì là binary setuid root có entitlement `com.apple.system-task-ports.read`, app bên thứ ba không xin được.
- `ps -axo pid,user,rss,comm` nhanh (khoảng 0.06s) nhưng chỉ có RSS, không tính phần bị nén, swap và bộ nhớ GPU (WindowServer: RSS 95 MB, footprint 1.5 GB), nên không dùng làm nguồn chính.
- Privileged helper (`SMAppService.daemon`) đọc đủ nhưng cần quyền admin, không đáng cho app menu bar.
- `-n` của `top` không làm nhanh hơn: `top` luôn quét mọi process, thời gian 1.6-8s tuỳ tải máy với cả `-n 50`, `150`, `500`. Top 500 phủ khoảng 94% RAM của process (top 150: 81%, top 50: 61%), nên giữ 500.

Hiện trạng: khi popover đóng, `top` vẫn chạy mỗi `max(setting, 15s)` để nuôi history theo user (cửa sổ khoảng 10 phút) và growth hint (cần 12 sample liên tiếp, khoảng 3 phút ở 15s). Menu bar chỉ dùng số tổng từ `host_statistics64`, không cần `top`.

- [x] Chốt interval của process timer khi popover đóng (anh chốt 2026-10-06: tối thiểu 60s, chỉ riêng process timer, memory timer giữ 15s). Đổi lại history theo user thưa hơn khi đóng popover và growth hint "12 sample liên tiếp" kéo dài thành khoảng 12 phút. Sau khi mở lại popover, history theo user lẫn sample 60s và sample theo setting, nên 12 sample không còn ứng với một khoảng thời gian cố định (copy "over the last N samples" vẫn đúng).
- [x] Tách `idleMinimumInterval` thành 2 giá trị cho memory và process (`SamplingKind.idleMinimumInterval`).
- [ ] Đo CPU/thời gian sample trước và sau (popover mở và đóng). Ước tính từ thời gian `top` đo được (khoảng 1.9s CPU mỗi lần, `user + sys`): khi đóng popover giảm từ khoảng 13% xuống khoảng 3% một core. Cần đo thật trên máy nhiều user.
- [x] `effectiveInterval` nhận thêm loại timer (memory hoặc process).
- [x] Dòng Sampling trong History hiện đúng khi 2 timer khác nhau lúc idle, ví dụ `Idle (15s, processes 60s)`.
- [x] Settings: sửa câu "both update at most every 15 seconds" và chuỗi dịch tương ứng trong `Localizable.xcstrings`.
- [x] Test `effectiveInterval` khi idle cho từng loại timer, và interval ban đầu của app state (15s/60s). Text dòng Sampling dùng code có sẵn (`%@ (%llds, %@ %llds)`), chưa có test riêng.
- [x] Cập nhật docs §5.1, §7 (dòng Sampling, khoảng thời gian history), §14.1, §14.3 (sửa luôn câu "12 phút ở 60s": capacity ở setting 60s chỉ còn 10 sample nên hint không bao giờ hiện), Note (lý do giữ `top`) và README (câu "both intervals are at least 15s").
- [x] Thêm "xem Task 14" vào phần Hiện trạng và Task 15 chỗ ghi rule `5s/15s`, `max(interval, 15s)`.

Commit: `perf(sampling): sample processes less often while the popover is closed`
