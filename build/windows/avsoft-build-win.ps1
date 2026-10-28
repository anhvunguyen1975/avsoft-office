# =============================================================================
#  AV-SOFT Office — biên dịch bản Windows từ mã nguồn ONLYOFFICE Desktop Editors + đổi thương hiệu
#
#  Cần cài sẵn (xem README, mục Windows):
#    Git, Python 3.11, Node.js LTS, Inno Setup 6, Visual Studio 2019 Build Tools (C++),
#    Windows 10 SDK 10.0.19041 + "Debugging Tools for Windows", Qt 5.9.9 msvc2017_64 (+ liên kết msvc2019_64)
#
#  Dùng (PowerShell, Run as Administrator):
#    powershell -ExecutionPolicy Bypass -File build\windows\avsoft-build-win.ps1            # tất cả các bước
#    powershell -ExecutionPolicy Bypass -File build\windows\avsoft-build-win.ps1 -Step check
#    ... -Step fetch | brand | build | package          (-Clean để biên dịch lại từ đầu)
#  Nhật ký: <Work>\logs\*.log
# =============================================================================
param(
    [ValidateSet("all", "check", "fetch", "brand", "build", "package")]
    [string]$Step = "all",
    [string]$Work = "D:\avsoft-win",
    [string]$QtDir = "D:\Qt\5.9.9",
    [string]$VsPath = "D:\VS2019BT\VC\Auxiliary\Build",
    [string]$ProjectDir = "F:\IT\Bawaco\Office",
    [switch]$Clean
)

$ErrorActionPreference = "Continue"
chcp 65001 > $null
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$env:PYTHONIOENCODING = "utf-8"

$Here  = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)      # gốc kho avsoft-office
$Brand = Get-Content "$Here\brand.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$Tag     = $Brand.upstream_tag                  # vd v9.4.0.131
$Branch  = "tags/$Tag"
$Version = $Tag.TrimStart("v")                  # 9.4.0.131
$BT   = "$Work\build_tools"
$Logs = "$Work\logs"
New-Item -ItemType Directory -Force -Path $Work, $Logs, "$Work\dist" | Out-Null

function Say($m)  { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "[!] $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "[LỖI] $m" -ForegroundColor Red; exit 1 }

# Chạy lệnh qua cmd (gộp stderr vào stdout để PowerShell 5.1 không coi là lỗi), ghi nhật ký
function Run([string]$Name, [string]$CmdLine, [string]$Dir = $null) {
    Say "$Name  (nhật ký: $Logs\$Name.log)"
    $t0 = Get-Date
    # ghi lệnh ra tệp .cmd để tránh lỗi trích dẫn tham số của PowerShell 5.1
    $bat = "$Work\_run.cmd"
    $lines = @("@echo off", "chcp 65001 >nul")
    if ($Dir) { $lines += "cd /d `"$Dir`"" }
    $lines += $CmdLine
    Set-Content -Path $bat -Value $lines -Encoding ASCII
    cmd /c "$bat 2>&1" | Tee-Object -FilePath "$Logs\$Name.log"
    $code = $LASTEXITCODE
    if ($code -ne 0) { Die "Bước '$Name' thất bại (mã $code) — gửi 50 dòng cuối của $Logs\$Name.log để xử lý." }
    Write-Host ("   xong sau {0:N0} phút" -f ((Get-Date) - $t0).TotalMinutes)
}

# ---------------------------------------------------------------- công cụ
function Find-Python {
    $py = (& py -3.11 -c "import sys;print(sys.executable)" 2>$null)
    if (-not $py) { $py = (& py -3 -c "import sys;print(sys.executable)" 2>$null) }
    if (-not $py -or -not (Test-Path $py)) { Die "Không thấy Python 3 (cài: winget install -e --id Python.Python.3.11)." }
    $dir = Split-Path $py
    # đặt Python thật lên đầu PATH (tránh lối tắt Microsoft Store tên 'python')
    $env:Path = "$dir;$dir\Scripts;$env:Path"
    return $py
}
function Find-Iscc {
    $cands = @("${env:ProgramFiles(x86)}\Inno Setup 6", "$env:ProgramFiles\Inno Setup 6", "$env:LOCALAPPDATA\Programs\Inno Setup 6")
    foreach ($c in $cands) { if (Test-Path "$c\ISCC.exe") { return $c } }
    return $null
}

function Ensure-Cmake {
    # Cần CMake 3.25 – 3.x: x265 không chạy với CMake 4, libheif (CMakePresets v6) cần >= 3.25.
    $vsRoot = Split-Path (Split-Path (Split-Path $VsPath))
    $cands = @("$env:ProgramFiles\CMake\bin", "${env:ProgramFiles(x86)}\CMake\bin",
               "$vsRoot\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin")
    $found = @()
    foreach ($d in $cands) {
        if (Test-Path "$d\cmake.exe") {
            $v = ((& "$d\cmake.exe" --version) | Select-Object -First 1) -replace "cmake version ", ""
            $p = $v.Split("."); $found += "$d ($v)"
            if ([int]$p[0] -eq 3 -and [int]$p[1] -ge 25) {
                $env:Path = "$d;$env:Path"; Write-Host "   CMake  : $d ($v)"; return $true
            }
        }
    }
    if ($found) { Warn ("CMake hiện có không phù hợp: " + ($found -join "; ")) }
    Warn "Cần CMake 3.25 – 3.31: winget uninstall -e --id Kitware.CMake ; winget install -e --id Kitware.CMake --version 3.31.8"
    return $false
}

function Ensure-Perl {
    # OpenSSL (Configure) cần Perl cho Windows; Perl đi kèm Git không dùng được
    foreach ($d in "C:\Strawberry\perl\bin", "C:\Strawberry\c\bin") { if (Test-Path $d) { $env:Path = "$d;$env:Path" } }
    $c = Get-Command perl -ErrorAction SilentlyContinue
    if ($c -and $c.Source -notlike "*\Git\*") { Write-Host "   Perl   : $($c.Source)"; return $true }
    Warn "Thiếu Perl cho Windows (cài: winget install -e --id StrawberryPerl.StrawberryPerl)"; return $false
}

function Ensure-Node {
    # web-apps dùng grunt; npm >= 11 chặn script cài đặt (gifsicle, jpegtran-bin, optipng-bin) -> dùng npm 10
    $env:Path = "$env:APPDATA\npm;$env:Path"
    $npmv = (& npm --version 2>$null)
    if (-not $npmv) { Warn "Thiếu Node.js/npm"; return $false }
    if ([int]($npmv.Split(".")[0]) -gt 10) {
        Write-Host "   npm $npmv -> cài npm 10 (bản mới chặn script cài đặt mà web-apps cần)"
        cmd /c "npm install -g npm@10 2>&1" | Out-Host
        $npmv = (& npm --version 2>$null)
    }
    if (-not (Get-Command grunt -ErrorAction SilentlyContinue)) {
        Write-Host "   cài grunt-cli"
        cmd /c "npm install -g grunt-cli 2>&1" | Out-Host
    }
    $g = Get-Command grunt -ErrorAction SilentlyContinue
    Write-Host "   npm    : $npmv · grunt: $(if ($g) { $g.Source } else { 'THIẾU' })"
    if ([int]($npmv.Split(".")[0]) -gt 10 -or -not $g) { Warn "Cần npm 10 và grunt-cli (npm install -g npm@10 grunt-cli)"; return $false }
    # node_modules đã cài bằng npm mới (thiếu chương trình nén ảnh) -> xóa để cài lại
    foreach ($nm in "$Work\web-apps\build\node_modules", "$Work\sdkjs\build\node_modules") {
        if ((Test-Path "$nm\gifsicle") -and -not (Test-Path "$nm\gifsicle\vendor")) {
            Write-Host "   xóa $nm (cài thiếu) để cài lại"; cmd /c "rmdir /s /q `"$nm`""
        }
    }
    return $true
}

function Step-Check {
    Say "Kiểm tra máy và công cụ"
    $ok = $true
    $script:PY = Find-Python
    Write-Host "   Python : $PY"
    foreach ($t in "git", "node", "npm") {
        $c = Get-Command $t -ErrorAction SilentlyContinue
        if ($c) { Write-Host ("   {0,-7}: {1}" -f $t, $c.Source) } else { Warn "Thiếu $t"; $ok = $false }
    }
    if (Test-Path "$VsPath\vcvarsall.bat") { Write-Host "   VS2019 : $VsPath" }
    else { Warn "Không thấy $VsPath\vcvarsall.bat (VS 2019 Build Tools chưa cài xong hoặc cài chỗ khác: dùng -VsPath)"; $ok = $false }
    if (Test-Path "$QtDir\msvc2019_64\bin\qmake.exe") { Write-Host "   Qt     : $QtDir\msvc2019_64" }
    else { Warn "Không thấy $QtDir\msvc2019_64\bin\qmake.exe (tạo liên kết: mklink /J ...\msvc2019_64 ...\msvc2017_64)"; $ok = $false }
    if (-not (Ensure-Cmake)) { $ok = $false }
    if (-not (Ensure-Perl)) { $ok = $false }
    $iscc = Find-Iscc
    if ($iscc) { Write-Host "   Inno   : $iscc" } else { Warn "Không thấy Inno Setup 6 (winget install -e --id JRSoftware.InnoSetup)"; $ok = $false }
    $dbg = "${env:ProgramFiles(x86)}\Windows Kits\10\Debuggers\x64\dbghelp.dll"
    if (Test-Path $dbg) { Write-Host "   SDK Debugging Tools: có" }
    else { Warn "Thiếu 'Debugging Tools for Windows' của Windows 10 SDK (cần để biên dịch V8) — xem README"; $ok = $false }
    $lp = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -ErrorAction SilentlyContinue).LongPathsEnabled
    if ($lp -ne 1) { Warn "Chưa bật LongPathsEnabled"; $ok = $false }
    $drive = (Get-Item $Work).PSDrive
    $free = [math]::Round($drive.Free / 1GB)
    Write-Host "   Ổ trống tại $Work : $free GB"
    if ($free -lt 80) { Warn "Nên có >= 80 GB trống"; $ok = $false }
    $cpu = (Get-CimInstance Win32_Processor | Measure-Object NumberOfLogicalProcessors -Sum).Sum
    $ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    Write-Host "   CPU: $cpu luồng · RAM: $ram GB"
    git config --global core.longpaths true | Out-Null
    if (-not $ok) { Die "Máy chưa đủ điều kiện — xử lý các dòng [!] ở trên rồi chạy lại." }
}

function Configure([string]$Update, [string]$CleanOpt) {
    return "`"$PY`" configure.py --branch $Branch --module desktop --platform win_64 " +
           "--update $Update --clean $CleanOpt --qt-dir `"$QtDir`" --vs-version 2019 --vs-path `"$VsPath`""
}

function Step-Fetch {
    if (-not (Test-Path "$BT\.git")) {
        Run "clone-build-tools" "git clone --depth 1 --branch $Tag https://github.com/ONLYOFFICE/build_tools.git `"$BT`""
    }
    Run "configure-fetch" (Configure "1" "0") $BT
    # chỉ tải mã nguồn các kho (chưa biên dịch) để áp thương hiệu trước
    $fetchPy = @"
import sys
sys.path.append('scripts'); sys.path.append('scripts/core_common'); sys.path.append('scripts/core_common/modules')
import config, base
config.parse(); config.parse_defaults()
repos = base.get_repositories()
print('Kho can tai:', ', '.join(sorted(repos)))
base.update_repositories(repos)
"@
    Set-Content -Path "$Work\fetch_sources.py" -Value $fetchPy -Encoding ASCII
    Run "fetch-sources" "`"$PY`" `"$Work\fetch_sources.py`"" $BT
}

function Step-Brand {
    if (-not (Test-Path "$Work\desktop-apps")) { Die "Chưa có mã nguồn — chạy bước fetch trước." }
    Run "brand" "`"$PY`" `"$Here\build\apply_branding.py`" --work `"$Work`""
}

function Step-Build {
    if (-not (Test-Path "$BT\configure.py")) { Die "Chưa có build_tools — chạy bước fetch trước." }
    # Thay các liên kết/tên mặc định ONLYOFFICE trong trình soạn thảo (web-apps/Gruntfile.js)
    $env:APP_TITLE_TEXT = $Brand.product_name
    $env:COMPANY_NAME   = $Brand.brand
    $env:PUBLISHER_URL  = $Brand.site_url
    $env:SUPPORT_URL    = $Brand.feedback_url
    $env:SUGGEST_URL    = $Brand.feedback_url
    $env:HELP_URL       = $Brand.help_url
    $env:HELP_CENTER_WEB_EDITORS = $Brand.help_url
    # V8 / depot_tools
    $env:DEPOT_TOOLS_DIR = "$Work\core\Common\3dParty\v8_89\depot_tools"
    $env:DEPOT_TOOLS_WIN_TOOLCHAIN = "0"
    # V8 (build/vs_toolchain.py) chỉ tự tìm VS 2019 ở C:\Program Files (x86); chỉ đường tới bản cài trên ổ D:
    $env:vs2019_install = Split-Path (Split-Path (Split-Path $VsPath))
    $env:GYP_MSVS_VERSION = "2019"
    $env:GCLIENT_SUPPRESS_GIT_VERSION_WARNING = "1"
    $v8d = "$Work\core\Common\3dParty\v8_89"
    if ((Test-Path $v8d) -and -not (Test-Path "$v8d\v8")) {
        Remove-Item -Force -Recurse -ErrorAction SilentlyContinue "$v8d\.gclient", "$v8d\.gclient_entries", "$v8d\.cipd"
    }
    if (-not (Ensure-Cmake)) { Die "Cần CMake 3.x để biên dịch (xem dòng [!] ở trên)." }
    if (-not (Ensure-Perl)) { Die "Cần Perl để biên dịch OpenSSL (xem dòng [!] ở trên)." }
    if (-not (Ensure-Node)) { Die "Cần npm 10 và grunt-cli (xem dòng [!] ở trên)." }
    # OpenSSL lỗi âm thầm (thiếu Perl) vẫn để lại thư mục build rỗng -> xóa để build lại
    $ossl = "$Work\core\Common\3dParty\openssl\build\win_64"
    if ((Test-Path $ossl) -and -not (Test-Path "$ossl\include\openssl\sha.h")) {
        Remove-Item -Recurse -Force $ossl; Write-Host "   đã xóa bản OpenSSL build dở để build lại"
    }
    # xóa cấu hình CMake dở dang của lần chạy lỗi trước (heif/x265, libde265, libheif)
    Get-ChildItem "$Work\core\Common\3dParty\heif\*\build" -Recurse -Filter CMakeCache.txt -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-Item -Force $_.FullName; Remove-Item -Recurse -Force "$($_.DirectoryName)\CMakeFiles" -ErrorAction SilentlyContinue }
    # build_tools gọi trực tiếp "./make.py" cho brotli/harfbuzz: trên Windows sẽ mở tệp bằng trình soạn thảo
    # (theo liên kết tệp .py) thay vì chạy. Sửa thành "python ./make.py".
    foreach ($m in "oo_brotli.py", "harfbuzz.py") {
        $f = "$BT\scripts\core_common\modules\$m"
        if (Test-Path $f) {
            $t = [IO.File]::ReadAllText($f)
            $t2 = $t.Replace(', "./make.py")', ', "python", ["./make.py"])')
            if ($t2 -ne $t) { [IO.File]::WriteAllText($f, $t2); Write-Host "   đã sửa $m (chạy make.py bằng python)" }
        }
    }
    $cleanOpt = if ($Clean) { "1" } else { "0" }
    Run "configure-build" (Configure "0" $cleanOpt) $BT
    # nmake chỉ dịch lại tài nguyên .rc khi chính tệp .rc đổi, không theo dõi version.h mà nó #include
    # (avsoft.6 lần đầu: DesktopEditors.exe vẫn mang tên ONLYOFFICE) -> chạm vào các tệp .rc để luôn dịch lại.
    foreach ($rc in "$Work\desktop-apps\win-linux\extras\projicons\version.rc", "$Work\desktop-apps\win-linux\version.rc") {
        if (Test-Path $rc) { (Get-Item $rc).LastWriteTime = Get-Date }
    }
    Run "make" "`"$PY`" make.py" $BT
}

function Step-Package {
    $exe = Get-ChildItem -Path "$BT\out\win_64" -Recurse -Filter "DesktopEditors.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $exe) { Die "Không thấy bản biên dịch (DesktopEditors.exe) trong $BT\out\win_64" }
    $src = $exe.DirectoryName
    Write-Host "   Bản biên dịch: $src"
    # Chặn đóng gói khi chưa biên dịch lại sau khi tăng "release" trong brand.json
    # (avsoft.5 từng bị: bộ cài mới nhưng "Về ứng dụng" vẫn ghi avsoft.4)
    if ($Brand.release) {
        $want = "$($Brand.upstream_version)-$($Brand.release)"
        $idx = Join-Path $src "index.html"
        if (-not (Test-Path $idx) -or -not (Select-String -Path $idx -SimpleMatch "Bản phát hành: $want." -Encoding UTF8 -Quiet)) {
            Die "Bản biên dịch chưa phải $want (trang Về ứng dụng còn số cũ). Chạy lại: -Step brand, rồi -Step build, rồi -Step package."
        }
        Write-Host "   Đúng bản phát hành: $want"
    }
    # DesktopEditors.exe (đích của lối tắt / liên kết tệp) phải mang tên AV-SOFT
    $pn = (Get-Item (Join-Path $src "DesktopEditors.exe")).VersionInfo.ProductName
    if ($pn -ne $Brand.product_name) {
        Die "DesktopEditors.exe còn tên `"$pn`" (chưa dịch lại projicons). Chạy lại -Step build rồi -Step package."
    }
    $iscc = Find-Iscc
    if (-not $iscc) { Die "Không thấy Inno Setup 6." }
    $env:INNOPATH = $iscc
    $pkg = "$Work\desktop-apps\package"
    Copy-Item -Force "$Here\LICENSE", "$Here\NOTICE.md" "$src\" -ErrorAction SilentlyContinue
    # không phát hành dịch vụ cập nhật (trùng tên dịch vụ của ONLYOFFICE; gỡ AV-SOFT có thể xóa nhầm dịch vụ đó)
    Remove-Item -Force "$src\updatesvc.exe" -ErrorAction SilentlyContinue
    Run "package-prepare" "powershell -NoProfile -ExecutionPolicy Bypass -File make.ps1 -Version $Version -Arch x64 -SourceDir `"$src`"" $pkg
    Run "package-inno"    "powershell -NoProfile -ExecutionPolicy Bypass -File make_inno.ps1 -Version $Version -Arch x64" $pkg
    $out = Get-ChildItem "$pkg\inno\*.exe" | Where-Object { $_.Name -notlike "vc_redist*" } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $out) { Die "Không thấy tệp .exe bộ cài trong $pkg\inno" }
    $rel = if ($Brand.release) { "-$($Brand.release)" } else { "" }
    $final = "$Work\dist\$($Brand.internal_name)-$($Brand.upstream_version)$rel-x64-setup.exe"
    Copy-Item -Force $out.FullName $final
    Say "XONG"
    Write-Host "   Bộ cài: $final"
    if (Test-Path $ProjectDir) {
        New-Item -ItemType Directory -Force -Path "$ProjectDir\dist" | Out-Null
        Copy-Item -Force $final "$ProjectDir\dist\"
        Write-Host "   Đã chép sang $ProjectDir\dist"
    }
}

$PY = Find-Python
switch ($Step) {
    "check"   { Step-Check }
    "fetch"   { Step-Check; Step-Fetch }
    "brand"   { Step-Brand }
    "build"   { Step-Build }
    "package" { Step-Package }
    "all"     { Step-Check; Step-Fetch; Step-Brand; Step-Build; Step-Package }
}
