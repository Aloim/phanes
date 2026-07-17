# phanes-template v2.6 hook-stamp-guard
# PreToolUse(Write) guard. Reads the tool-call JSON from stdin. Denies (exit 2) creation of a NEW
# file under a stamped tree whose content lacks the required header stamp, so new files must go
# through `phanes new-file`. Every other call passes (exit 0). Fails open on any parse trouble.
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
  $raw = [Console]::In.ReadToEnd()
  if (-not $raw) { exit 0 }
  $data = $raw | ConvertFrom-Json

  $fp = $data.tool_input.file_path
  if (-not $fp) { exit 0 }
  $content = [string]$data.tool_input.content

  # Only NEW files are guarded.
  if (Test-Path -LiteralPath $fp) { exit 0 }

  $startDir = [System.IO.Path]::GetDirectoryName($fp)
  if (-not $startDir) { $startDir = (Get-Location).Path }
  # Walk up from the file location, or the current directory, to locate the project root.
  $root = Find-PhanesRoot $startDir
  if (-not $root) { $root = Find-PhanesRoot (Get-Location).Path }
  if (-not $root) { exit 0 }

  $rootNorm = ((Resolve-Path -LiteralPath $root).Path -replace '\\', '/').TrimEnd('/')
  $fpNorm = ($fp -replace '\\', '/')
  if (-not $fpNorm.StartsWith($rootNorm, [System.StringComparison]::OrdinalIgnoreCase)) { exit 0 }
  $rel = $fpNorm.Substring($rootNorm.Length).TrimStart('/')

  $cfg = Get-Content -LiteralPath (Join-Path $root '.phanes\config.json') -Raw -Encoding utf8 | ConvertFrom-Json
  $stamped = @('src', 'tests', 'documentation')
  if ($cfg.stampedTrees) { $stamped = $cfg.stampedTrees }
  if ($cfg.docRoot) { $stamped += $cfg.docRoot }
  if ($cfg.modules) { $stamped += $cfg.modules }

  $guarded = $false
  foreach ($t in $stamped) {
    $tn = ($t -replace '\\', '/').Trim('/')
    if ($tn -eq '') { continue }
    if ($rel -eq $tn -or $rel.StartsWith($tn + '/', [System.StringComparison]::OrdinalIgnoreCase)) { $guarded = $true; break }
  }
  if (-not $guarded) { exit 0 }

  $hasSource = $content -match 'Soft size threshold: 500 LOC'
  $hasDoc = $content -match '<!--\s*DOC\s*\|'
  if ($hasSource -or $hasDoc) { exit 0 }

  [Console]::Error.WriteLine("New files must be created via ``phanes new-file`` $([char]0x2014) the stamp is what ``regen-registry`` slices modules by; bypassing it produces silent API-baseline drift.")
  exit 2
} catch {
  # Never wedge the session on a parse or IO error.
  exit 0
}
