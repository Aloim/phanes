# phanes-template v3.4.0 repo-manifest
# Generates the deterministic raw file list (.phanes/inventory/raw-files.txt, from
# git ls-files, docRoot/.phanes/.claude trees and binary extensions excluded) and diffs
# it against the Claude-maintained annotated summary list (annotated-files.json, shape
# {path: {summary, hash}}). Staleness is content-hash based: the hash is the index blob
# sha that git ls-files -s already returns. Pruning is keyed to GENUINE absence from the
# full unfiltered tracked set, never to the filters, so a misread docRoot can never
# destroy hand-written summaries. Advisory: always exits 0.
$ErrorActionPreference = 'Stop'
$CAP = 100

# BOM-free UTF-8 on every write (house pattern, see doc-index.ps1). WriteAllText resolves
# relative paths against the .NET process directory, which Push-Location does not change,
# so every path handed to it below is already absolute.
$UTF8_NO_BOM = New-Object System.Text.UTF8Encoding($false)
function Write-Utf8([string]$path, [string]$content) {
  [System.IO.File]::WriteAllText($path, $content, $UTF8_NO_BOM)
}

function Find-PhanesRoot {
  $d = (Get-Location).Path
  while ($true) {
    if (Test-Path -LiteralPath (Join-Path $d '.phanes\config.json')) { return $d }
    $p = [System.IO.Path]::GetDirectoryName($d)
    if (-not $p -or $p -eq $d) { return $null }
    $d = $p
  }
}

# --- node-parity JSON emitter (JSON.stringify(x, null, 2) format), so annotated-files.json
# --- is byte-identical across platforms and the stdout report is line-identical.
function ConvertTo-JsonStringLiteral([string]$s) {
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append('"')
  foreach ($ch in $s.ToCharArray()) {
    if ($ch -eq '"') { [void]$sb.Append('\"') }
    elseif ($ch -eq '\') { [void]$sb.Append('\\') }
    elseif ($ch -eq "`b") { [void]$sb.Append('\b') }
    elseif ($ch -eq "`f") { [void]$sb.Append('\f') }
    elseif ($ch -eq "`n") { [void]$sb.Append('\n') }
    elseif ($ch -eq "`r") { [void]$sb.Append('\r') }
    elseif ($ch -eq "`t") { [void]$sb.Append('\t') }
    elseif ([int]$ch -lt 0x20) { [void]$sb.Append('\u' + ([int]$ch).ToString('x4')) }
    else { [void]$sb.Append($ch) }
  }
  [void]$sb.Append('"')
  return $sb.ToString()
}
function ConvertTo-NodeJson($value, [int]$indent) {
  $pad = ' ' * $indent
  $padIn = ' ' * ($indent + 2)
  if ($null -eq $value) { return 'null' }
  if ($value -is [string]) { return ConvertTo-JsonStringLiteral $value }
  if ($value -is [bool]) { if ($value) { return 'true' } else { return 'false' } }
  if ($value -is [int] -or $value -is [long] -or $value -is [double]) { return [string]$value }
  if ($value -is [System.Collections.IDictionary]) {
    $keys = @($value.Keys)
    if ($keys.Count -eq 0) { return '{}' }
    $parts = @()
    foreach ($k in $keys) { $parts += ($padIn + (ConvertTo-JsonStringLiteral ([string]$k)) + ': ' + (ConvertTo-NodeJson $value[$k] ($indent + 2))) }
    return "{`n" + ($parts -join ",`n") + "`n" + $pad + '}'
  }
  if ($value -is [System.Collections.IEnumerable]) {
    $items = @($value)
    if ($items.Count -eq 0) { return '[]' }
    $parts = @()
    foreach ($it in $items) { $parts += ($padIn + (ConvertTo-NodeJson $it ($indent + 2))) }
    return "[`n" + ($parts -join ",`n") + "`n" + $pad + ']'
  }
  return ConvertTo-JsonStringLiteral ([string]$value)
}

$root = Find-PhanesRoot
if (-not $root) { [Console]::Error.WriteLine('repo-manifest: .phanes/config.json not found from this directory'); exit 0 }

$invDir = Join-Path $root '.phanes\inventory'
$rawFile = Join-Path $invDir 'raw-files.txt'
$annotatedFile = Join-Path $invDir 'annotated-files.json'

$report = [ordered]@{
  totalTracked = 0
  newCount = 0; new = @()
  changedCount = 0; changed = @()
  staleCount = 0; stale = @()
  listTruncated = $false
  annotatedMalformed = $false
  configUntrusted = $false
  gitUnavailable = $false
  migrated = $false
}
function Write-ReportAndExit { Write-Output (ConvertTo-NodeJson $report 0); exit 0 }

# Config verdict: degrade, never destroy, identically on both platforms. A config that
# cannot be read or parsed does NOT stop the run and does NOT silently default either:
# the run continues on the default filters, the report carries configUntrusted: true,
# and every destructive or mutating write to annotated-files.json is suppressed, so a
# misread config can produce a confusing report but never a loss. (The POSIX sibling
# reaches the same whole-file verdict through JSON.parse in its existing node block.)
$docRoot = 'documentation'
$configUntrusted = $false
$cfg = $null
try {
  $cfg = Get-Content -LiteralPath (Join-Path $root '.phanes\config.json') -Raw -Encoding utf8 | ConvertFrom-Json
  if (-not ($cfg -is [System.Management.Automation.PSCustomObject])) { $cfg = $null }
} catch { $cfg = $null }
if ($null -eq $cfg) {
  $configUntrusted = $true
  [Console]::Error.WriteLine('repo-manifest: .phanes/config.json is malformed or unreadable; running on default filters, pruning and annotation writes suppressed so no summary can be lost to a misread config')
}
if (-not $configUntrusted -and ($cfg.docRoot -is [string]) -and $cfg.docRoot -ne '') { $docRoot = $cfg.docRoot }
$report.configUntrusted = $configUntrusted
$docRoot = $docRoot -replace '/+$', ''
if ($docRoot -eq '') { $docRoot = 'documentation' }

# Native git under $ErrorActionPreference = 'Stop': redirected stderr surfaces as an
# ErrorRecord (the loc-check.ps1 class), so the call sits in try/catch and degrades to
# "inventory left untouched" outside a repository. Nothing is written on this path: an
# empty tracked set from a FAILED git call must never be allowed to prune summaries.
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
$lsRaw = $null
Push-Location $root
try {
  $lsRaw = & git ls-files -s -z 2>$null
  if ($LASTEXITCODE -ne 0) { $lsRaw = $null }
} catch {
  $lsRaw = $null
} finally {
  Pop-Location
}
if ($null -eq $lsRaw) {
  [Console]::Error.WriteLine('repo-manifest: not a git repository (or git unavailable), inventory left untouched')
  $report.gitUnavailable = $true
  Write-ReportAndExit
}

# Parse `git ls-files -s -z` records: "<mode> <sha> <stage>`t<path>". Two sets are kept
# deliberately: the FULL tracked set (prune substrate: only genuine absence from git
# counts as deleted) and the filtered inventory set (what agents browse). Excluded by a
# filter is not the same as deleted.
$binRe = '\.(png|jpg|jpeg|gif|ico|woff2?|ttf|eot|pdf|zip|exe|dll|so|dylib)$'
$docPrefix = $docRoot + '/'
$hashByPath = @{}
$rawPaths = New-Object System.Collections.ArrayList
$lsText = [string]::Join('', @($lsRaw))
foreach ($e in $lsText.Split([char]0)) {
  if ($e -eq '') { continue }
  $tab = $e.IndexOf([char]"`t")
  if ($tab -lt 0) { continue }
  $meta = $e.Substring(0, $tab).Split(' ')
  if ($meta.Length -lt 3) { continue }
  $p = $e.Substring($tab + 1)
  $hashByPath[$p] = $meta[1]
  if ($p.StartsWith($docPrefix, [System.StringComparison]::Ordinal) -or $p.StartsWith('.phanes/', [System.StringComparison]::Ordinal) -or $p.StartsWith('.claude/', [System.StringComparison]::Ordinal)) { continue }
  if ($p -match $binRe) { continue }
  [void]$rawPaths.Add($p)
}
$rawPaths = $rawPaths.ToArray()
[Array]::Sort($rawPaths, [System.StringComparer]::Ordinal)
$report.totalTracked = $rawPaths.Count

New-Item -ItemType Directory -Force -Path $invDir | Out-Null
if (-not (Test-Path -LiteralPath $annotatedFile)) { Write-Utf8 $annotatedFile "{}`n" }

# A malformed annotated file is a degrade, never a reset: the one-line summaries are
# hand-maintained and unrecoverable from git, so report it and leave it untouched.
$annotatedObj = $null
$annotatedMalformed = $false
try {
  $annotatedObj = Get-Content -LiteralPath $annotatedFile -Raw -Encoding utf8 | ConvertFrom-Json
  if ($null -eq $annotatedObj -or $annotatedObj -is [System.Array] -or -not ($annotatedObj -is [System.Management.Automation.PSCustomObject])) { throw 'top-level value is not a JSON object' }
} catch {
  $annotatedObj = $null
  $annotatedMalformed = $true
  [Console]::Error.WriteLine('repo-manifest: .phanes/inventory/annotated-files.json is malformed, left untouched; the raw list was still regenerated')
}
$report.annotatedMalformed = $annotatedMalformed

if ($rawPaths.Count -gt 0) { Write-Utf8 $rawFile (($rawPaths -join "`n") + "`n") } else { Write-Utf8 $rawFile '' }

if (-not $annotatedMalformed) {
  # NOT @($annotatedObj.PSObject.Properties.Name): on an object with no properties that
  # member access yields $null, and @($null) is a ONE-element array holding $null. Project
  # the names through the pipeline instead, where an empty collection stays empty.
  # Flat {path: "summary"} entries migrate to {summary, hash: null}; a null hash means
  # "stamp me this run". Own properties only: a tracked file named constructor or
  # toString is classified by lookup, never by inherited members.
  $normalized = @{}
  $normKeys = New-Object System.Collections.ArrayList
  $migrated = $false
  foreach ($prop in @($annotatedObj.PSObject.Properties | ForEach-Object { $_ })) {
    $v = $prop.Value
    if ($v -is [string]) { $normalized[$prop.Name] = @{ summary = $v; hash = $null }; $migrated = $true }
    elseif ($v -is [System.Management.Automation.PSCustomObject]) {
      $s = ''; $h = $null
      if ($v.summary -is [string]) { $s = $v.summary }
      if ($v.hash -is [string]) { $h = $v.hash }
      $normalized[$prop.Name] = @{ summary = $s; hash = $h }
    }
    else { $normalized[$prop.Name] = @{ summary = ''; hash = $null } }
    [void]$normKeys.Add($prop.Name)
  }
  $report.migrated = $migrated
  $fresh = New-Object System.Collections.ArrayList
  foreach ($p in $rawPaths) { if (-not $normalized.ContainsKey($p)) { [void]$fresh.Add($p) } }
  $stale = New-Object System.Collections.ArrayList
  $changed = New-Object System.Collections.ArrayList
  foreach ($k in $normKeys) {
    if (-not $hashByPath.ContainsKey($k)) { [void]$stale.Add($k); continue }
    $rec = $normalized[$k]
    $cur = $hashByPath[$k]
    # A null hash is the "just written or just refreshed" marker: stamp it with the
    # current index blob sha. A present hash that no longer matches is the changed
    # signal, deliberately NOT overwritten here: it stays until an agent refreshes the
    # summary and nulls the hash, otherwise the signal would vanish unseen.
    if ($null -eq $rec.hash) { $rec.hash = $cur }
    elseif ($rec.hash -cne $cur) { [void]$changed.Add($k) }
  }
  $staleArr = $stale.ToArray(); [Array]::Sort($staleArr, [System.StringComparer]::Ordinal)
  $changedArr = $changed.ToArray(); [Array]::Sort($changedArr, [System.StringComparer]::Ordinal)
  $freshArr = $fresh.ToArray()
  if (-not $configUntrusted) {
    $keep = New-Object System.Collections.ArrayList
    foreach ($k in $normKeys) { if ($hashByPath.ContainsKey($k)) { [void]$keep.Add($k) } }
    $keepArr = $keep.ToArray(); [Array]::Sort($keepArr, [System.StringComparer]::Ordinal)
    $out = [ordered]@{}
    foreach ($k in $keepArr) { $rec = $normalized[$k]; $out[$k] = [ordered]@{ summary = $rec.summary; hash = $rec.hash } }
    Write-Utf8 $annotatedFile ((ConvertTo-NodeJson $out 0) + "`n")
  }
  $report.newCount = $freshArr.Count
  if ($freshArr.Count -gt $CAP) { $report.new = @($freshArr[0..($CAP - 1)]) } else { $report.new = $freshArr }
  $report.changedCount = $changedArr.Count
  if ($changedArr.Count -gt $CAP) { $report.changed = @($changedArr[0..($CAP - 1)]) } else { $report.changed = $changedArr }
  $report.staleCount = $staleArr.Count
  if ($staleArr.Count -gt $CAP) { $report.stale = @($staleArr[0..($CAP - 1)]) } else { $report.stale = $staleArr }
  $report.listTruncated = ($freshArr.Count -gt $CAP -or $changedArr.Count -gt $CAP -or $staleArr.Count -gt $CAP)
}
Write-ReportAndExit
