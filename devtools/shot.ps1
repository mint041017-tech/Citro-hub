# shot.ps1 — 把 Citro 窗口置前并截到 scr-3.1.67/<name>.png
param(
  [Parameter(Mandatory=$true)][string]$Name,
  [int]$SleepMs = 900
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$h = Get-Process Citro | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $h) { Write-Error 'Citro 窗口不在了'; exit 1 }
$sig = @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
'@
Add-Type -MemberDefinition $sig -Name WinShot -Namespace ApiShot | Out-Null
[ApiShot.WinShot]::SetForegroundWindow($h.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds $SleepMs
$r = New-Object ApiShot.WinShot+RECT
[ApiShot.WinShot]::GetWindowRect($h.MainWindowHandle, [ref]$r) | Out-Null
$w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
$bmp = New-Object System.Drawing.Bitmap $w, $ht
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
$bmp.Save("C:/webflu/Citro/scr-3.1.67/$Name.png")
$g.Dispose(); $bmp.Dispose()
Write-Host "saved $Name ($w x $ht)"
