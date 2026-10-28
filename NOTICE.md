# Thông báo sửa đổi / Modification notice

**AV-SOFT Office** là phiên bản sửa đổi của **ONLYOFFICE Desktop Editors**, phần mềm gốc do
**Ascensio System SIA** (ONLYOFFICE) phát triển — https://github.com/ONLYOFFICE/DesktopEditors

*AV-SOFT Office is a modified version of ONLYOFFICE Desktop Editors, originally developed by Ascensio System SIA.*

| Ngày | Phiên bản gốc | Người sửa | Nội dung sửa đổi |
|---|---|---|---|
| 2026-10-22 | ONLYOFFICE Desktop Editors 9.4.0 (`v9.4.0.131`) | AV-SOFT (BAWACO) | Đổi tên hiển thị, biểu tượng, màn hình chào, logo trang khởi động và bộ cài sang AV-SOFT; định danh riêng (thư mục dữ liệu, khoá registry, mutex) để cài song song với ONLYOFFICE; ngôn ngữ mặc định tiếng Việt; thêm thông báo pháp lý trong mục "Về ứng dụng". |
| 2026-10-23 | ONLYOFFICE Desktop Editors 9.4.0 (`v9.4.0.131`) | AV-SOFT (BAWACO) | Bỏ tài liệu Trợ giúp gốc khỏi gói; liên kết hỗ trợ/góp ý trỏ về kho AV-SOFT; mẫu văn bản mới tiếng Việt theo NĐ 30/2020 (Times New Roman 14, lề 20-20-30-15 mm); bổ sung khoảng 12.000 chuỗi giao diện tiếng Việt (`build/locale/`). |
| 2026-10-25 | ONLYOFFICE Desktop Editors 9.4.0 (`v9.4.0.131`) | AV-SOFT (BAWACO) | Bản Windows (bộ cài Inno tiếng Việt); tắt cập nhật tự động và đổi cổng nội bộ để chạy song song ONLYOFFICE; khoảng cách đoạn/dòng trong trình soạn thảo văn bản hiển thị theo pt như Word (NĐ 30). |
| 2026-10-26 | ONLYOFFICE Desktop Editors 9.4.0 (`v9.4.0.131`) | AV-SOFT (BAWACO) | Bộ cài Windows: tự đóng AV-SOFT đang chạy trước khi chép đè tệp, khoá cài đặt (SetupMutex) riêng, dịch tiếng Việt các thông báo bộ cài còn thiếu. |
| 2026-10-28 | ONLYOFFICE Desktop Editors 9.4.0 (`v9.4.0.131`) | AV-SOFT (BAWACO) | Đổi tên hiển thị trong thông tin tệp `DesktopEditors.exe`; bộ cài không xoá lối tắt "ONLYOFFICE Editors" trên màn hình chung (khi cài song song ONLYOFFICE); script đóng gói kiểm tra số bản phát hành trước khi tạo bộ cài. |

Chi tiết từng thay đổi: thư mục `overlay/` (tệp thay thế) và `build/apply_branding.py` (các chỗ sửa văn bản).
Bản vá dạng `git diff` được sinh tự động vào `<WORK>/avsoft-patches/` mỗi lần biên dịch.

## Giấy phép
- Mã nguồn: **GNU AGPL v3** kèm các điều khoản bổ sung của ONLYOFFICE — xem tệp `LICENSE`.
- Nội dung không phải mã (hình minh hoạ, bộ biểu tượng, tài liệu) của ONLYOFFICE: **CC BY-SA 4.0**.
- Biểu tượng và logo AV-SOFT trong `overlay/` và `assets/`: thuộc AV-SOFT.
- Tệp ngôn ngữ bộ cài (`overlay/desktop-apps/package/inno/avsoft-isl/*.isl`): từ Inno Setup (jrsoftware/issrc), giấy phép Inno Setup.
- Font Be Vietnam Pro (dùng để dựng chữ trong hình): SIL Open Font License 1.1 — `assets/source/fonts/OFL.txt`.
- Phần mềm **không** sử dụng nhãn hiệu, logo ONLYOFFICE; tên "ONLYOFFICE" chỉ xuất hiện để ghi nhận nhà phát triển gốc.
