# phanes-template v3.2 module-list
# Prints the configured module list, one per line, read from .phanes/config.json.
$ErrorActionPreference = 'Stop'

function Find-PhanesRoot {
  $d = (Get-Location).Path
  while ($true) {
    if (Test-Path -LiteralPath (Join-Path $d '.phanes\config.json')) { return $d }
    $p = [System.IO.Path]::GetDirectoryName($d)
    if (-not $p -or $p -eq $d) { return $null }
    $d = $p
  }
}

$root = Find-PhanesRoot
if (-not $root) { [Console]::Error.WriteLine('module-list: .phanes/config.json not found from this directory'); exit 1 }

$cfg = Get-Content -LiteralPath (Join-Path $root '.phanes\config.json') -Raw -Encoding utf8 | ConvertFrom-Json
if (-not $cfg.modules -or $cfg.modules.Count -eq 0) {
  Write-Output '(no modules configured)'
  exit 0
}
foreach ($m in $cfg.modules) { Write-Output $m }
exit 0
