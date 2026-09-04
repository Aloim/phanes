# phaneslight-template v3.7.1 loc-check
# Scans tracked source files and prints any over the 500 LOC soft ceiling with line counts.
# With file arguments, checks only those files (this is how hook-size-check invokes it).
# Advisory: always exits 0.
$ErrorActionPreference = 'Stop'
$SOFT_CEILING = 500

function Find-PhanesLightRoot {
  $d = (Get-Location).Path
  while ($true) {
    if (Test-Path -LiteralPath (Join-Path $d '.phaneslight\config.json')) { return $d }
    $p = [System.IO.Path]::GetDirectoryName($d)
    if (-not $p -or $p -eq $d) { return $null }
    $d = $p
  }
}

$root = Find-PhanesLightRoot
if (-not $root) { [Console]::Error.WriteLine('loc-check: .phaneslight/config.json not found from this directory'); exit 0 }

$cfg = $null
try {
  $cfg = Get-Content -LiteralPath (Join-Path $root '.phaneslight\config.json') -Raw -Encoding utf8 | ConvertFrom-Json
} catch {
  [Console]::Error.WriteLine('loc-check: .phaneslight/config.json is malformed, using defaults')
  $cfg = $null
}
$docRoot = 'documentation'
if ($cfg.docRoot) { $docRoot = $cfg.docRoot }
# A trailing slash in docRoot would otherwise leak into every derived path and message.
$docRoot = ([string]$docRoot).TrimEnd('/', '\')
if (-not $docRoot) { $docRoot = 'documentation' }

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
  } catch {
    $tracked = $null
    [Console]::Error.WriteLine('loc-check: not a git repository, nothing to scan')
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
$phaneslightPrefix = $rootNorm.TrimEnd('/') + '/.phaneslight/'

$offenders = 0
foreach ($f in $files) {
  $fn = Normalize((Resolve-Path -LiteralPath $f).Path)
  # loc-check owns source; documentation is doc-check's domain, .phaneslight/ is machinery.
  if ($fn.StartsWith($docPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
  if ($fn.StartsWith($phaneslightPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
  # Skip obvious binaries by extension.
  $ext = [System.IO.Path]::GetExtension($fn).ToLower()
  if ($ext -in @('.png', '.jpg', '.jpeg', '.gif', '.ico', '.pdf', '.zip', '.exe', '.dll', '.bin', '.woff', '.woff2', '.ttf')) { continue }
  $lines = 0
  try { $lines = @(Get-Content -LiteralPath $f -Encoding utf8).Count } catch { continue }
  if ($lines -gt $SOFT_CEILING) {
    $relOut = $fn
    if ($fn.StartsWith($rootNorm)) { $relOut = $fn.Substring($rootNorm.Length).TrimStart('/') }
    Write-Output ("OVER-CEILING: {0} ({1} lines, soft ceiling {2})" -f $relOut, $lines, $SOFT_CEILING)
    $offenders++
  }
}

# A terminating count line, always (v3.6.1). The offender list can run to dozens of lines, and a
# reader who sees only the tail of it -- a truncated transcript, a scrolled terminal, a hook that
# surfaced the last few lines -- has no way to know how many lines came before. That is not
# hypothetical: a run counted 12 OVER-CEILING lines off a truncated tail when 19 had been printed,
# and wrote the 12 into a document. The count is now the LAST thing printed, so the tail carries it.
# Exit stays 0: this check is advisory by design, the ceiling is soft, and a non-zero exit here
# would fail the pre-commit hook and CI on a threshold nobody intended as a gate.
if ($offenders -eq 0) {
  Write-Output 'loc-check: OK'
} else {
  Write-Output ("loc-check: {0} file(s) OVER-CEILING (soft ceiling {1} lines). Advisory, exit 0." -f $offenders, $SOFT_CEILING)
}
exit 0
