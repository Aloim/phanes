# phanes-template v3.4.0 doc-check
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

$cfg = $null
try {
  $cfg = Get-Content -LiteralPath (Join-Path $root '.phanes\config.json') -Raw -Encoding utf8 | ConvertFrom-Json
} catch {
  [Console]::Error.WriteLine('doc-check: .phanes/config.json is malformed, using defaults')
  $cfg = $null
}
$docRoot = 'documentation'
if ($cfg.docRoot) { $docRoot = $cfg.docRoot }
# A trailing slash in docRoot would otherwise leak into every derived path and message
# (doubled separators, and an empty final segment where a folder name belongs).
$docRoot = ([string]$docRoot).TrimEnd('/', '\')
if (-not $docRoot) { $docRoot = 'documentation' }
$docPath = Join-Path $root $docRoot
if (-not (Test-Path -LiteralPath $docPath)) { Write-Output 'doc-check: no documentation tree'; exit 0 }

function Normalize([string]$p) { return ($p -replace '\\', '/') }
# Enumerate from the resolved base so child FullName prefixes line up with docNorm exactly.
$docPath = (Resolve-Path -LiteralPath $docPath).Path
$docNorm = Normalize($docPath).TrimEnd('/')

function Get-DisciplineList([object]$cfg, [string]$key, [string]$docRoot) {
  $out = New-Object System.Collections.Generic.List[string]
  if (-not $cfg.doc_discipline) { return $out }
  $raw = $cfg.doc_discipline.$key
  if (-not $raw) { return $out }
  $prefix = $docRoot.Trim('/').Trim('\') + '/'
  foreach ($e in @($raw)) {
    if (-not $e) { continue }
    $n = ([string]$e).Trim()
    if (-not $n) { continue }
    $n = $n -replace '\\', '/'
    $n = $n.Trim('/')
    if ($n.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
      $n = $n.Substring($prefix.Length).Trim('/')
    }
    if ($n) { $out.Add($n) }
  }
  return $out
}

$frozen = Get-DisciplineList $cfg 'frozen_classes' $docRoot

function Is-Frozen([string]$normPath) {
  # relative segments below the doc root
  $rel = $normPath.Substring($docNorm.Length).TrimStart('/')
  $segs = $rel -split '/'
  foreach ($s in $segs) {
    if ($s -eq 'archive') { return $true }
    if ($s -eq 'session-summaries') { return $true }
    if ($s -match '^\d{4}-\d{2}-\d{2}') { return $true }  # dated snapshot folder
  }
  foreach ($e in $frozen) {
    if ($e -notmatch '/') {
      foreach ($s in $segs) { if ($s -eq $e) { return $true } }
    } else {
      if ($rel -eq $e -or $rel.StartsWith($e + '/', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
  }
  return $false
}

$exclusions = Get-DisciplineList $cfg 'index_exclusions' $docRoot
function Test-Excluded([string]$relPath) {
  foreach ($e in $exclusions) {
    if ($e -notmatch '/') {
      foreach ($seg in ($relPath -split '/')) { if ($seg -eq $e) { return $true } }
    } else {
      if ($relPath -eq $e -or $relPath.StartsWith($e + '/', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
  }
  return $false
}

# Strip the doc-root prefix cleanly. Takes an already-normalized path in a variable, so no
# function-call chaining (which PowerShell would mis-parse in command mode).
# Repository-root-relative, for messages that name a folder rather than a file inside docRoot.
# The docRoot itself is a legitimate answer there, and it has no docRoot-relative spelling.
# Two statements, not one: in PowerShell `Normalize($x).TrimEnd('/')` binds TrimEnd to the
# ARGUMENT, not to Normalize's result, so the chained form silently does nothing here.
$rootNorm = Normalize((Resolve-Path -LiteralPath $root).Path)
$rootNorm = $rootNorm.TrimEnd('/')
function RelRoot([string]$norm) {
  if ($norm.Length -ge $rootNorm.Length -and $norm.StartsWith($rootNorm, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $norm.Substring($rootNorm.Length).TrimStart('/')
  }
  return $norm
}

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

  # Advisory: one unreadable file must not abort the whole tree audit under EAP = 'Stop'.
  try { $lines = @(Get-Content -LiteralPath $f.FullName -Encoding utf8) }
  catch {
    [Console]::Error.WriteLine("doc-check: cannot read $(Rel $fn), skipping")
    continue
  }
  $count = $lines.Count
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
  if (Test-Excluded (Rel $fn)) { continue }
  $childMd = Get-ChildItem -LiteralPath $folder.FullName -Filter *.md -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '_index.md' -and $_.Name -ne '_index_archive.md' }
  if (-not $childMd -or $childMd.Count -eq 0) { continue }
  $indexPath = Join-Path $folder.FullName '_index.md'
  if (-not (Test-Path -LiteralPath $indexPath)) {
    # Repository-root-relative, matching the POSIX sibling. Rel is docRoot-relative, which
    # renders the docRoot itself as an empty string and printed a bare "NO-INDEX: /".
    Write-Output ("NO-INDEX: {0}/" -f (RelRoot $fn))
    $offenders++
    continue
  }
  $indexTime = (Get-Item -LiteralPath $indexPath).LastWriteTime
  $newestChild = ($childMd | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
  if ($newestChild -gt $indexTime) {
    # Root-relative, same base as NO-INDEX above: both name a folder, and the docRoot folder
    # itself has no docRoot-relative spelling (it printed as a bare "/").
    Write-Output ("STALE-INDEX: {0}/ (run phanes doc-index)" -f (RelRoot $fn))
    $offenders++
  }
}

if ($offenders -eq 0) { Write-Output 'doc-check: OK' }
exit 0
