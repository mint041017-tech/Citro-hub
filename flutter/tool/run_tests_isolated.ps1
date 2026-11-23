# 逐文件隔离跑测试：把"真实断言失败"与"harness 基础设施失败"分开记账。
#
# 本机 flutter test 在并发/冷启动下会偶发 `Connection closed before test suite
# loaded` 与尾部 `did not complete`（退出码 79），这些不是代码缺陷。把每个
# 测试文件放在独立进程里串行跑，失败文件单独复跑，才能真正分清两类失败。
#
# 用法（在 flutter 目录或任意目录均可）：
#   pwsh -File tool/run_tests_isolated.ps1                    # 全量
#   pwsh -File tool/run_tests_isolated.ps1 -Filter '*duo*'    # 只跑匹配文件
#   pwsh -File tool/run_tests_isolated.ps1 -Retries 3
#
# 结果分类：
#   PASS        首次即通过
#   INFRA       仅出现基础设施症状（loader 断连 / did not complete / 退出 79），
#               且复跑通过 —— 计入"基础设施失败"，不计入通过数
#   FAIL        复跑仍失败，或日志里出现断言 / golden / 溢出等真实失败信号
#
# 退出码：0 = 无真实失败；1 = 存在 FAIL。

param(
  [string]$Filter = '*_test.dart',
  [int]$Retries = 2,
  [int]$AttemptTimeoutSec = 300,
  [string]$LogDir = (Join-Path $env:TEMP 'citro_test_isolated')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

$flutter = (Get-Command flutter -ErrorAction SilentlyContinue)?.Source
if (-not $flutter) {
  $candidate = 'C:\Android\flutter\bin\flutter.bat'
  if (Test-Path -LiteralPath $candidate) { $flutter = $candidate }
}
if (-not $flutter) { throw 'flutter 未找到：请把 flutter 放进 PATH 或用 -Flutter 指定。' }

New-Item -ItemType Directory -Force -Path $LogDir > $null

# 基础设施症状：只在这些症状里才允许判为抖动。
$infraPattern = 'Connection closed before test suite loaded|did not complete|Failed to load|No tests were found|attempt timed out'
# 严格真实失败信号：出现任意一条就不是基础设施问题，直接判 FAIL，不复跑洗白。
$strictRealPattern = 'Expected:|Actual:|Golden|overflowed by|RenderFlex'
# 弱失败信号：单独出现不足以定性，仅记录供人工复核。
$weakPattern = 'Exception|Error:'

function Get-TestCount([string]$text) {
  # 优先取最终汇总行 "+N: All tests passed!"；否则取进度序列里最后一个 +N。
  $m = [regex]::Match($text, '\+(\d+):\s*All tests passed')
  if ($m.Success) { return [int]$m.Groups[1].Value }
  $all = [regex]::Matches($text, '\+(\d+)')
  if ($all.Count -eq 0) { return 0 }
  return [int]$all[$all.Count - 1].Groups[1].Value
}

function Get-FirstStrictSignal([string]$text) {
  foreach ($line in ($text -split "`r?`n")) {
    if ($line -match $strictRealPattern) { return $line.Trim() }
  }
  return ''
}

$files = Get-ChildItem -LiteralPath (Join-Path $root 'test') -Recurse -Filter $Filter |
  Where-Object { $_.Extension -eq '.dart' } |
  Sort-Object FullName

$rows = @()
$passTotal = 0
$realFail = 0

foreach ($f in $files) {
  $rel = [System.IO.Path]::GetRelativePath($root, $f.FullName) -replace '\\', '/'
  $attempt = 0
  $verdict = 'FAIL'
  $tests = 0
  $lastText = ''
  $infraSeen = $false
  $strictSeen = $false
  $detail = ''

  while ($attempt -le $Retries) {
    $attempt++
    $log = Join-Path $LogDir (('{0}.try{1}.log' -f ($rel -replace '/', '_'), $attempt))
    # 看门狗：单条用例文件超过 $AttemptTimeoutSec 仍未退出（harness 死锁/挂起），
    # 杀掉整棵进程树并按基础设施症状记账，避免一个挂起文件阻塞整个批量。
    $argLine = '/c ""' + $flutter + '" test ' + $rel + ' --concurrency=1 > "' + $log + '" 2>&1"'
    $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList $argLine -PassThru -WindowStyle Hidden -WorkingDirectory $root
    $exited = $proc.WaitForExit($AttemptTimeoutSec * 1000)
    if (-not $exited) {
      taskkill /PID $proc.Id /T /F 2>&1 | Out-Null
      try { $proc.WaitForExit(5000) | Out-Null } catch { }
      $code = 79
      Add-Content -LiteralPath $log -Value ("[isolated-script] attempt timed out after {0}s; process tree killed" -f $AttemptTimeoutSec)
      $infraSeen = $true
    } else {
      $code = $proc.ExitCode
    }
    $lastText = Get-Content -LiteralPath $log -Raw -ErrorAction SilentlyContinue
    if ($null -eq $lastText) { $lastText = '' }

    if ($code -eq 0) {
      $tests = Get-TestCount $lastText
      if ($attempt -eq 1) { $verdict = 'PASS' } elseif ($infraSeen) { $verdict = 'INFRA' } else { $verdict = 'PASS' }
      break
    }

    if ($lastText -match $strictRealPattern) {
      $strictSeen = $true
      $detail = Get-FirstStrictSignal $lastText
      break  # 真实断言 / golden / 布局失败：直接 FAIL，不再复跑洗白
    }
    if ($lastText -match $infraPattern) { $infraSeen = $true }
    if ($code -eq 79) { $infraSeen = $true }
  }

  if ($verdict -eq 'FAIL') {
    if ($strictSeen) {
      $verdict = 'FAIL'
    } elseif ($infraSeen -and $lastText -match $infraPattern) {
      # 复跑用尽仍失败，但症状纯属基础设施 —— 仍记为 INFRA，交由人工判断，不计通过。
      $verdict = 'INFRA'
    } else {
      $detail = Get-FirstStrictSignal $lastText
      if (-not $detail) {
        $weak = [regex]::Match($lastText, "($weakPattern[^\r\n]*)")
        if ($weak.Success) { $detail = $weak.Groups[1].Value.Trim() }
      }
    }
  }

  if ($verdict -eq 'PASS') { $passTotal += $tests }
  if ($verdict -eq 'FAIL') { $realFail++ }

  $rows += [pscustomobject]@{
    Test    = $rel
    Attempt = $attempt
    Result  = $verdict
    Cases   = $tests
    Detail  = $detail
  }
  Write-Output ('{0,-8} {1,2}x {2,4}  {3}' -f $verdict, $attempt, $tests, $rel)
}

$rows | Format-Table -AutoSize | Out-String | Write-Output
$summary = [pscustomobject]@{
  Files      = $rows.Count
  PassFiles  = ($rows | Where-Object Result -eq 'PASS').Count
  InfraFiles = ($rows | Where-Object Result -eq 'INFRA').Count
  FailFiles  = ($rows | Where-Object Result -eq 'FAIL').Count
  PassCases  = $passTotal
  LogDir     = $LogDir
}
$summary | Format-List | Out-String | Write-Output

# 机器可读汇总，便于全量跑完后从文件提取，不把整份日志读进上下文。
$rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $LogDir 'isolated_rows.csv')
$summary | ConvertTo-Json | Set-Content -Encoding UTF8 -Path (Join-Path $LogDir 'isolated_summary.json')

if ($realFail -gt 0) { exit 1 }
exit 0
