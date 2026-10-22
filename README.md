# AV-SOFT Office — kho đổi thương hiệu

Biên dịch **ONLYOFFICE Desktop Editors 9.4.0** từ mã nguồn và đổi sang thương hiệu **AV-SOFT Office**:
tên, biểu tượng, màn hình chào, trang khởi động, bộ cài; ngôn ngữ mặc định tiếng Việt; cài song song được với ONLYOFFICE gốc.

```
avsoft-branding/
├── brand.json              Tên sản phẩm, phiên bản gốc, đường dẫn mã nguồn, câu chào… (sửa ở đây)
├── build/
│   ├── avsoft-build.sh     Script biên dịch một lệnh (Ubuntu 24.04 / WSL2)
│   ├── apply_branding.py   Áp thương hiệu lên mã nguồn ONLYOFFICE
│   ├── defines_p.h.in      Tên + định danh ứng dụng (C++)
│   └── linux/              Tệp .desktop, control cho gói .deb
├── overlay/                Hình ảnh thay thế (sinh tự động, cùng cấu trúc thư mục mã nguồn gốc)
├── assets/
│   ├── make_assets.py      Sinh lại toàn bộ hình ảnh từ logo
│   └── source/             Logo gốc, biểu tượng đã vector hoá, font Be Vietnam Pro
├── LICENSE                 AGPL v3 + điều khoản bổ sung của ONLYOFFICE
└── NOTICE.md               Thông báo sửa đổi (bắt buộc theo giấy phép)
```

## 1. Chuẩn bị máy biên dịch

- **Ubuntu 24.04 64-bit**, ≥ 4 nhân CPU, ≥ 8 GB RAM (+ swap 8 GB), **≥ 100 GB ổ SSD trống**, có Internet.
- Máy Windows dùng **WSL2**:
  1. PowerShell (Admin): `wsl --install -d Ubuntu-24.04`, khởi động lại, đặt tên/mật khẩu người dùng.
  2. Tăng RAM cho WSL nếu cần: tạo `%UserProfile%\.wslconfig` gồm
     ```
     [wsl2]
     memory=10GB
     swap=8GB
     processors=6
     ```
     rồi `wsl --shutdown`.
  3. Làm việc **trong ổ của Linux** (`~/…`), *không* đặt thư mục làm việc ở `/mnt/c` hay `/mnt/f` (rất chậm).

## 2. Biên dịch (một lệnh)

```bash
cd ~
# chép thư mục avsoft-branding vào ~ (hoặc git clone kho của công ty)
cd avsoft-branding
bash build/avsoft-build.sh
```

Các bước (chạy riêng được: `fetch`, `brand`, `build`, `package`):

| Bước | Việc | Thời gian ước tính |
|---|---|---|
| `fetch` | Cài công cụ (Qt 5.9.9, cmake, Node…), tải ~10 kho mã nguồn ONLYOFFICE | 30–60 phút |
| `brand` | Áp thương hiệu AV-SOFT | < 1 phút |
| `build` | Biên dịch C++ + giao diện web | 2–6 giờ (lần đầu) |
| `package` | Tạo gói `.deb` và bản chạy liền `.tar.gz` | vài phút |

Kết quả: `~/avsoft-build/dist/avsoft-office_9.4.0_amd64.deb` → cài thử: `sudo apt install ./avsoft-office_9.4.0_amd64.deb`.

Lỗi ở bước nào: xem `~/avsoft-build/logs/<bước>.log` (50 dòng cuối là đủ để chẩn đoán).
Sửa xong chạy lại đúng bước đó; muốn biên dịch nhanh sau khi chỉ đổi hình/chữ: `CLEAN=0 bash build/avsoft-build.sh build`.

## 3. Đổi logo / tên

1. Thay `assets/source/mark-trace.svg` (biểu tượng dạng vector) hoặc sửa màu trong `assets/make_assets.py`.
2. `pip install fonttools brotli cairosvg pillow && python3 assets/make_assets.py`
3. Sửa tên, câu chào, đường dẫn trong `brand.json`.
4. `bash build/avsoft-build.sh brand && CLEAN=0 bash build/avsoft-build.sh build && bash build/avsoft-build.sh package`

## 4. Cập nhật khi ONLYOFFICE ra phiên bản mới

1. Sửa `upstream_tag` / `upstream_version` trong `brand.json` (vd `v9.5.0.xxx`), thêm một dòng vào `NOTICE.md`.
2. Xoá `~/avsoft-build` (hoặc đặt `WORK` mới) rồi chạy lại `bash build/avsoft-build.sh`.
3. Nếu `apply_branding.py` báo "Không tìm thấy chuỗi cần thay" → ONLYOFFICE đã đổi mã ở chỗ đó, cần cập nhật script.

## 5. Tuân thủ giấy phép khi chia sẻ (bắt buộc)

Khi đưa bộ cài AV-SOFT Office cho người khác (kể cả bạn bè):
- **Công bố mã nguồn**: đưa kho `avsoft-branding` này lên GitHub công khai; kèm phiên bản gốc (`upstream_tag`) là đủ để
  tái tạo toàn bộ mã nguồn tương ứng. Có thể đính kèm thêm thư mục `avsoft-patches/` sinh ra khi biên dịch.
- Giữ nguyên `LICENSE`, `NOTICE.md` trong gói cài (script đã tự chép vào `/opt/avsoft-office/` và `/usr/share/doc/`).
- Mục **Về ứng dụng** đã hiển thị: phần mềm gốc là ONLYOFFICE (Ascensio System SIA), đây là bản sửa đổi, liên kết tới giấy phép và mã nguồn.
- **Không** dùng logo/nhãn hiệu ONLYOFFICE trong sản phẩm, tài liệu quảng bá.
- Cập nhật `source_url`, `license_url` trong `brand.json` thành địa chỉ kho GitHub thật trước khi phát hành.

## Trạng thái

- [x] Kho thương hiệu, hình ảnh, script biên dịch Linux, đóng gói .deb
- [ ] Biên dịch thử lần đầu trên máy thật
- [ ] Bộ cài Windows (Inno Setup) — đã chuẩn bị `defines.iss` và ảnh, chưa kiểm thử
- [ ] Plugin: mẫu NĐ 30, kiểm tra thể thức, đọc số thành chữ, OCR tiếng Việt
