$out = 'C:\Users\Administrator\psdiag.txt'
$lines = @(
  'PSVersion=' + $PSVersionTable.PSVersion.ToString(),
  'PSScriptRoot=[' + $PSScriptRoot + ']',
  'MyCommand=[' + $MyInvocation.MyCommand.Path + ']',
  'PWD=[' + (Get-Location).Path + ']'
)
[IO.File]::WriteAllLines($out, $lines)
