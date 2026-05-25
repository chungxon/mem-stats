# Ram Stats - Remediation Plan (Post Review)

## Scope

Plan này tổng hợp toàn bộ issue từ vòng review gần nhất và chia thành các task nhỏ để triển khai an toàn.

## Issue Summary

1. Donut "RAM by User" đang tính từ top 20 process nên không đại diện tổng RAM theo user.
2. Top Processes UI chưa khớp spec: chỉ show 5 dòng, thiếu PID, command hiển thị khó đọc.
3. Donut UX chưa đủ theo description: thiếu hover tooltip/center-focused feedback.
4. Text ngữ cảnh desktop chưa chuẩn: "Tap" nên đổi thành "Click".
5. Test/build verification đang bị chặn bởi signing environment, cần tách rõ lỗi môi trường và lỗi code.

## Task 1 - Fix Donut Data Accuracy

Objective:

- Đảm bảo donut phản ánh dữ liệu bộ nhớ hợp lý thay vì chỉ top 20 process.

TODO:

- [x] Tách nguồn dữ liệu donut khỏi `topProcesses` hiển thị.
- [x] Bổ sung phần "Unattributed/Other Used" để tổng slice hợp lệ khi thiếu coverage từ process list.
- [x] Giữ quy tắc sort + merge tiny slices + free slice cuối.
- [x] Bổ sung test cho tổng fraction/slice consistency.

Acceptance Criteria:

- Donut không còn lệch lớn với `Used / Total` summary.
- Tổng các slice luôn hợp lệ, không vượt tổng RAM.

## Task 2 - Align Top Processes With Spec

Objective:

- Đưa phần Top Processes về đúng kỳ vọng trong `docs/DESCRIPTION.md`.

TODO:

- [x] Hiển thị đầy đủ tối đa top 8 process.
- [x] Bổ sung cột PID.
- [x] Rút gọn command thành process name dễ đọc, vẫn giữ metadata cần thiết.
- [x] Giữ sorting theo RAM giảm dần.

Acceptance Criteria:

- UI process list dễ đọc, có PID/User/Process/Memory.
- Không còn mismatch count 8 nhưng chỉ render 5 dòng.

## Task 3 - Improve Donut Interaction UX

Objective:

- Hoàn thiện interaction layer cho donut theo description.

TODO:

- [x] Thêm hover state cho slice (highlight/dim rõ ràng trên macOS).
- [x] Thêm tooltip/overlay thông tin user + memory + percent.
- [x] Bổ sung center label hoặc trạng thái tương đương để phản hồi trực quan.
- [x] Đảm bảo click chọn/bỏ chọn vẫn ổn định.

Acceptance Criteria:

- Hover/click cho trải nghiệm rõ ràng, không gây nhảy trạng thái.
- Filter process theo selected user ổn định.

## Task 4 - Copy, Terminology, and Visual Polish

Objective:

- Chuẩn hóa microcopy và hoàn thiện UX detail.

TODO:

- [x] Đổi "Tap a slice..." thành wording phù hợp desktop (`Click a slice...`).
- [x] Rà lại text labels trong popover cho đồng nhất.
- [x] Kiểm tra tương phản và readability với solid color surfaces hiện tại.

Acceptance Criteria:

- Wording đồng nhất ngữ cảnh macOS.
- Không còn text gây hiểu nhầm hành vi input.

## Task 5 - Verification and Environment Notes

Objective:

- Chốt verification rõ ràng để phân biệt lỗi code và lỗi local environment.

TODO:

- [x] Run lint cho tất cả file đã thay đổi.
- [x] Run unit test/build trong môi trường khả dụng.
- [x] Ghi chú rõ nếu fail do signing certificate/team setup.

Acceptance Criteria:

- Có báo cáo kết quả lint/test/build minh bạch.
- Nếu fail do môi trường, có hướng xử lý cụ thể.

## Task 6 - Selected User Process Filter Correctness

Objective:

- Đảm bảo khi chọn user từ donut, list process hiển thị đúng top process của user đó (không bị lệ thuộc top global).

TODO:

- [x] Lưu `topLimit` hiện tại trong `ProcessViewModel`.
- [x] Đổi `visibleProcesses` để lọc từ `allProcesses` theo `selectedUser`, sau đó mới áp `topLimit`.
- [x] Bổ sung test regression cho case user không nằm trong top global nhưng vẫn có top process riêng.
- [x] Run lint cho file đã thay đổi.

Acceptance Criteria:

- Khi chọn user, process list phản ánh đúng top process của user đã chọn.
- Không còn tình trạng selected user nhưng list trống/sai do lọc từ top global.

## Task 7 - History Chart Readability Stabilization

Objective:

- Làm chart lịch sử dễ đọc hơn và tránh cảm giác "line bị chéo lạ" khi hiển thị đồng thời Used/Swap/Pressure.

TODO:

- [x] Đổi series `Used` sang area + line để thể hiện xu hướng usage rõ hơn.
- [x] Giữ `Swap` ở dạng line nét đứt để phân biệt với `Used`.
- [x] Dời `Pressure` về dải overlay gần đỉnh chart để không nhiễu scale bytes.
- [x] Run lint cho file đã thay đổi.

Acceptance Criteria:

- Chart nhìn ổn định, dễ đọc hơn khi mở lâu.
- `Used`, `Swap`, `Pressure` được phân biệt rõ mà không làm trục dữ liệu khó hiểu.

Current Note:

- Bản hiện tại giữ `Used` là series chính; `Swap` và `Pressure` hiển thị dạng latest-status badges để giảm nhiễu đường chart.

## Task 8 - Full Verification Pass

Objective:

- Chạy lại full verification sau các thay đổi gần nhất để có trạng thái hiện tại rõ ràng.

TODO:

- [x] Run lint trên toàn bộ file Swift trong repo.
- [x] Run `xcodebuild build` với `-derivedDataPath .derivedData`.
- [x] Run `xcodebuild test -only-testing:RamStatsTests`.
- [x] Cập nhật notes kết quả verification và rủi ro môi trường.

Acceptance Criteria:

- Có báo cáo minh bạch cho lint/build/test tại thời điểm hiện tại.
- Nếu test fail do môi trường, ghi rõ nguyên nhân và hành động tiếp theo.

Latest Verification Notes (2026-05-19):

- Lint: `swiftlint` chưa có trong môi trường local; dùng `xcrun swift-format lint` để kiểm tra thay thế.
- Build: `xcodebuild build` pass với `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`.
- Test: `xcodebuild test -only-testing:RamStatsTests` fail do sandbox chặn `com.apple.testmanagerd.control` (không phải lỗi logic runtime của app).
- Environment follow-up: cần chạy test ngoài sandbox hoặc trên máy local có quyền testmanagerd đầy đủ để có kết quả test chính thức.
- Full lint snapshot: có warning format trong `RamStatsUITests/*` (template indentation/line length), không phải file logic chính của app.

## Task 9 - Process Memory Metric Alignment With Activity Monitor

Objective:

- Giảm độ lệch giữa Top Processes trong app và cột Memory của Activity Monitor.

TODO:

- [x] Ưu tiên lấy `phys_footprint` theo PID thay vì chỉ dựa trên `rss`.
- [x] Giữ fallback `rss` khi không lấy được footprint của process.
- [x] Re-rank toàn bộ process sau khi enrich memory metric để top list đúng thứ tự.
- [x] Run lint cho file đã thay đổi.

Acceptance Criteria:

- Top process ranking gần với Activity Monitor hơn trong các tiến trình tiêu tốn RAM lớn.
- Không làm hỏng parser/filter hiện có.

## Task 10 - Improve Memory Metric Fallback Coverage

Objective:

- Tăng khả năng đọc memory metric khi `proc_pid_rusage` bị giới hạn quyền trên một số process.

TODO:

- [x] Thêm fallback `proc_pidinfo(PROC_PIDTASKINFO)` lấy `pti_resident_size`.
- [x] Giữ fallback cuối cùng về metric từ snapshot process để không mất dữ liệu.
- [x] Run lint cho file đã thay đổi.
- [x] Run build check để đảm bảo compile/link ổn định.

Acceptance Criteria:

- Với process không lấy được footprint, app vẫn có metric đáng tin hơn `rss` đơn thuần.
- Top list ổn định hơn khi chạy lâu và giữa các quyền process khác nhau.

## Task 11 - Top Process Name Readability And Inspection

Objective:

- Làm tên process trong bảng dễ đọc và dễ đối chiếu với Activity Monitor khi command có path/space/args phức tạp.

TODO:

- [x] Cải thiện parse token executable đầu tiên để xử lý escape và quote trong command line.
- [x] Giữ ưu tiên hiển thị executable name thay vì cả command line dài.
- [x] Thêm tooltip full command cho từng dòng process để inspect chi tiết khi cần.
- [x] Run lint cho file đã thay đổi.
- [x] Run build check.

Acceptance Criteria:

- Các process có app path chứa khoảng trắng (vd Edge Helper) không bị cắt sai tên còn lại như `Microsoft`.
- Người dùng vẫn xem được full command line khi hover.

## Task 12 - Prevent System Process Under-Reporting

Objective:

- Tránh việc một số system process (như `WindowServer`) bị tụt top do metric fallback trả về thấp bất thường.

TODO:

- [x] Cập nhật metric chọn giá trị lớn nhất giữa `rss`, `phys_footprint`, `task resident`.
- [x] Giữ sorting top process theo metric đã chuẩn hóa.
- [x] Run lint file thay đổi.
- [x] Run build check.

Acceptance Criteria:

- Các process hệ thống lớn không bị mất khỏi top list chỉ vì một source metric under-report.
- Top list ổn định hơn khi dữ liệu từ API quyền thấp không nhất quán.

## Task 13 - Add `top` Memory Merge For Protected Processes

Objective:

- Bù khoảng trống khi `proc_pid_rusage`/`proc_pidinfo` bị `EPERM` với process system như `WindowServer`.

TODO:

- [x] Lấy snapshot memory từ `top -l 1 -o mem -stats pid,mem`.
- [x] Parse `pid -> bytes` và merge vào pipeline memory metric theo PID.
- [x] Chọn metric cuối bằng `max(rss, footprint, task resident, top mem)`.
- [x] Run lint file thay đổi.
- [x] Run build check.

Acceptance Criteria:

- Process như `WindowServer` vẫn xuất hiện đúng trong top list khi RSS/proc APIs không phản ánh đủ.
- Thứ tự top process gần Activity Monitor hơn trong môi trường user không root.

## Task 14 - One-Command Process Sampling Experiment

Objective:

- Thử phương án chỉ dùng một command (`top`) cho toàn bộ pipeline process snapshot để giảm complexity.

TODO:

- [x] Đổi `fetchProcesses` và `fetchTopProcesses` sang parse trực tiếp output `top`.
- [x] Giữ filter `includeRootUser` và `includeSystemUsers` như hiện tại.
- [x] Sắp xếp lại theo memory giảm dần và áp limit như cũ.
- [x] Run lint file thay đổi.
- [x] Run build check.

Acceptance Criteria:

- Runtime path chỉ dùng `top` (không gọi `ps` trong sampling flow).
- Top process có mặt `WindowServer` gần giống Activity Monitor trên máy local.

Decision Note:

- Sau thử nghiệm, chọn giữ phương án single-source `top` cho process sampling hiện tại.

## Task 15 - Docs and Parser Alignment Cleanup

Objective:

- Đồng bộ docs + test với kiến trúc runtime hiện tại (single-source `top`) và bỏ parser code thừa dễ gây hiểu nhầm.

TODO:

- [x] Cập nhật `docs/PLAN.md` để phản ánh default filter hiện tại (include all users).
- [x] Cập nhật `docs/DESCRIPTION.md` để phản ánh history chart hiện tại (Used là series chính, swap/pressure là status badges).
- [x] Xóa parser `ps` không còn dùng trong runtime để tránh drift về sau.
- [x] Chuyển test parser sang `TopProcessSnapshotParser`.
- [x] Run lint cho file Swift thay đổi.

Acceptance Criteria:

- Docs không còn mâu thuẫn với runtime behavior hiện tại.
- Test parser bám đúng source dữ liệu `top`.
- Không còn đoạn code parser `ps` không được dùng trong production flow.

## Execution Order

1. Task 1 (data correctness)
2. Task 2 (process list structure)
3. Task 3 (interaction UX)
4. Task 4 (copy/polish)
5. Task 5 (verification)
6. Task 6 (selected-user process filtering)
7. Task 7 (history chart readability)
8. Task 8 (full verification pass)
9. Task 9 (memory metric alignment)
10. Task 10 (metric fallback coverage)
11. Task 11 (top process readability)
12. Task 12 (system process under-reporting)
13. Task 13 (top memory merge)
14. Task 14 (one-command top sampling)
15. Task 15 (docs and parser alignment cleanup)

## Review Gates

- Sau mỗi task: cập nhật checklist, gửi commit message đề xuất, dừng để review.
