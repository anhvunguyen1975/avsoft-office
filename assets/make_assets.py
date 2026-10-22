#!/usr/bin/env python3
"""Sinh toàn bộ hình ảnh thương hiệu AV-SOFT Office (SVG/PNG/ICO) vào thư mục overlay/.

Đầu vào: assets/source/mark-trace.svg (biểu tượng đã vector hoá từ logo gốc) + font Be Vietnam Pro.
Chạy:   python3 assets/make_assets.py          (cần: pip install fonttools brotli cairosvg pillow)
"""
from __future__ import annotations

import io
import re
from pathlib import Path

import cairosvg
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "source"
OUT = ROOT / "overlay"

BRAND = "AV-SOFT"
PRODUCT = "AV-SOFT Office"
C1, C2 = "#15B7FF", "#4A55FF"          # dải màu của logo gốc (xanh lơ -> tím xanh)
INK, INK_DARK = "#3A3A55", "#FFFFFF"

# ------------------------------------------------------------------ biểu tượng (mark)
_trace = (SRC / "mark-trace.svg").read_text()
MARK_D = re.search(r'<path d="([^"]+)"', _trace, re.S).group(1).replace("\n", " ")
MARK_W, MARK_H = 1300.0, 1080.0                       # khung của bản trace (đã có lề)
MARK_BOX = (95.0, 55.0, 1205.0, 1025.0)               # vùng thực có nét (ước lượng, dùng để canh giữa)


def mark(x: float, y: float, h: float, fill: str = "url(#avg)") -> str:
    """Biểu tượng cao h (theo vùng có nét), đặt góc trên-trái tại (x, y)."""
    bx0, by0, bx1, by1 = MARK_BOX
    s = h / (by1 - by0)
    tx, ty = x - bx0 * s, y - by0 * s
    return (f'<g transform="translate({tx:.3f},{ty:.3f}) scale({s:.5f})">'
            f'<g transform="translate(0,{MARK_H}) scale(0.1,-0.1)"><path fill="{fill}" d="{MARK_D}"/></g></g>')


def mark_width(h: float) -> float:
    bx0, by0, bx1, by1 = MARK_BOX
    return (bx1 - bx0) * h / (by1 - by0)


def grad(id_: str = "avg", c1: str = C1, c2: str = C2) -> str:
    return (f'<linearGradient id="{id_}" x1="0" y1="0" x2="1" y2="0">'
            f'<stop offset="0" stop-color="{c1}"/><stop offset="1" stop-color="{c2}"/></linearGradient>')


# ------------------------------------------------------------------ chữ -> đường path
_FONTS: dict[int, list[TTFont]] = {}


def fonts(weight: int) -> list[TTFont]:
    if weight not in _FONTS:
        _FONTS[weight] = [TTFont(SRC / "fonts" / f"be-vietnam-pro-{sub}-{weight}-normal.woff2")
                          for sub in ("latin", "vietnamese")]
    return _FONTS[weight]


def text_path(text: str, x: float, y: float, size: float, weight: int = 700, fill: str = INK,
              anchor: str = "start", letter: float = 0.0) -> tuple[str, float]:
    """Trả về (svg <path>, độ rộng). y = đường chân chữ (baseline)."""
    fs = fonts(weight)
    upm = fs[0]["head"].unitsPerEm
    k = size / upm
    glyphs = []
    width = 0.0
    for ch in text:
        for f in fs:
            cmap = f.getBestCmap()
            if ord(ch) in cmap:
                gname = cmap[ord(ch)]
                adv = f["hmtx"][gname][0]
                glyphs.append((f, gname, width))
                width += adv * k + letter
                break
        else:
            width += size * 0.3
    width -= letter if text else 0
    if anchor == "middle":
        x -= width / 2
    elif anchor == "end":
        x -= width
    d = []
    for f, gname, off in glyphs:
        pen = SVGPathPen(f.getGlyphSet())
        tpen = TransformPen(pen, (k, 0, 0, -k, x + off, y))
        f.getGlyphSet()[gname].draw(tpen)
        d.append(pen.getCommands())
    return f'<path fill="{fill}" d="{" ".join(d)}"/>', width


def svg(w: float, h: float, body: str, defs: str = "") -> str:
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w:g}" height="{h:g}" viewBox="0 0 {w:g} {h:g}" fill="none">'
            f'<defs>{defs}</defs>{body}</svg>')


def write(rel: str, content: str | bytes):
    p = OUT / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(content, str):
        p.write_text(content, encoding="utf-8")
    else:
        p.write_bytes(content)


def png(svg_text: str, w: int, h: int) -> bytes:
    return cairosvg.svg2png(bytestring=svg_text.encode(), output_width=w, output_height=h)


# ------------------------------------------------------------------ các tài sản
def wordmark(color: str, w=85, h=20, gid=None) -> str:
    """Logo ngang 85x20: biểu tượng + 'AV-SOFT' (thanh tab/tiêu đề của ứng dụng)."""
    mh = 15.0
    body = mark(1.0, (h - mh) / 2, mh)
    tp, _ = text_path(BRAND, 1.0 + mark_width(mh) + 4.0, 14.6, 12.2, 700, color, letter=0.2)
    body += tp
    return f'<g id="{gid}">{body}</g>' if gid else body


def app_icon_svg(size=256, bg=None, pad=0.04) -> str:
    inner = size * (1 - 2 * pad)
    mh = inner / (mark_width(1) if mark_width(1) > 1 else 1)
    mh = min(inner, inner / mark_width(1.0) * 1.0)
    mw = mark_width(mh)
    body = ""
    if bg:
        body += f'<rect width="{size}" height="{size}" rx="{size*0.22:.1f}" fill="{bg}"/>'
    body += mark((size - mw) / 2, (size - mh) / 2, mh)
    return svg(size, size, body, grad())


def build():
    D = "desktop-apps/win-linux/res/icons/"
    # 1) logo thanh tab (sprite có 2 nhóm id logo-dark / logo-light như bản gốc)
    sprite = svg(85, 20, wordmark(INK, gid="logo-dark") + wordmark(INK_DARK, gid="logo-light"), grad())
    write(D + "logo.svg", sprite)
    for name, col in (("logo_light", INK), ("logo_dark", INK_DARK)):
        s = svg(85, 20, wordmark(col), grad())
        write(D + f"{name}.svg", s)
        for sc, suf in ((1, ""), (1.25, "@1.25x"), (1.5, "@1.5x"), (1.75, "@1.75x"), (2, "@2x")):
            write(D + f"{name}{suf}.png", png(s, round(85 * sc), round(20 * sc)))

    # 2) màn hình chào 500x250
    body = '<rect width="500" height="250" fill="#fff"/><rect x="0.5" y="0.5" width="499" height="249" stroke="#D0D0DA"/>'
    mh = 84
    body += mark(250 - mark_width(mh) / 2, 40, mh)
    t1, w1 = text_path("AV-SOFT", 0, 0, 30, 700, C2)
    t2, w2 = text_path(" Office", 0, 0, 30, 500, INK)
    x0 = 250 - (w1 + w2) / 2
    body += text_path("AV-SOFT", x0, 168, 30, 700, C2)[0] + text_path(" Office", x0 + w1, 168, 30, 500, INK)[0]
    body += text_path("Bộ ứng dụng văn phòng · Văn bản · Bảng tính · Trình chiếu · PDF", 250, 195, 11.5, 400, "#6B6B80", "middle")[0]
    body += text_path("Phiên bản sửa đổi dựa trên ONLYOFFICE Desktop Editors (Ascensio System SIA) · AGPL v3", 250, 232, 9, 400, "#9A9AAA", "middle")[0]
    write(D + "splash.svg", svg(500, 250, body, grad()))

    # 3) biểu tượng ứng dụng
    icon = app_icon_svg(256)
    write(D + "app-icon_64.png", png(icon, 64, 64))
    big = Image.open(io.BytesIO(png(icon, 256, 256)))
    ico = io.BytesIO()
    big.save(ico, format="ICO", sizes=[(s, s) for s in (16, 20, 24, 32, 40, 48, 64, 96, 128, 256)])
    write(D + "desktopeditors.ico", ico.getvalue())
    for s in (16, 24, 32, 48, 64, 128, 256):
        write(f"desktop-apps/package/common/linux/icons/{s}x{s}.png", png(icon, s, s))
    write("icons/avsoft-office.svg", icon)
    write("icons/avsoft-office-256.png", png(icon, 256, 256))

    # 4) logo trang chủ / Về ứng dụng (52x45)
    L = "desktop-apps/common/loginpage/res/img/"
    mh = 43
    m = svg(52, 45, mark(26 - mark_width(mh) / 2, 1, mh), grad())
    write(L + "idx-logo-light.svg", m)
    write(L + "idx-logo-dark.svg", m)

    # 5) trình soạn thảo (web-apps): logo đầu trang + khối "Dựa trên ONLYOFFICE" trong hộp Giới thiệu
    W = "web-apps/apps/common/main/resources/img/"
    write(W + "header/header-logo_s.svg", svg(85, 20, wordmark(INK_DARK), grad()))
    write(W + "header/dark-logo_s.svg", svg(85, 20, wordmark(INK), grad()))
    # Không dùng logo (nhãn hiệu) ONLYOFFICE: thay bằng chữ thường để vẫn ghi nhận nhà phát triển gốc
    for name, col in (("logo_s.svg", "#444"), ("logo-white_s.svg", "#fff")):
        t, _ = text_path("Dựa trên ONLYOFFICE · Ascensio System SIA", 122.5, 28, 13, 500, col, "middle")
        write(W + "about/" + name, svg(245, 45, t))

    # 6) ảnh bộ cài Windows (Inno Setup)
    I = "desktop-apps/package/inno/res/"
    tall = [(164, 314), (202, 386), (240, 459), (290, 556), (315, 604), (366, 700), (416, 797)]
    small = [58, 71, 103, 112, 129, 147]
    for theme, bg, fg in (("Light", "#F4F6FF", INK), ("Dark", "#1E2030", INK_DARK)):
        for w, h in tall:
            mh = w * 0.42
            b = f'<rect width="{w}" height="{h}" fill="{bg}"/>' + mark((w - mark_width(mh)) / 2, h * 0.30, mh)
            b += text_path("AV-SOFT", w / 2, h * 0.30 + mh + w * 0.17, w * 0.13, 700, C2, "middle")[0]
            b += text_path("Office", w / 2, h * 0.30 + mh + w * 0.30, w * 0.10, 500, fg, "middle")[0]
            write(I + f"WizImage-{theme}-{w}x{h}.png", png(svg(w, h, b, grad()), w, h))
        for s in small:
            b = f'<rect width="{s}" height="{s}" fill="{bg}"/>' + mark((s - mark_width(s * 0.7)) / 2, s * 0.15, s * 0.7)
            write(I + f"WizSmallImage-{theme}-{s}x{s}.png", png(svg(s, s, b, grad()), s, s))

    # 7) ảnh xem trước cho tài liệu
    preview = svg(520, 160, mark(10, 20, 120) +
                  text_path("AV-SOFT", 170, 92, 54, 700, C2)[0] + text_path("Office", 170, 140, 40, 500, INK)[0], grad())
    write("icons/preview.svg", preview)
    write("icons/preview.png", png(preview, 1040, 320))


if __name__ == "__main__":
    build()
    n = sum(1 for _ in OUT.rglob("*") if _.is_file())
    print(f"Đã sinh {n} tệp vào {OUT}")
