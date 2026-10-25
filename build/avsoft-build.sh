#!/usr/bin/env bash
# =============================================================================
#  AV-SOFT Office — biên dịch từ mã nguồn ONLYOFFICE Desktop Editors + đổi thương hiệu
#
#  Máy: Ubuntu 24.04 64-bit (máy thật hoặc WSL2 trên Windows), >= 4 nhân, 8 GB RAM,
#       >= 100 GB ổ trống (SSD), có Internet, tài khoản có quyền sudo.
#
#  Dùng:   bash build/avsoft-build.sh            # chạy tất cả các bước
#          bash build/avsoft-build.sh fetch      # 1. cài công cụ + tải mã nguồn
#          bash build/avsoft-build.sh brand      # 2. áp thương hiệu AV-SOFT
#          bash build/avsoft-build.sh build      # 3. biên dịch (lâu nhất)
#          bash build/avsoft-build.sh package    # 4. đóng gói .deb + .tar.gz
#  Biến môi trường: WORK=~/avsoft-build (thư mục làm việc), CLEAN=1 (biên dịch lại từ đầu)
#  Nhật ký: $WORK/logs/*.log
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${WORK:-$HOME/avsoft-build}"
LOGS="$WORK/logs"
STEP="${1:-all}"
jq_() { python3 -c "import json,sys;print(json.load(open('$HERE/brand.json'))['$1'])"; }
TAG="$(jq_ upstream_tag)"
# build_tools: tiền tố "tags/" để checkout đúng tag và bỏ qua "git pull" (tag không phải nhánh)
BRANCH="tags/$TAG"
VERSION="$(jq_ upstream_version)"
PRODUCT="$(jq_ product_name)"
PKG="$(jq_ internal_name)"
REL="$(python3 -c "import json;print(json.load(open('$HERE/brand.json')).get('release',''))")"
# Số phiên bản gói: 9.4.0-avsoft.3 (dpkg coi là mới hơn 9.4.0 và 9.4.0-avsoft.2 -> nâng cấp được)
FULLVER="${VERSION}${REL:+-$REL}"
BT="$WORK/build_tools"
PY="$BT/tools/linux/python3/bin/python3"
QT_DIR="$BT/tools/linux/qt_build/Qt-5.9.9"

mkdir -p "$WORK" "$LOGS"
say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[LỖI] %s\033[0m\n' "$*"; exit 1; }
run_logged() { local name="$1"; shift; say "$name (nhật ký: $LOGS/$name.log)"; local t0=$SECONDS
  if ! "$@" 2>&1 | tee "$LOGS/$name.log"; then die "Bước '$name' thất bại — gửi 50 dòng cuối của $LOGS/$name.log để xử lý."; fi
  printf '   xong sau %d phút\n' $(( (SECONDS - t0) / 60 )); }

check_machine() {
  say "Kiểm tra máy"
  . /etc/os-release 2>/dev/null || true
  [[ "${ID:-}" == "ubuntu" ]] || warn "Khuyến nghị Ubuntu 24.04 (máy này: ${PRETTY_NAME:-không rõ})."
  [[ "${VERSION_ID:-}" == "24.04" ]] || warn "ONLYOFFICE kiểm thử trên Ubuntu 24.04; bản khác có thể lỗi."
  local cpu ram disk
  cpu=$(nproc); ram=$(awk '/MemTotal/{print int($2/1024/1024)}' /proc/meminfo); disk=$(df -BG --output=avail "$WORK" | tail -1 | tr -dc 0-9)
  echo "   CPU: $cpu nhân · RAM: ${ram} GB · Ổ trống tại $WORK: ${disk} GB"
  (( cpu >= 4 ))   || warn "Ít hơn 4 nhân: biên dịch sẽ rất lâu."
  (( ram >= 7 ))   || warn "RAM dưới 8 GB: nên bật swap >= 8 GB."
  (( disk >= 80 )) || die "Cần ít nhất 80-100 GB trống tại $WORK."
  sudo -v || die "Cần quyền sudo."
}

step_fetch() {
  check_machine
  say "Cài công cụ cơ bản"
  sudo apt-get update -q
  sudo apt-get install -y -q git python3 python3-pip curl wget dpkg-dev desktop-file-utils ninja-build >/dev/null
  if [[ ! -d "$BT/.git" ]]; then
    run_logged clone-build-tools git clone --depth 1 --branch "$TAG" https://github.com/ONLYOFFICE/build_tools.git "$BT"
  fi
  cd "$BT/tools/linux"
  [[ -d ./python3 ]] || run_logged python ./python.sh
  if [[ ! -f ./packages_complete ]]; then
    run_logged deps ./python3/bin/python3 ./deps.py
    run_logged cmake sudo ./cmake.sh
  fi
  [[ -d ./qt_build ]] || run_logged qt ./python3/bin/python3 ./qt_binary_fetch.py all
  [[ -d ./sysroot/ubuntu16-amd64-sysroot ]] || (cd sysroot && run_logged sysroot ../python3/bin/python3 ./fetch.py all)
  cd "$BT"
  run_logged configure-fetch "$PY" ./configure.py --branch "$BRANCH" --module desktop --sysroot 1 --update 1 --qt-dir "$QT_DIR"
  # chỉ tải/cập nhật mã nguồn các kho (chưa biên dịch) để còn áp thương hiệu trước khi biên dịch
  run_logged fetch-sources "$PY" - <<'PYEOF'
import sys
sys.path.append('scripts'); sys.path.append('scripts/core_common'); sys.path.append('scripts/core_common/modules')
import config, base
config.parse(); config.parse_defaults()
repos = base.get_repositories()
print("Kho cần tải:", ", ".join(sorted(repos)))
base.update_repositories(repos)
PYEOF
}

step_brand() {
  [[ -d "$WORK/desktop-apps" ]] || die "Chưa có mã nguồn — chạy bước fetch trước."
  run_logged brand python3 "$HERE/build/apply_branding.py" --work "$WORK"
}

step_build() {
  [[ -x "$PY" ]] || die "Chưa chuẩn bị công cụ — chạy bước fetch trước."
  cd "$BT"
  run_logged configure-build "$PY" ./configure.py --branch "$BRANCH" --module desktop --sysroot 1 \
      --update 0 --clean "${CLEAN:-1}" --qt-dir "$QT_DIR"
  # V8 (core/Common/3dParty/v8_89): build_tools gọi "./depot_tools/fetch" bằng đường dẫn tương đối;
  # depot_tools bản mới lấy DEPOT_TOOLS_DIR tương đối rồi cd vào thư mục con -> cipd không thấy
  # cipd_client_version.digests ("Platform linux-amd64 is not supported..."). Đặt đường dẫn tuyệt đối.
  local v8d="$WORK/core/Common/3dParty/v8_89"
  export DEPOT_TOOLS_DIR="$v8d/depot_tools"
  export DEPOT_TOOLS_UPDATE=0     # không tự cập nhật depot_tools giữa chừng (giữ các chỉnh sửa bên dưới)
  # build_tools ghim Python 3.8 cho depot_tools trên Linux, nhưng depot_tools hiện tại cần >= 3.9
  # (fetch.py: argparse.BooleanOptionalAction). Dùng bản 3.11.8 mà chính ONLYOFFICE ghim cho Windows.
  local py_old="version:2@3.8.10.chromium.23" py_new="version:2@3.11.8.chromium.35"
  sed -i "s/$py_old/$py_new/" "$BT/scripts/core_common/modules/v8_89.py"
  if [[ -f "$v8d/depot_tools/bootstrap/manifest.txt" ]] && grep -q "$py_old" "$v8d/depot_tools/bootstrap/manifest.txt"; then
    sed -i "s/$py_old/$py_new/" "$v8d/depot_tools/bootstrap/manifest.txt"
    rm -rf "$v8d/depot_tools/python3_bin_reldir.txt" "$v8d"/depot_tools/bootstrap-2@3.8.10*
  fi
  if [[ -d "$v8d" && ! -d "$v8d/v8" ]]; then
    rm -rf "$v8d/.gclient" "$v8d/.gclient_entries" "$v8d/.cipd"   # dọn lần tải V8 hỏng trước đó
  fi
  if [[ -x "$v8d/depot_tools/ensure_bootstrap" && ! -f "$v8d/depot_tools/python3_bin_reldir.txt" ]]; then
    run_logged depot-tools-bootstrap bash -c "cd '$v8d/depot_tools' && ./ensure_bootstrap"
  fi
  # depot_tools/ninja.py không còn kèm ninja -> dùng ninja của hệ thống (nằm sau depot_tools trong PATH)
  command -v ninja >/dev/null || sudo apt-get install -y -q ninja-build
  # build_tools đặt LD_LIBRARY_PATH = thư viện sysroot Ubuntu 16 (libstdc++ cũ) -> ninja của Ubuntu 24
  # báo "GLIBCXX_3.4.32 not found". Bọc ninja: tự nạp thư viện hệ thống, các lệnh con vẫn giữ môi trường sysroot.
  mkdir -p "$WORK/bin"
  cat > "$WORK/bin/ninja" <<'NINJA'
#!/bin/sh
exec /lib64/ld-linux-x86-64.so.2 --library-path /lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu /usr/bin/ninja "$@"
NINJA
  chmod +x "$WORK/bin/ninja"
  export PATH="$WORK/bin:$PATH"
  export GCLIENT_SUPPRESS_GIT_VERSION_WARNING=1
  # web-apps (Gruntfile.js): thay các liên kết/tên mặc định của ONLYOFFICE trong trình soạn thảo
  # (giữ nguyên PUBLISHER_NAME = Ascensio System SIA để ghi công nhà phát triển gốc)
  export APP_TITLE_TEXT="$PRODUCT" COMPANY_NAME="$(jq_ brand)"
  export PUBLISHER_URL="$(jq_ site_url)" SUPPORT_URL="$(jq_ feedback_url)" SUGGEST_URL="$(jq_ feedback_url)"
  export HELP_URL="$(jq_ help_url)" HELP_CENTER_WEB_EDITORS="$(jq_ help_url)"
  run_logged make "$PY" ./make.py
}

step_package() {
  local src
  src="$(ls -d "$BT"/out/linux_64/*/desktopeditors 2>/dev/null | head -1)"
  [[ -n "$src" && -x "$src/DesktopEditors" ]] || die "Không thấy bản biên dịch trong $BT/out/linux_64/*/desktopeditors"
  local deb="$WORK/dist/${PKG}_${FULLVER}_amd64" opt="/opt/$PKG"
  say "Đóng gói $PRODUCT $FULLVER"
  rm -rf "$deb"; mkdir -p "$deb$opt" "$deb/usr/bin" "$deb/usr/share/applications" "$deb/usr/share/doc/$PKG" "$deb/DEBIAN"
  cp -a "$src/." "$deb$opt/"
  cp "$HERE/LICENSE" "$HERE/NOTICE.md" "$deb$opt/"; cp "$HERE/LICENSE" "$HERE/NOTICE.md" "$deb/usr/share/doc/$PKG/"
  cat > "$deb/usr/bin/$PKG" <<EOF
#!/bin/sh
APP_PATH=$opt
export LD_LIBRARY_PATH=\$APP_PATH\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}
exec \$APP_PATH/DesktopEditors "\$@"
EOF
  chmod 755 "$deb/usr/bin/$PKG"
  for s in 16 24 32 48 64 128 256; do
    install -Dm644 "$HERE/overlay/desktop-apps/package/common/linux/icons/${s}x${s}.png" "$deb/usr/share/icons/hicolor/${s}x${s}/apps/$PKG.png"
  done
  install -Dm644 "$HERE/overlay/icons/avsoft-office.svg" "$deb/usr/share/icons/hicolor/scalable/apps/$PKG.svg"
  sed -e "s|@PKG@|$PKG|g" -e "s|@PRODUCT@|$PRODUCT|g" "$HERE/build/linux/avsoft-office.desktop.in" > "$deb/usr/share/applications/$PKG.desktop"
  local size; size=$(du -sk "$deb" | cut -f1)
  sed -e "s|@PKG@|$PKG|g" -e "s|@VERSION@|$FULLVER|g" -e "s|@SIZE@|$size|g" "$HERE/build/linux/control.in" > "$deb/DEBIAN/control"
  install -m755 "$HERE/build/linux/postinst" "$deb/DEBIAN/postinst"
  install -m755 "$HERE/build/linux/postrm" "$deb/DEBIAN/postrm"
  run_logged dpkg-deb dpkg-deb --build --root-owner-group "$deb"
  tar -C "$deb$opt/.." -czf "$WORK/dist/${PKG}_${FULLVER}_linux_x64_portable.tar.gz" "$(basename "$opt")"
  # Máy Windows + WSL2: tự chép kết quả sang ổ F (thư mục dự án) nếu có
  local proj="${PROJECT_DIR:-/mnt/f/IT/Bawaco/Office}"
  if [[ -d "$proj" ]]; then
    mkdir -p "$proj/dist" && cp -f "$deb.deb" "$WORK/dist/${PKG}_${FULLVER}_linux_x64_portable.tar.gz" "$proj/dist/" \
      && echo "   Đã chép kết quả sang $proj/dist"
  fi
  say "XONG"
  echo "   Gói cài:      $deb.deb"
  echo "   Bản chạy liền: $WORK/dist/${PKG}_${FULLVER}_linux_x64_portable.tar.gz"
  echo "   Cài thử:      sudo apt install $deb.deb   rồi mở '$PRODUCT' trong menu ứng dụng"
}

case "$STEP" in
  fetch)   step_fetch ;;
  brand)   step_brand ;;
  build)   step_build ;;
  package) step_package ;;
  all)     step_fetch; step_brand; step_build; step_package ;;
  *) die "Bước không hợp lệ: $STEP (dùng: all | fetch | brand | build | package)" ;;
esac
