#!/usr/bin/env python3
"""Áp thương hiệu AV-SOFT lên mã nguồn ONLYOFFICE đã tải về.

Dùng:  python3 build/apply_branding.py --work <thư mục chứa build_tools, desktop-apps, web-apps...>

- Chép các tệp trong overlay/ đè lên mã nguồn (biểu tượng, logo, màn hình chào, ảnh bộ cài…).
- Sinh win-linux/src/prop/defines_p.h (tên ứng dụng, định danh riêng, ngôn ngữ mặc định tiếng Việt).
- Sửa một số chuỗi văn bản (lời chào, tiêu đề, thông báo pháp lý trong "Về ứng dụng").
- Chạy lại nhiều lần được (khôi phục tệp gốc bằng git trước khi sửa).
- Xuất bản vá (git diff) vào <work>/avsoft-patches/ để công bố cùng mã nguồn (yêu cầu AGPL).
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent          # gốc kho avsoft-branding
OVERLAY = HERE / "overlay"
REPOS = ("desktop-apps", "web-apps", "desktop-sdk", "core", "sdkjs")

warnings: list[str] = []


def log(msg: str):
    print(f"[avsoft] {msg}", flush=True)


def git(repo: Path, *args: str, check=False) -> str:
    r = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True)
    if check and r.returncode != 0:
        raise RuntimeError(r.stderr)
    return r.stdout


def restore(repo: Path, rel: str):
    """Đưa tệp về bản gốc của ONLYOFFICE (nếu tệp có trong git)."""
    git(repo, "checkout", "--", rel)


def notice(brand: dict, style: str) -> str:
    text = (f"Modified by {brand['publisher']} on {brand['modified_date']}: branding for "
            f"{brand['product_name']} (based on {brand['upstream_name']} {brand['upstream_version']}).")
    return {"c": f"/* {text} */\n", "html": f"<!-- {text} -->\n", "m4": f"dnl {text}\n",
            "iss": f"; {text}\n"}[style]


def patch(work: Path, repo: str, rel: str, pairs: list[tuple[str, str]], brand: dict, style: str,
          critical: bool = False):
    path = work / repo / rel
    if not path.exists():
        warnings.append(f"Không thấy {repo}/{rel}")
        return
    restore(work / repo, rel)
    text = path.read_text(encoding="utf-8")
    for old, new in pairs:
        if old not in text:
            msg = f"Không tìm thấy chuỗi cần thay trong {repo}/{rel}: {old[:60]!r}"
            if critical:
                raise SystemExit("[avsoft] LỖI: " + msg)
            warnings.append(msg)
            continue
        text = text.replace(old, new)
    path.write_text(notice(brand, style) + text if style != "html" else _html_notice(text, brand), encoding="utf-8")
    log(f"đã sửa {repo}/{rel}")


def _html_notice(text: str, brand: dict) -> str:
    n = notice(brand, "html")
    i = text.find("\n") + 1 if text.lstrip().lower().startswith("<!doctype") else 0
    return text[:i] + n + text[i:]


def copy_overlay(work: Path):
    n = 0
    for src in OVERLAY.rglob("*"):
        if not src.is_file():
            continue
        rel = src.relative_to(OVERLAY)
        if rel.parts[0] not in REPOS:
            continue
        dst = work / rel
        if not (work / rel.parts[0]).exists():
            warnings.append(f"Bỏ qua {rel} (chưa có kho {rel.parts[0]})")
            continue
        if not dst.parent.exists():
            warnings.append(f"Thư mục đích không tồn tại, vẫn tạo: {dst.parent}")
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
        n += 1
    log(f"đã chép {n} tệp hình ảnh/tài nguyên thương hiệu")


def make_defines_p(work: Path, brand: dict):
    repo = work / "desktop-apps"
    rel = "win-linux/src/prop/defines_p.h"
    restore(repo, rel)
    orig = (repo / rel).read_text(encoding="utf-8")
    end = orig.find("*/")
    header = orig[: end + 2] if orig.lstrip().startswith("/*") and end > 0 else ""
    tpl = (HERE / "build" / "defines_p.h.in").read_text(encoding="utf-8")
    out = tpl.replace("{original_header}", header)
    for k, v in brand.items():
        out = out.replace("{" + k + "}", str(v))
    (repo / rel).write_text(out, encoding="utf-8")
    log(f"đã sinh desktop-apps/{rel}")


def legal_block(brand: dict) -> str:
    return (
        '<div class="about-field avsoft-legal" style="max-width:440px;line-height:1.45;font-size:11px;margin-top:10px;opacity:.85">'
        f'{brand["product_name"]} là phiên bản sửa đổi (ngày {brand["modified_date"]}) của '
        f'{brand["upstream_name"]} {brand["upstream_version"]} — phần mềm gốc do ONLYOFFICE / Ascensio System SIA phát triển. '
        'Phát hành theo giấy phép GNU AGPL v3 kèm các điều khoản bổ sung. '
        f'<a class="link" target="popup" href="{brand["source_url"]}">Mã nguồn</a> · '
        f'<a class="link" target="popup" href="{brand["license_url"]}">Giấy phép</a>'
        '</div>'
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--work", required=True, help="thư mục chứa build_tools và các kho ONLYOFFICE")
    ap.add_argument("--brand", default=str(HERE / "brand.json"))
    a = ap.parse_args()
    work = Path(a.work).resolve()
    brand = json.loads(Path(a.brand).read_text(encoding="utf-8"))
    if not (work / "desktop-apps").exists():
        raise SystemExit(f"[avsoft] Chưa có mã nguồn trong {work} (thiếu desktop-apps). Hãy chạy bước tải mã nguồn trước.")

    copy_overlay(work)
    make_defines_p(work, brand)

    # --- tên trong thông tin tệp .exe (Windows) - giữ nguyên dòng bản quyền của Ascensio System SIA
    patch(work, "desktop-apps", "win-linux/src/version.h", [
        ('"ONLYOFFICE Desktop Editors\\0"', f'"{brand["product_name"]} (based on ONLYOFFICE Desktop Editors)\\0"'),
        ('#define VER_PRODUCTNAME_STR         "ONLYOFFICE\\0"', f'#define VER_PRODUCTNAME_STR         "{brand["product_name"]}\\0"'),
    ], brand, "c")

    # --- trang khởi động: lời chào, tiêu đề, thông báo pháp lý trong "Về ứng dụng"
    patch(work, "desktop-apps", "common/loginpage/locale/vi.js", [
        ("welWelcome: 'Chào mừng đến với ONLYOFFICE Editors cho máy tính!'", f"welWelcome: '{brand['welcome_vi']}'"),
        ("welDescr: 'Làm việc với các tài liệu khi không kết nối mạng hay kết nối bộ công cụ với đám mây của bạn: ONLYOFFICE, ownCloud, Nextcloud.'",
         f"welDescr: '{brand['welcome_descr_vi']}'"),
    ], brand, "c")
    patch(work, "desktop-apps", "common/loginpage/src/locale.js", [
        ("welWelcome: 'Welcome to ONLYOFFICE Desktop Editors!'", f"welWelcome: '{brand['welcome_en']}'"),
    ], brand, "c")
    patch(work, "desktop-apps", "common/loginpage/src/index.html", [
        ("<title>Hello ONLYOFFICE Documents</title>", f"<title>{brand['product_name']}</title>"),
    ], brand, "html")
    patch(work, "desktop-apps", "common/loginpage/src/panelabout.js", [
        ('<div class="ver-copyright about-field">${_opts.rights}</div>',
         '<div class="ver-copyright about-field">${_opts.rights}</div>' + legal_block(brand)),
    ], brand, "c", critical=True)

    # --- gói Linux (dùng khi đóng gói bằng hệ thống của ONLYOFFICE)
    patch(work, "desktop-apps", "package/common/linux/defines.m4", [
        ("define(`_NAME',ONLYOFFICE)dnl", f"define(`_NAME',{brand['product_name']})dnl"),
        ("define(`_WM_CLASS',ONLYOFFICE)dnl", f"define(`_WM_CLASS',{brand['product_name']})dnl"),
    ], brand, "m4")

    # --- bộ cài Windows (Inno Setup) — sẽ kiểm thử khi dựng máy biên dịch Windows
    patch(work, "desktop-apps", "package/inno/defines.iss", [
        ('#define sCompanyName                    "ONLYOFFICE"', '#define sCompanyName                    "AVSOFT"'),
        ('#define sProductName                    "Desktop Editors"', '#define sProductName                    "Office"'),
        ('#define sAppName                        str(sCompanyName)', f'#define sAppName                        "{brand["product_name"]}"'),
        ('#define sAppPublisher                   "Ascensio System SIA"', f'#define sAppPublisher                   "{brand["publisher"]}"'),
        ('#define sAppPublisherURL                "https://www.onlyoffice.com/"', f'#define sAppPublisherURL                "{brand["site_url"]}"'),
        ('#define sAppSupportURL                  "https://www.onlyoffice.com/support.aspx"', f'#define sAppSupportURL                  "{brand["site_url"]}"'),
        ('#define sAppIconName                    "ONLYOFFICE"', f'#define sAppIconName                    "{brand["product_name"]}"'),
        ("#define sAppProtocol                    'oo-office'", "#define sAppProtocol                    'avsoft-office'"),
        ('#define APP_USER_MODEL_ID               "ASC.Documents.5"', '#define APP_USER_MODEL_ID               "AVSOFT.Office.1"'),
        ('#define APP_MUTEX_NAME                  "TEAMLAB"', '#define APP_MUTEX_NAME                  "AVSOFT_OFFICE"'),
        ('#define ASSC_APP_NAME                   "ONLYOFFICE"', f'#define ASSC_APP_NAME                   "{brand["product_name"]}"'),
        ('#define ASCC_REG_PREFIX                 "ASC"', '#define ASCC_REG_PREFIX                 "AVSOFT"'),
        ('#define ASCC_REG_REGISTERED_APP_NAME    "ONLYOFFICE Editors"', f'#define ASCC_REG_REGISTERED_APP_NAME    "{brand["product_name"]}"'),
        ('#define ASSOC_PROG_ID                   "ASC.Editors"', '#define ASSOC_PROG_ID                   "AVSOFT.Office"'),
        ('#define ASSOC_APP_FRIENDLY_NAME         "ONLYOFFICE Editors"', f'#define ASSOC_APP_FRIENDLY_NAME         "{brand["product_name"]}"'),
    ], brand, "iss")

    # --- xuất bản vá để công bố mã nguồn
    pdir = work / "avsoft-patches"
    pdir.mkdir(exist_ok=True)
    for repo in REPOS:
        if (work / repo).exists():
            diff = git(work / repo, "diff", "--binary")
            if diff.strip():
                (pdir / f"{repo}.patch").write_text(diff, encoding="utf-8")
    log(f"bản vá đã lưu tại {pdir}")

    if warnings:
        log("CẢNH BÁO (không chặn quá trình biên dịch):")
        for w in warnings:
            print("   - " + w)
    log("Áp thương hiệu xong.")


if __name__ == "__main__":
    sys.exit(main())
