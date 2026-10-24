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
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
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
    # heif/x265 cần CMake; ưu tiên bản cài riêng, nếu không có thì dùng bản đi kèm VS 2019
    $vsRoot = Split-Path (Split-Path (Split-Path $VsPath))
    foreach ($d in @("$env:ProgramFiles\CMake\bin", "$vsRoot\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin")) {
        if ((-not (Get-Command cmake -ErrorAction SilentlyContinue)) -and (Test-Path "$d\cmake.exe")) { $env:Path = "$d;$env:Path" }
    }
    $c = Get-Command cmake -ErrorAction SilentlyContinue
    if ($c) { Write-Host "   CMake  : $($c.Source)"; return $true }
    Warn "Thiếu CMake (cài: winget install -e --id Kitware.CMake)"; return $false
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
    if (-not (Ensure-Cmake)) { Die "Cần CMake để biên dịch." }
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
    Run "make" "`"$PY`" make.py" $BT
}

function Step-Package {
    $exe = Get-ChildItem -Path "$BT\out\win_64" -Recurse -Filter "DesktopEditors.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $exe) { Die "Không thấy bản biên dịch (DesktopEditors.exe) trong $BT\out\win_64" }
    $src = $exe.DirectoryName
    Write-Host "   Bản biên dịch: $src"
    $iscc = Find-Iscc
    if (-not $iscc) { Die "Không thấy Inno Setup 6." }
    $env:INNOPATH = $iscc
    $pkg = "$Work\desktop-apps\package"
    Copy-Item -Force "$Here\LICENSE", "$Here\NOTICE.md" "$src\" -ErrorAction SilentlyContinue
    Run "package-prepare" "powershell -NoProfile -ExecutionPolicy Bypass -File make.ps1 -Version $Version -Arch x64 -SourceDir `"$src`"" $pkg
    Run "package-inno"    "powershell -NoProfile -ExecutionPolicy Bypass -File make_inno.ps1 -Version $Version -Arch x64" $pkg
    $out = Get-ChildItem "$pkg\inno\*.exe" | Where-Object { $_.Name -notlike "vc_redist*" } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $out) { Die "Không thấy tệp .exe bộ cài trong $pkg\inno" }
    $final = "$Work\dist\$($Brand.internal_name)-$($Brand.upstream_version)-x64-setup.exe"
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
