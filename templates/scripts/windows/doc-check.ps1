# phanes-template v3.0.1 doc-check
# Scans the documentation tree (archive/ excluded) for living documents over the 500-line ceiling
# or missing a DOC header line, for folders holding docs but no _index.md, and for indexes older
# than their newest sibling. Prints offenders with line counts. Frozen artifact classes (session
# summaries, dated architecture snapshot folders, archive/) are never flagged for content
# conformance. Advisory: always exits 0.
$ErrorActionPreference = 'Stop'
$CEILING = 500

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
if (-not $root) { [Console]::Error.WriteLine('doc-check: .phanes/config.json not found from this directory'); exit 0 }

$cfg = Get-Content -LiteralPath (Join-Path $root '.phanes\config.json') -Raw -Encoding utf8 | ConvertFrom-Json
$docRoot = 'documentation'
if ($cfg.docRoot) { $docRoot = $cfg.docRoot }
$docPath = Join-Path $root $docRoot
if (-not (Test-Path -LiteralPath $docPath)) { Write-Output 'doc-check: no documentation tree'; exit 0 }

function Normalize([string]$p) { return ($p -replace '\\', '/') }
# Enumerate from the resolved base so child FullName prefixes line up with docNorm exactly.
$docPath = (Resolve-Path -LiteralPath $docPath).Path
$docNorm = Normalize($docPath).TrimEnd('/')

function Is-Frozen([string]$normPath) {
  # relative segments below the doc root
  $rel = $normPath.Substring($docNorm.Length).TrimStart('/')
  $segs = $rel -split '/'
  foreach ($s in $segs) {
    if ($s -eq 'archive') { return $true }
    if ($s -eq 'session-summaries') { return $true }
    if ($s -match '^\d{4}-\d{2}-\d{2}') { return $true }  # dated snapshot folder
  }
  return $false
}

# Strip the doc-root prefix cleanly. Takes an already-normalized path in a variable, so no
# function-call chaining (which PowerShell would mis-parse in command mode).
function Rel([string]$norm) {
  if ($norm.Length -ge $docNorm.Length -and $norm.StartsWith($docNorm, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $norm.Substring($docNorm.Length).TrimStart('/')
  }
  return $norm
}

$offenders = 0

# 1. File-level checks on living .md documents.
$allMd = Get-ChildItem -LiteralPath $docPath -Recurse -Filter *.md -File -ErrorAction SilentlyContinue
foreach ($f in $allMd) {
  $fn = Normalize($f.FullName)
  if ($fn -match '/archive/') { continue }
  if ($f.Name -eq '_index.md' -or $f.Name -eq '_index_archive.md') { continue }
  if (Is-Frozen $fn) { continue }

  $lines = Get-Content -LiteralPath $f.FullName
  $count = ($lines | Measure-Object -Line).Lines
  if ($count -gt $CEILING) {
    Write-Output ("OVER-CEILING: {0} ({1} lines)" -f (Rel $fn), $count)
    $offenders++
  }
  $head = $lines | Select-Object -First 8
  $hasDoc = $false
  foreach ($ln in $head) { if ($ln -match '<!--\s*DOC\s*\|') { $hasDoc = $true; break } }
  if (-not $hasDoc) {
    Write-Output ("NO-DOC-HEADER: {0}" -f (Rel $fn))
    $offenders++
  }
}

# 2. Folder-level checks: missing or stale _index.md.
$folders = @(Get-Item -LiteralPath $docPath) + @(Get-ChildItem -LiteralPath $docPath -Recurse -Directory -ErrorAction SilentlyContinue)
foreach ($folder in $folders) {
  $fn = Normalize($folder.FullName)
  if ($fn -match '/archive(/|$)') { continue }
  $childMd = Get-ChildItem -LiteralPath $folder.FullName -Filter *.md -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '_index.md' -and $_.Name -ne '_index_archive.md' }
  if (-not $childMd -or $childMd.Count -eq 0) { continue }
  $indexPath = Join-Path $folder.FullName '_index.md'
  if (-not (Test-Path -LiteralPath $indexPath)) {
    Write-Output ("NO-INDEX: {0}/" -f (Rel $fn))
    $offenders++
    continue
  }
  $indexTime = (Get-Item -LiteralPath $indexPath).LastWriteTime
  $newestChild = ($childMd | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
  if ($newestChild -gt $indexTime) {
    Write-Output ("STALE-INDEX: {0}/ (run phanes doc-index)" -f (Rel $fn))
    $offenders++
  }
}

if ($offenders -eq 0) { Write-Output 'doc-check: OK' }
exit 0
