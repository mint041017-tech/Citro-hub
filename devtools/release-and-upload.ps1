# release-and-upload.ps1 — 一键出 Android / Windows 包并上传 OBS
#
# 在仓库根目录运行（需要 Windows + PowerShell）：
#   powershell -NoProfile -ExecutionPolicy Bypass -File devtools\release-and-upload.ps1
#
# 只出包不上传：加 -BuildOnly
# 只上传已有产物：加 -UploadOnly
#
# 前置（缺哪样都会在对应步骤报错，不会静默跳过）：
#   - Node（跑构建脚本）
#   - Android SDK + JDK 17+（build.js release 需要）
#   - VS 2022「使用 C++ 的桌面开发」工作负载 + Inno Setup 6（build_windows.js 需要）
#   - flutter/android/app/key.properties 与 Android key/citro-release.jks（签名）
param(
  [switch]$BuildOnly,
  [switch]$UploadOnly
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$flutter = Join-Path $root 'flutter'

# 版本号只从 pubspec.yaml 读，避免脚本里写死。
$pub = Get-Content (Join-Path $flutter 'pubspec.yaml') -Raw
if ($pub -notmatch '(?m)^version:\s*(\d+\+\d+)\s*$') {
  throw '无法从 flutter/pubspec.yaml 读取 version'
}
$full = $Matches[1]
$ver = ($full -split '\+')[0]
$code = ($full -split '\+')[1]

$apk = "APK/Citro-v$ver-release.apk"
$setup = "exe/Citro-v$ver-win64-setup.exe"

Write-Host "版本 $ver (versionCode $code)" -ForegroundColor Green
Write-Host ""

if (-not $UploadOnly) {
  Write-Host '== 1/2 Android release（arm64 + 正式签名） ==' -ForegroundColor Cyan
  Set-Location $flutter
  node build.js release
  if ($LASTEXITCODE -ne 0) { throw "Android 构建失败（exit $LASTEXITCODE）" }
  Set-Location $root
  if (-not (Test-Path (Join-Path $root $apk))) { throw "没找到 $apk" }
  Write-Host ""

  Write-Host '== 2/2 Windows release + Inno Setup 安装包 ==' -ForegroundColor Cyan
  Set-Location $flutter
  node tool/build_windows.js
  if ($LASTEXITCODE -ne 0) { throw "Windows 构建失败（exit $LASTEXITCODE）" }
  Set-Location $root
  if (-not (Test-Path (Join-Path $root $setup))) { throw "没找到 $setup" }
  Write-Host ""
}

if ($BuildOnly) {
  Write-Host '已按 -BuildOnly 跳过上传。' -ForegroundColor Yellow
  exit 0
}

foreach ($pair in @(@('APK', $apk), @('exe', $setup))) {
  $dir = $pair[0]
  $file = $pair[1]
  if (-not (Test-Path (Join-Path $root $file))) {
    throw "找不到 $file，无法上传"
  }
  Write-Host "== 上传 $file → OBS 的 $dir/ ==" -ForegroundColor Cyan
  node devtools/upload-obs.mjs $dir (Join-Path $root $file) (Join-Path $root "$dir/update.json")
  if ($LASTEXITCODE -ne 0) { throw "上传 $file 失败（exit $LASTEXITCODE）" }
  Write-Host "   https://obs.chimu-claw.xyz/$dir/$(Split-Path $file -Leaf)" -ForegroundColor Green
  Write-Host ""
}

Write-Host '全部完成。' -ForegroundColor Green
Write-Host '提醒：更新清单里的 url 指向 OBS，App 内更新靠它拉包。' -ForegroundColor Yellow
