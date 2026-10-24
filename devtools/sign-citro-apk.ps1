# sign-citro-apk.ps1 - Sign an unsigned Citro release APK (after restoring the keystore)
#
# Usage (from anywhere):
#   powershell -NoProfile -ExecutionPolicy Bypass -File devtools/sign-citro-apk.ps1 `
#     -Keystore "密钥/chimu-release.jks" -StorePassword "***" -KeyAlias "***" -KeyPassword "***"
#
# Default input : kotlin/app/build/outputs/apk/stable/release/app-stable-release-unsigned.apk
# Default output: APK/Citro-v<versionName>-release.apk (versionName read from aapt2 badging)
#
# IMPORTANT: use the SAME keystore as previous releases
# (CN=Chimu Crew, SHA-256 30a30b98...413654), otherwise existing users
# cannot upgrade (install fails with signature mismatch).
param(
  [string]$Apk = '',
  [Parameter(Mandatory = $true)][string]$Keystore,
  [Parameter(Mandatory = $true)][string]$StorePassword,
  [Parameter(Mandatory = $true)][string]$KeyAlias,
  [Parameter(Mandatory = $true)][string]$KeyPassword,
  [string]$Out = ''
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$sdk = 'C:\Android\Sdk'
$bt = Get-ChildItem (Join-Path $sdk 'build-tools') -Directory |
  Sort-Object { [int]($_.Name -replace '\..*$') } -Descending |
  Select-Object -First 1
if (-not $bt) { throw 'Android build-tools not found (C:\Android\Sdk\build-tools)' }
$zipalign = Join-Path $bt.FullName 'zipalign.exe'
$apksigner = Join-Path $bt.FullName 'apksigner.bat'
$aapt2 = Join-Path $bt.FullName 'aapt2.exe'

if (-not $Apk) {
  $Apk = Join-Path $repo 'kotlin\app\build\outputs\apk\stable\release\app-stable-release-unsigned.apk'
}
if (-not (Test-Path $Apk)) { throw "Unsigned APK not found: $Apk" }

$keystorePath = $Keystore
if (-not (Test-Path $keystorePath)) {
  $candidate = Join-Path $repo $Keystore
  if (Test-Path $candidate) { $keystorePath = $candidate }
}
if (-not (Test-Path $keystorePath)) { throw "Keystore not found: $Keystore" }

# Read versionName from the APK (fallback: timestamp)
$version = 'x'
try {
  $badging = & $aapt2 dump badging $Apk 2>$null
  $line = $badging | Select-String -Pattern "versionName='([^']+)'" | Select-Object -First 1
  if ($line) { $version = $line.Matches[0].Groups[1].Value }
} catch { }

if (-not $Out) { $Out = Join-Path $repo ("APK\Citro-v$version-release.apk") }
New-Item -ItemType Directory -Force (Split-Path -Parent $Out) | Out-Null

$tmp = Join-Path $env:TEMP ('citro-sign-' + [guid]::NewGuid().ToString('N') + '.apk')
try {
  & $zipalign -f -p 4 $Apk $tmp
  if ($LASTEXITCODE -ne 0) { throw 'zipalign failed' }

  & $apksigner sign --ks $keystorePath --ks-pass ("pass:" + $StorePassword) --key-pass ("pass:" + $KeyPassword) --ks-key-alias $KeyAlias --out $Out $tmp
  if ($LASTEXITCODE -ne 0) { throw 'apksigner sign failed' }

  $certLine = & $apksigner verify --print-certs $Out 2>$null | Select-String 'SHA-256 digest' | Select-Object -First 1
  $size = [math]::Round((Get-Item $Out).Length / 1MB, 2)
  Write-Output "OK: signed -> $Out ($size MB)"
  if ($certLine) { Write-Output ("    " + $certLine) }
} finally {
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
