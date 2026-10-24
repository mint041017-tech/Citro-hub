# Minimal dependency-free static file server (no Python/Node needed).
# Usage: powershell -File serve.ps1 -Root <dir> -Port 8019
param(
  [string]$Root = (Split-Path $PSScriptRoot -Parent),
  [int]$Port = 8019
)
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path $Root).Path

$mime = @{
  '.html'='text/html; charset=utf-8'; '.htm'='text/html; charset=utf-8';
  '.css'='text/css; charset=utf-8';   '.js'='application/javascript; charset=utf-8';
  '.json'='application/json; charset=utf-8'; '.svg'='image/svg+xml';
  '.jpg'='image/jpeg'; '.jpeg'='image/jpeg'; '.png'='image/png';
  '.webp'='image/webp'; '.gif'='image/gif'; '.ico'='image/x-icon';
  '.woff2'='font/woff2'; '.woff'='font/woff'; '.ttf'='font/ttf'; '.otf'='font/otf';
  '.mp4'='video/mp4'; '.m4v'='video/mp4'; '.webm'='video/webm'; '.mp3'='audio/mpeg'; '.m4a'='audio/mp4'; '.apk'='application/vnd.android.package-archive';
  '.txt'='text/plain; charset=utf-8'; '.map'='application/json'
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
$listener.Start()
Write-Output ("serving {0} at http://localhost:{1}/" -f $Root, $Port)

while ($true) {
  $client = $listener.AcceptTcpClient()
  try {
    $client.ReceiveTimeout = 5000
    $stream = $client.GetStream()
    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)
    $reqLine = $reader.ReadLine()
    while ($true) { $h = $reader.ReadLine(); if ([string]::IsNullOrEmpty($h)) { break } }
    if (-not $reqLine) { $client.Close(); continue }

    $parts = $reqLine.Split(' ')
    $method = $parts[0]
    $target = if ($parts.Length -gt 1) { $parts[1] } else { '/' }
    $target = $target.Split('?')[0]
    $rel = [System.Uri]::UnescapeDataString($target).TrimStart('/')
    if ([string]::IsNullOrEmpty($rel)) { $rel = 'index.html' }

    $full = Join-Path $Root $rel
    $full = [System.IO.Path]::GetFullPath($full)

    $status = '200 OK'
    $ctype = 'application/octet-stream'
    $body = $null
    if (-not $full.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $full -PathType Leaf)) {
      $status = '404 Not Found'
      $ctype = 'text/plain; charset=utf-8'
      $body = [System.Text.Encoding]::UTF8.GetBytes('404 Not Found')
    } else {
      $ext = [System.IO.Path]::GetExtension($full).ToLower()
      if ($mime.ContainsKey($ext)) { $ctype = $mime[$ext] }
      $body = [System.IO.File]::ReadAllBytes($full)
    }

    $head = "HTTP/1.1 $status`r`nContent-Type: $ctype`r`nContent-Length: $($body.Length)`r`nCache-Control: no-store`r`nConnection: close`r`n`r`n"
    $hb = [System.Text.Encoding]::ASCII.GetBytes($head)
    $stream.Write($hb, 0, $hb.Length)
    $stream.Write($body, 0, $body.Length)
    $stream.Flush()
  } catch {
    Write-Output ("ERR: " + $_.Exception.Message)
  } finally {
    try { $client.Close() } catch {}
  }
}
