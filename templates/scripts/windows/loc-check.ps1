# phanes-template v3.0 loc-check
# Scans tracked source files and prints any over the 500 LOC soft ceiling with line counts.
# With file arguments, checks only those files (this is how hook-size-check invokes it).
# Advisory: always exits 0.
$ErrorActionPreference = 'Stop'
$SOFT_CEILING = 500

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
if (-not $root) { [Console]::Error.WriteLine('loc-check: .phanes/config.json not found from this directory'); exit 0 }

$cfg = Get-Content -LiteralPath (Join-Path $root '.phanes\config.json') -Raw -Encoding utf8 | ConvertFrom-Json
$docRoot = 'documentation'
if ($cfg.docRoot) { $docRoot = $cfg.docRoot }

function Normalize([string]$p) { return ($p -replace '\\', '/') }

# Build the file list: explicit arguments, or all git-tracked files under the project root.
$files = @()
if ($args.Count -gt 0) {
  foreach ($a in $args) {
    $full = $a
    if (-not [System.IO.Path]::IsPathRooted($a)) { $full = Join-Path $root $a }
    if (Test-Path -LiteralPath $full) { $files += (Resolve-Path -LiteralPath $full).Path }
  }
} else {
  Push-Location $root
  try {
    $tracked = & git ls-files 2>$null
  } finally {
    Pop-Location
  }
  if ($tracked) {
    foreach ($rel in $tracked) {
      $full = Join-Path $root $rel
      if (Test-Path -LiteralPath $full) { $files += $full }
    }
  }
}

$rootNorm = Normalize((Resolve-Path -LiteralPath $root).Path)
$docPrefix = $rootNorm.TrimEnd('/') + '/' + $docRoot.TrimEnd('/') + '/'
$phanesPrefix = $rootNorm.TrimEnd('/') + '/.phanes/'

$offenders = 0
foreach ($f in $files) {
  $fn = Normalize((Resolve-Path -LiteralPath $f).Path)
  # loc-check owns source; documentation is doc-check's domain, .phanes/ is machinery.
  if ($fn.StartsWith($docPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
  if ($fn.StartsWith($phanesPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
  # Skip obvious binaries by extension.
  $ext = [System.IO.Path]::GetExtension($fn).ToLower()
  if ($ext -in @('.png', '.jpg', '.jpeg', '.gif', '.ico', '.pdf', '.zip', '.exe', '.dll', '.bin', '.woff', '.woff2', '.ttf')) { continue }
  $lines = 0
  try { $lines = (Get-Content -LiteralPath $f | Measure-Object -Line).Lines } catch { continue }
  if ($lines -gt $SOFT_CEILING) {
    $relOut = $fn
    if ($fn.StartsWith($rootNorm)) { $relOut = $fn.Substring($rootNorm.Length).TrimStart('/') }
    Write-Output ("OVER-CEILING: {0} ({1} lines, soft ceiling {2})" -f $relOut, $lines, $SOFT_CEILING)
    $offenders++
  }
}

if ($offenders -eq 0) { Write-Output 'loc-check: OK' }
exit 0
