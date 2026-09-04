# phaneslight-template v3.7.1 list-apis
# Prints the API baseline entries for one module to stdout.
# Reads the machine baseline at .phaneslight/registry/<module>.json (produced by regen-registry).
# Sub-agents call this as a tool; they do not load the whole baseline into context.
$ErrorActionPreference = 'Stop'

function Find-PhanesLightRoot {
  $d = (Get-Location).Path
  while ($true) {
    if (Test-Path -LiteralPath (Join-Path $d '.phaneslight\config.json')) { return $d }
    $p = [System.IO.Path]::GetDirectoryName($d)
    if (-not $p -or $p -eq $d) { return $null }
    $d = $p
  }
}

if ($args.Count -lt 1) { [Console]::Error.WriteLine('list-apis: usage: phaneslight list-apis <module>'); exit 1 }
$module = $args[0]

$root = Find-PhanesLightRoot
if (-not $root) { [Console]::Error.WriteLine('list-apis: .phaneslight/config.json not found from this directory'); exit 1 }

$baseline = Join-Path $root ('.phaneslight\registry\' + $module + '.json')
if (-not (Test-Path -LiteralPath $baseline)) {
  [Console]::Error.WriteLine("list-apis: no baseline for '$module'. Run: phaneslight regen-registry $module")
  exit 1
}

Get-Content -LiteralPath $baseline -Raw -Encoding utf8 | Write-Output
exit 0
