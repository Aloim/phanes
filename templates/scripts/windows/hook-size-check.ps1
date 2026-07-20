# phanes-template v3.0.1 hook-size-check
# PostToolUse(Write|Edit) advisory. Reads the tool-call JSON from stdin and routes the touched file
# to the matching audit: a hot file (root CLAUDE.md or CLAUDE.local.md) runs register-check; a
# documentation file runs doc-index then doc-check; anything else runs loc-check on that file.
# Prints any warning into the transcript. Always exits 0.
$ErrorActionPreference = 'Stop'

function Find-PhanesRoot {
  param([string]$start)
  $d = $start
  while ($true) {
    if (Test-Path -LiteralPath (Join-Path $d '.phanes\config.json')) { return $d }
    $p = [System.IO.Path]::GetDirectoryName($d)
    if (-not $p -or $p -eq $d) { return $null }
    $d = $p
  }
}

try {
  # Run by hand instead of by a hook (stdin is a console, no tool-call JSON is coming): exit
  # cleanly rather than blocking forever on a read that never returns.
  if (-not [Console]::IsInputRedirected) { exit 0 }
  $raw = [Console]::In.ReadToEnd()
  if (-not $raw) { exit 0 }
  $data = $raw | ConvertFrom-Json
  $fp = $data.tool_input.file_path
  if (-not $fp) { exit 0 }

  $startDir = [System.IO.Path]::GetDirectoryName($fp)
  if (-not $startDir) { $startDir = (Get-Location).Path }
  $root = Find-PhanesRoot $startDir
  if (-not $root) { $root = Find-PhanesRoot (Get-Location).Path }
  if (-not $root) { exit 0 }

  $cfg = Get-Content -LiteralPath (Join-Path $root '.phanes\config.json') -Raw -Encoding utf8 | ConvertFrom-Json
  $docRoot = 'documentation'
  if ($cfg.docRoot) { $docRoot = $cfg.docRoot }

  $rootNorm = ((Resolve-Path -LiteralPath $root).Path -replace '\\', '/').TrimEnd('/')
  $fpNorm = ($fp -replace '\\', '/')
  $rel = $fpNorm
  if ($fpNorm.StartsWith($rootNorm, [System.StringComparison]::OrdinalIgnoreCase)) {
    $rel = $fpNorm.Substring($rootNorm.Length).TrimStart('/')
  }

  $out = $null
  if ($rel -eq 'CLAUDE.md' -or $rel -eq 'CLAUDE.local.md') {
    $s = Join-Path $PSScriptRoot 'register-check.ps1'
    if (Test-Path -LiteralPath $s) { $out = & $s }
  } elseif ($rel.StartsWith($docRoot.TrimEnd('/') + '/', [System.StringComparison]::OrdinalIgnoreCase)) {
    $di = Join-Path $PSScriptRoot 'doc-index.ps1'
    $dc = Join-Path $PSScriptRoot 'doc-check.ps1'
    if (Test-Path -LiteralPath $di) { & $di | Out-Null }
    if (Test-Path -LiteralPath $dc) { $out = & $dc }
  } else {
    $lc = Join-Path $PSScriptRoot 'loc-check.ps1'
    if (Test-Path -LiteralPath $lc) { $out = & $lc $fp }
  }

  if ($out) {
    foreach ($line in $out) {
      if ($line -and $line -notmatch '\[OK\]\s*$' -and $line -notmatch ':\s*OK\s*$') {
        Write-Output ("[phanes size-check] {0}" -f $line)
      }
    }
  }
  exit 0
} catch {
  exit 0
}
