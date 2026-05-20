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

## Review Gates

- Sau mỗi task: cập nhật checklist, gửi commit message đề xuất, dừng để review.
