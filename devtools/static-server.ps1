param([string]$RootB64 = '')
$ErrorActionPreference = 'Continue'
$diag = 'C:\Users\Administrator\serverdiag.txt'
[IO.File]::WriteAllText($diag, 'PSScriptRoot=[' + $PSScriptRoot + '] RootB64=[' + $RootB64 + ']')
$root = $null
if ($RootB64) {
  try { $root = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($RootB64)) } catch {}
}
if (-not $root -and $PSScriptRoot) {
  try { $root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path } catch {}
}
if (-not $root) { $root = (Get-Location).Path }
[IO.File]::AppendAllText($diag, "`r`nROOT=[" + $root + "]")
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add('http://127.0.0.1:8018/')
$listener.Start()
$mime = @{
  '.html'='text/html; charset=utf-8'; '.js'='text/javascript; charset=utf-8';
  '.json'='application/json; charset=utf-8'; '.css'='text/css; charset=utf-8';
  '.png'='image/png'; '.jpg'='image/jpeg'; '.jpeg'='image/jpeg'; '.gif'='image/gif';
  '.svg'='image/svg+xml'; '.ico'='image/x-icon'; '.txt'='text/plain; charset=utf-8';
  '.md'='text/plain; charset=utf-8'; '.whl'='application/octet-stream'; '.se1'='application/octet-stream';
  '.mp4'='video/mp4'; '.m4v'='video/mp4'; '.webm'='video/webm'; '.mp3'='audio/mpeg'; '.m4a'='audio/mp4'; '.apk'='application/vnd.android.package-archive'
}
while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  try {
    $path = $ctx.Request.Url.AbsolutePath
    if ($path -eq '/') { $path = '/index.html' }
    $rel = [Uri]::UnescapeDataString($path).TrimStart('/') -replace '/', '\'
    $file = Join-Path $root $rel
    if ((Test-Path -LiteralPath $file -PathType Leaf) -and ($file.StartsWith($root))) {
      $ext = [IO.Path]::GetExtension($file).ToLower()
      $ct = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' }
      $bytes = [IO.File]::ReadAllBytes($file)
      $ctx.Response.ContentType = $ct
      $ctx.Response.ContentLength64 = $bytes.Length
      $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
      $ctx.Response.StatusCode = 404
      $body = [Text.Encoding]::UTF8.GetBytes('404 not found: ' + $path)
      $ctx.Response.ContentType = 'text/plain; charset=utf-8'
      $ctx.Response.ContentLength64 = $body.Length
      $ctx.Response.OutputStream.Write($body, 0, $body.Length)
    }
  } catch { [IO.File]::AppendAllText($diag, "`r`nERR=" + $_.Exception.Message) }
  finally { $ctx.Response.OutputStream.Close() }
}
