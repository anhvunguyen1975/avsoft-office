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

Thư mục dự án nằm trên ổ 1 TB (`F:\IT\Bawaco\Office`, trong WSL là `/mnt/f/IT/Bawaco/Office`).
Mã nguồn và quá trình biên dịch phải đặt **trong ổ Linux** (`~`), chỉ dùng ổ F để chép vào/ra:

```bash
cd ~
cp /mnt/f/IT/Bawaco/Office/avsoft-branding.zip . && unzip -o avsoft-branding.zip
cd avsoft-branding
bash build/avsoft-build.sh
```

Biên dịch xong, gói `.deb` và bản `.tar.gz` được tự chép về `F:\IT\Bawaco\Office\dist\`.

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

## 6. Bản Windows (bộ cài .exe)

Biên dịch trên chính máy Windows 10/11 64-bit (≥ 80 GB trống, nên dùng ổ D:).

**Cài công cụ** (PowerShell *Run as Administrator*):
```powershell
reg add HKLM\SYSTEM\CurrentControlSet\Control\FileSystem /v LongPathsEnabled /t REG_DWORD /d 1 /f
winget install -e --id Git.Git
winget install -e --id Python.Python.3.11
winget install -e --id OpenJS.NodeJS.LTS
winget install -e --id JRSoftware.InnoSetup
winget install -e --id Kitware.CMake --version 3.31.8   # cần 3.25–3.x, KHÔNG dùng CMake 4
winget install -e --id StrawberryPerl.StrawberryPerl
winget install -e --id Microsoft.VisualStudio.2019.BuildTools --override "--wait --passive --norestart --installPath D:\VS2019BT --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --add Microsoft.VisualStudio.Component.Windows10SDK.19041"
py -m pip install aqtinstall
py -m aqt install-qt windows desktop 5.9.9 win64_msvc2017_64 -O D:\Qt
cmd /c mklink /J D:\Qt\5.9.9\msvc2019_64 D:\Qt\5.9.9\msvc2017_64
```
Thêm **Debugging Tools for Windows** (cần cho V8): *Control Panel → Programs and Features →
Windows Software Development Kit - Windows 10.0.19041 → Change → Change → đánh dấu "Debugging Tools for Windows"*.

**Biên dịch** (PowerShell Admin):
```powershell
cd D:\ ; git clone https://github.com/anhvunguyen1975/avsoft-office.git ; cd avsoft-office
powershell -ExecutionPolicy Bypass -File build\windows\avsoft-build-win.ps1 -Step check
powershell -ExecutionPolicy Bypass -File build\windows\avsoft-build-win.ps1
```
Kết quả: `D:\avsoft-win\dist\avsoft-office-9.4.0-x64-setup.exe` (tự chép sang `F:\IT\Bawaco\Office\dist\` nếu có ổ F).
Các bước chạy riêng: `-Step fetch | brand | build | package`; nhật ký ở `D:\avsoft-win\logs\`.

## Trạng thái

- [x] Kho thương hiệu, hình ảnh, script biên dịch Linux, đóng gói .deb
- [x] Biên dịch thử lần đầu trên máy thật (Linux, 23/10/2026)
- [ ] Bộ cài Windows (Inno Setup) — script `build/windows/avsoft-build-win.ps1`, đang chạy thử
- [ ] Plugin: mẫu NĐ 30, kiểm tra thể thức, đọc số thành chữ, OCR tiếng Việt
