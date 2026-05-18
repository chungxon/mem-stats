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

- [ ] Tách nguồn dữ liệu donut khỏi `topProcesses` hiển thị.
- [ ] Bổ sung phần "Unattributed/Other Used" để tổng slice hợp lệ khi thiếu coverage từ process list.
- [ ] Giữ quy tắc sort + merge tiny slices + free slice cuối.
- [ ] Bổ sung test cho tổng fraction/slice consistency.

Acceptance Criteria:

- Donut không còn lệch lớn với `Used / Total` summary.
- Tổng các slice luôn hợp lệ, không vượt tổng RAM.

## Task 2 - Align Top Processes With Spec

Objective:

- Đưa phần Top Processes về đúng kỳ vọng trong `docs/DESCRIPTION.md`.

TODO:

- [ ] Hiển thị đầy đủ tối đa top 8 process.
- [ ] Bổ sung cột PID.
- [ ] Rút gọn command thành process name dễ đọc, vẫn giữ metadata cần thiết.
- [ ] Giữ sorting theo RAM giảm dần.

Acceptance Criteria:

- UI process list dễ đọc, có PID/User/Process/Memory.
- Không còn mismatch count 8 nhưng chỉ render 5 dòng.

## Task 3 - Improve Donut Interaction UX

Objective:

- Hoàn thiện interaction layer cho donut theo description.

TODO:

- [ ] Thêm hover state cho slice (highlight/dim rõ ràng trên macOS).
- [ ] Thêm tooltip/overlay thông tin user + memory + percent.
- [ ] Bổ sung center label hoặc trạng thái tương đương để phản hồi trực quan.
- [ ] Đảm bảo click chọn/bỏ chọn vẫn ổn định.

Acceptance Criteria:

- Hover/click cho trải nghiệm rõ ràng, không gây nhảy trạng thái.
- Filter process theo selected user ổn định.

## Task 4 - Copy, Terminology, and Visual Polish

Objective:

- Chuẩn hóa microcopy và hoàn thiện UX detail.

TODO:

- [ ] Đổi "Tap a slice..." thành wording phù hợp desktop (`Click a slice...`).
- [ ] Rà lại text labels trong popover cho đồng nhất.
- [ ] Kiểm tra tương phản và readability với solid color surfaces hiện tại.

Acceptance Criteria:

- Wording đồng nhất ngữ cảnh macOS.
- Không còn text gây hiểu nhầm hành vi input.

## Task 5 - Verification and Environment Notes

Objective:

- Chốt verification rõ ràng để phân biệt lỗi code và lỗi local environment.

TODO:

- [ ] Run lint cho tất cả file đã thay đổi.
- [ ] Run unit test/build trong môi trường khả dụng.
- [ ] Ghi chú rõ nếu fail do signing certificate/team setup.

Acceptance Criteria:

- Có báo cáo kết quả lint/test/build minh bạch.
- Nếu fail do môi trường, có hướng xử lý cụ thể.

## Execution Order

1. Task 1 (data correctness)
2. Task 2 (process list structure)
3. Task 3 (interaction UX)
4. Task 4 (copy/polish)
5. Task 5 (verification)

## Review Gates

- Sau mỗi task: cập nhật checklist, gửi commit message đề xuất, dừng để review.
