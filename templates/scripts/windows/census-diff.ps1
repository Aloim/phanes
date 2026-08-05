# phanes-template v3.4.0 census-diff
# Re-enumerates the disk-visible capability surfaces (MCP servers via `claude mcp list`,
# plugins, skills, commands) and diffs them against capabilities.selection[] recorded in
# .phanes/config.json, mechanizing the update-run "diff, don't re-ask" duty. Prints a digest
# JSON: added (detected, not in selection), removed (in selection, no longer detected),
# changed (an MCP server whose connected state differs from the recorded authOk). The ASKING
# about deltas stays in the session. A failed `claude mcp list` degrades that one surface
# (mcpAvailable: false) and never reports its selection entries as removed: an empty result
# from a FAILED call is not an authoritative empty set. Advisory: always exits 0.
$ErrorActionPreference = 'Stop'
$CAP = 100

# BEGIN SHARED core

# The current directory as a DirectoryInfo. Deliberately not (Get-Location).Path, for two
# reasons that both showed up as defects: that string is provider-qualified, and
# [System.IO.Path]::GetDirectoryName collapses the leading \\ of a UNC path on the very first
# ascent, after which every Test-Path is false and the walk silently finds nothing at all;
# and DirectoryInfo.Parent returns $null at a drive root AND at a UNC share root, which gives
# every walk below one honest termination condition instead of the compare-the-string-to-
# itself idiom that cannot tell those two cases apart.
function Get-PhanesStartDirectory {
  $p = $null
  try { $p = $PWD.ProviderPath } catch { $p = $null }
  if ([string]::IsNullOrEmpty($p)) { try { $p = (Get-Location).Path } catch { $p = $null } }
  if ([string]::IsNullOrEmpty($p)) { return $null }
  try { return (New-Object System.IO.DirectoryInfo $p) } catch { return $null }
}

# The user home directory, resolved by identity through three candidates rather than by
# reading one environment string. USERPROFILE can be unset entirely, and the naive form
# (Join-Path $env:USERPROFILE '.claude') then raises a TERMINATING error under EAP-Stop, so a
# script contractually bound to always exit 0 exits 1 with no output at all. Each candidate is
# materialized as a DirectoryInfo so that every later comparison is FullName against FullName,
# both already canonical.
function Get-PhanesHomeDirectory {
  $cands = @()
  if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) { $cands += $env:USERPROFILE }
  if ((-not [string]::IsNullOrWhiteSpace($env:HOMEDRIVE)) -and (-not [string]::IsNullOrWhiteSpace($env:HOMEPATH))) {
    $cands += ($env:HOMEDRIVE + $env:HOMEPATH)
  }
  try {
    $g = [Environment]::GetFolderPath('UserProfile')
    if (-not [string]::IsNullOrWhiteSpace($g)) { $cands += $g }
  } catch { }
  foreach ($c in $cands) {
    try {
      $i = New-Object System.IO.DirectoryInfo $c
      if ($i.Exists) { return $i.FullName }
    } catch { }
  }
  return $null
}

# The house root pattern: walk up for .phanes/config.json, $null when there is none. Asking
# the filesystem whether a path exists is a filesystem operation, so OrdinalIgnoreCase governs
# here; no NAME is compared anywhere in this function.
function Find-PhanesRoot {
  $d = Get-PhanesStartDirectory
  while ($null -ne $d) {
    try {
      if (Test-Path -LiteralPath (Join-Path $d.FullName '.phanes\config.json')) { return $d.FullName }
    } catch { }
    $d = $d.Parent
  }
  return $null
}

# Every hashtable keyed by user content must be built through this. A bare @{} is constructed
# with StringComparer.OrdinalIgnoreCase, which is how a case-only rename produced a completely
# empty diff while the -ceq and -cnotcontains operators reading from it looked correct on
# inspection and passed every operator audit. See Global Constraints, the four-construct rule,
# item 3.
function New-OrdinalHashtable {
  return (New-Object System.Collections.Hashtable ([System.StringComparer]::Ordinal))
}

# Is $Target inside $Root? Both sides are canonicalized first, because ../ segments and short
# 8.3 names each survive a naive prefix test. The comparison is OrdinalIgnoreCase under the
# documented NTFS exception: this is a path check against the filesystem, not a name compare.
# The trailing separator forced onto the root is load-bearing and not cosmetic: without it
# "C:\proj-evil" passes a prefix test against "C:\proj". The root itself counts as contained.
function Test-PhanesContained([string]$Root, [string]$Target) {
  if ([string]::IsNullOrWhiteSpace($Root) -or [string]::IsNullOrWhiteSpace($Target)) { return $false }
  $r = $null; $t = $null
  try {
    $r = [System.IO.Path]::GetFullPath($Root)
    $t = [System.IO.Path]::GetFullPath($Target)
  } catch { return $false }
  $sep = [System.IO.Path]::DirectorySeparatorChar
  if (-not $r.EndsWith($sep)) { $r = $r + $sep }
  if ([string]::Equals(($t + $sep), $r, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
  return $t.StartsWith($r, [System.StringComparison]::OrdinalIgnoreCase)
}

# Guarded JSON read with the FOUR outcomes a sensor has to be able to tell apart. Returns a
# hashtable with Status ('ok' | 'absent' | 'unreadable' | 'malformed'), Value (the parsed
# object on 'ok', $null otherwise) and Reason (one line, on the two failure states).
#
# 'absent' and 'unreadable' are DIFFERENT ANSWERS, and conflating them is the fabricated empty
# set the Global Constraints ban outright. Two separate mechanisms produced that conflation in
# the draft and both are closed here:
#   1. Get-Content -Raw on a 0-byte file emits $null, so the pipeline never reaches
#      ConvertFrom-Json and the catch never fires. A 0-byte file is the canonical interrupted-
#      write corruption, which makes it the single most likely real-world case and exactly the
#      one the guard missed.
#   2. Whitespace-only, literal null, bare-array and bare-string contents all PARSE cleanly, so
#      the catch never fires either, and the caller then reads a member off a value that has
#      none and silently gets $null.
# RequireMember closes (2) for a caller that knows its shape: pass 'artifacts' and a parsed
# value that is not an object carrying that member is 'malformed' rather than 'ok'.
#
# The result hashtable is a bare @{} on purpose: its keys are three fixed literals, never user
# content, so the Ordinal rule does not apply to it.
function Read-PhanesJsonFile([string]$Path, [string]$RequireMember) {
  $res = @{ Status = 'absent'; Value = $null; Reason = $null }
  try {
    if (-not (Test-Path -LiteralPath $Path)) { return $res }
  } catch {
    $res.Status = 'unreadable'
    $res.Reason = 'existence could not be determined: ' + $_.Exception.Message
    return $res
  }
  $raw = $null
  try {
    $raw = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).ProviderPath)
  } catch {
    $res.Status = 'unreadable'; $res.Reason = $_.Exception.Message; return $res
  }
  if ($null -eq $raw -or $raw.Trim().Length -eq 0) {
    $res.Status = 'malformed'; $res.Reason = 'file is empty or whitespace only'; return $res
  }
  $parsed = $null
  try { $parsed = $raw | ConvertFrom-Json } catch {
    $res.Status = 'malformed'; $res.Reason = 'not valid JSON'; return $res
  }
  if ($null -eq $parsed) {
    $res.Status = 'malformed'; $res.Reason = 'JSON literal null'; return $res
  }
  if (-not ($parsed -is [System.Management.Automation.PSCustomObject])) {
    $res.Status = 'malformed'; $res.Reason = 'top level is not a JSON object'; return $res
  }
  if (-not [string]::IsNullOrEmpty($RequireMember)) {
    $has = $false
    foreach ($p in $parsed.PSObject.Properties) {
      if ($null -ne $p -and [string]::Equals($p.Name, $RequireMember, [System.StringComparison]::Ordinal)) { $has = $true; break }
    }
    if (-not $has) {
      $res.Status = 'malformed'
      $res.Reason = ("required member '" + $RequireMember + "' is absent")
      return $res
    }
  }
  $res.Status = 'ok'; $res.Value = $parsed
  return $res
}

# The line-oriented sibling of the above, for the run-progress ledger. Same three-state
# contract and the same reason for it: a ledger that EXISTS but cannot be read must never
# report the verdict a ledger that is not there reports, because 'absent' is the fresh-project
# answer and acting on it archives or overwrites a run whose state was never seen. The
# directory probe is not hypothetical: a directory sitting where the ledger belongs read as
# ABSENT in the draft.
function Read-PhanesTextFile([string]$Path) {
  $res = @{ Status = 'absent'; Text = $null; Reason = $null }
  try {
    if (-not (Test-Path -LiteralPath $Path)) { return $res }
  } catch {
    $res.Status = 'unreadable'; $res.Reason = $_.Exception.Message; return $res
  }
  try {
    if ((Get-Item -LiteralPath $Path -Force).PSIsContainer) {
      $res.Status = 'unreadable'; $res.Reason = 'path is a directory, not a file'; return $res
    }
  } catch {
    $res.Status = 'unreadable'; $res.Reason = $_.Exception.Message; return $res
  }
  try {
    $res.Text = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).ProviderPath)
    $res.Status = 'ok'
  } catch {
    $res.Status = 'unreadable'; $res.Reason = $_.Exception.Message
  }
  return $res
}
# END SHARED core

# BEGIN SHARED json

# node-parity JSON emitter, matching JSON.stringify(x, null, 2) LAYOUT exactly: two-space
# indent, one key per line, same brace and bracket placement. The parity claim is deliberately
# scoped to layout, because byte parity on numbers was MEASURED FALSE on 2026-08-05 and is
# recorded here rather than claimed away: a JSON number that PS 5.1 parsed to Decimal round
# trips at its written precision, so 1.0 emits as 1.0 where node emits 1, and a 20-digit
# integer survives intact where node loses it to double precision. Both forms are valid JSON
# of the same value, and the difference PRESERVES the user's file instead of renormalizing it,
# which is why it is kept rather than fixed. Unchanged from the five copies it replaces except
# where noted; those five were byte-identical in two clusters and the defect below sat in both.
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
  # [decimal] is the type that was missing, and it is not an edge case: Windows PowerShell 5.1
  # returns System.Decimal from ConvertFrom-Json for EVERY non-integer JSON number, 1.0
  # included. Without it every such value fell through to the string branch below, so one
  # round trip through install-templates turned 0.75 into "0.75" in the user's own
  # .claude/settings.json, and the corruption is cumulative: once quoted, always quoted.
  # The invariant culture on the same line closes a second, independent defect in the same
  # spot: [string]$d under fi-FI or sv-SE emits a comma decimal separator, and a comma
  # decimal separator is not JSON.
  if ($value -is [int] -or $value -is [long] -or $value -is [double] -or $value -is [decimal]) {
    return [System.Convert]::ToString($value, [System.Globalization.CultureInfo]::InvariantCulture)
  }
  if ($value -is [System.Collections.IDictionary]) {
    $keys = @($value.Keys)
    if ($keys.Count -eq 0) { return '{}' }
    $parts = @()
    foreach ($k in $keys) {
      $parts += ($padIn + (ConvertTo-JsonStringLiteral ([string]$k)) + ': ' + (ConvertTo-NodeJson $value[$k] ($indent + 2)))
    }
    return "{`n" + ($parts -join ",`n") + "`n" + $pad + '}'
  }
  if ($value -is [System.Management.Automation.PSCustomObject]) {
    $props = @($value.PSObject.Properties | Where-Object { $null -ne $_ })
    if ($props.Count -eq 0) { return '{}' }
    $parts = @()
    foreach ($p in $props) {
      $parts += ($padIn + (ConvertTo-JsonStringLiteral ([string]$p.Name)) + ': ' + (ConvertTo-NodeJson $p.Value ($indent + 2)))
    }
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
# END SHARED json

$report = [ordered]@{
  selectionPresent = $false
  configUntrusted = $false
  mcpAvailable = $false
  addedCount = 0; added = @()
  removedCount = 0; removed = @()
  changedCount = 0; changed = @()
  ignoredSelectionEntries = 0
  surfacesUnreadable = $false
  listTruncated = $false
}
function Write-ReportAndExit { Write-Output (ConvertTo-NodeJson $report 0); exit 0 }

$root = Find-PhanesRoot
if (-not $root) {
  [Console]::Error.WriteLine('census-diff: .phanes/config.json not found from this directory')
  Write-ReportAndExit
}

# Selection from config, guarded. A malformed config degrades to "no diff computed", clearly
# flagged; it never reads as "everything was removed".
$selection = @()
try {
  $cfg = Get-Content -LiteralPath (Join-Path $root '.phanes\config.json') -Raw -Encoding utf8 | ConvertFrom-Json
  if ($cfg.capabilities -and $cfg.capabilities.selection) {
    $selection = @($cfg.capabilities.selection)
    $report.selectionPresent = $true
  }
} catch {
  $report.configUntrusted = $true
  [Console]::Error.WriteLine('census-diff: .phanes/config.json is malformed; no diff computed, nothing reported as removed')
  Write-ReportAndExit
}

# --- detected surfaces. Each is (type, name); names are compared ordinal case-sensitively,
# --- exactly as recorded (a rename shows as removed + added, which the session can judge).
# B3 repair, and this is the sharpest defect the review found. These two, and $inSelection
# below, were bare @{}, which PowerShell builds with StringComparer.OrdinalIgnoreCase. Every
# -ceq and -cnotcontains in the diff loop was therefore CORRECT BUT DECORATIVE, because every
# actual name match runs through ContainsKey on one of these tables. Measured consequence: a
# case-only rename produced a COMPLETELY EMPTY diff, directly contradicting this task's own
# recorded decision that "a renamed server reads as removed plus added". Worse, `changed` fired
# for a differently-cased server by binding a selection entry to it and reporting that server's
# health as the entry's current state. Whitespace-only differences were handled correctly
# throughout, which is exactly what made the case gap easy to miss on inspection.
$detected = New-OrdinalHashtable      # key "type`0name" -> $true
$mcpConnected = New-OrdinalHashtable  # mcp name -> connected state
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
try {
  # B5 repair, the second of the two sites: no `2>$null` on a native call under EAP-Stop. See
  # the same fix in preflight for the full reasoning. One incidental stderr line beside a valid
  # server list discarded the entire MCP surface here too.
  $mcpRaw = & claude mcp list
  if ($LASTEXITCODE -ne 0) { $mcpRaw = $null }
} catch { $mcpRaw = $null }
if ($null -ne $mcpRaw) {
  $report.mcpAvailable = $true
  foreach ($lnObj in @($mcpRaw)) {
    $ln = [string]$lnObj
    $i = $ln.IndexOf(': ', [System.StringComparison]::Ordinal)
    if ($i -le 0) { continue }
    $name = $ln.Substring(0, $i)
    $detected['mcp' + [char]0 + $name] = $true
    # Health mark: the line tail carries "- <mark> <status>"; U+2714/check = connected.
    $mcpConnected[$name] = ($ln.IndexOf([string][char]0x2714, [System.StringComparison]::Ordinal) -ge 0)
  }
} else {
  [Console]::Error.WriteLine('census-diff: `claude mcp list` unavailable or failed; MCP surface skipped, its selection entries are NOT reported as removed')
}

# B2 repair, same as preflight: never Join-Path onto $env:USERPROFILE, which raises a
# terminating error under EAP-Stop when the variable is unset, from a script bound to exit 0.
$userHome = Get-PhanesHomeDirectory
$userClaude = $null
if ($userHome) { $userClaude = Join-Path $userHome '.claude' }

# B8 repair. An unreadable directory returned silently here, so every recorded entry sourced
# from that surface fell out of $detected and was then reported as REMOVED. That is the
# fabricated empty set in its most damaging form for this script: the whole point of the
# mcpAvailable guard is that a failed enumeration must never read as "everything was removed",
# and the directory surfaces had no equivalent protection. An unreadable surface is now
# recorded, and its recorded entries are skipped in the removed pass exactly as the MCP surface
# already was.
$unreadableTypes = New-OrdinalHashtable
function Add-DirNames([string]$dir, [string]$type, [string]$filter, [bool]$dirs) {
  if (-not $dir) { return }
  if (-not (Test-Path -LiteralPath $dir)) { return }
  try {
    if ($dirs) { $items = @(Get-ChildItem -LiteralPath $dir -Directory -ErrorAction Stop) }
    else { $items = @(Get-ChildItem -LiteralPath $dir -File -Filter $filter -ErrorAction Stop) }
  } catch {
    $script:unreadableTypes[$type] = $true
    [Console]::Error.WriteLine("census-diff: cannot enumerate $dir; $type entries are NOT reported as removed")
    return
  }
  foreach ($it in $items) {
    $n = $it.Name
    if (-not $dirs) { $n = [System.IO.Path]::GetFileNameWithoutExtension($n) }
    $script:detected[$type + [char]0 + $n] = $true
  }
}
Add-DirNames (Join-Path $root '.claude\commands') 'command' '*.md' $false
if ($userClaude) { Add-DirNames (Join-Path $userClaude 'commands') 'command' '*.md' $false } else { $unreadableTypes['command'] = $true }
Add-DirNames (Join-Path $root '.claude\skills') 'skill' '*' $true
if ($userClaude) { Add-DirNames (Join-Path $userClaude 'skills') 'skill' '*' $true } else { $unreadableTypes['skill'] = $true }
$pluginsJson = $null
if ($userClaude) { $pluginsJson = Join-Path $userClaude 'plugins\installed_plugins.json' } else { $unreadableTypes['plugin'] = $true }
if ($pluginsJson -and (Test-Path -LiteralPath $pluginsJson)) {
  try {
    $pj = Get-Content -LiteralPath $pluginsJson -Raw -Encoding utf8 | ConvertFrom-Json
    if ($pj.plugins -is [System.Management.Automation.PSCustomObject]) {
      foreach ($prop in @($pj.plugins.PSObject.Properties | ForEach-Object { $_ })) {
        foreach ($inst in @($prop.Value)) {
          $scopeOk = ($inst.scope -ceq 'user') -or (($inst.scope -ceq 'project') -and ($inst.projectPath -is [string]) -and ([string]::Equals($inst.projectPath, $root, [System.StringComparison]::OrdinalIgnoreCase)))
          if ($scopeOk) {
            $n = ([string]$prop.Name -split '@')[0]
            $detected['plugin' + [char]0 + $n] = $true
            break
          }
        }
      }
    }
  } catch { }
}

# --- diff against the recorded selection
$inSelection = New-OrdinalHashtable
$added = New-Object System.Collections.ArrayList
$removed = New-Object System.Collections.ArrayList
$changed = New-Object System.Collections.ArrayList
$diffTypes = @('mcp', 'plugin', 'skill', 'command')
foreach ($e in $selection) {
  if (-not ($e.name -is [string]) -or -not ($e.type -is [string])) { $report.ignoredSelectionEntries++; continue }
  if ($diffTypes -cnotcontains $e.type) { $report.ignoredSelectionEntries++; continue }
  if ($e.type -ceq 'mcp' -and -not $report.mcpAvailable) { $inSelection[$e.type + [char]0 + $e.name] = $true; continue }
  # B8 repair, the consuming half: a surface that could not be enumerated cannot testify that
  # anything on it is gone. Recording the key still suppresses a false "added" for the same
  # entry, exactly as the mcpAvailable branch above already does.
  if ($unreadableTypes.ContainsKey($e.type)) { $inSelection[$e.type + [char]0 + $e.name] = $true; $report.surfacesUnreadable = $true; continue }
  $key = $e.type + [char]0 + $e.name
  $inSelection[$key] = $true
  if (-not $detected.ContainsKey($key)) {
    [void]$removed.Add([ordered]@{ name = $e.name; type = $e.type })
  } elseif ($e.type -ceq 'mcp' -and ($e.authOk -is [bool]) -and $mcpConnected.ContainsKey($e.name) -and ($mcpConnected[$e.name] -ne $e.authOk)) {
    [void]$changed.Add([ordered]@{ name = $e.name; type = 'mcp'; field = 'authOk'; recorded = $e.authOk; current = $mcpConnected[$e.name] })
  }
}
$detKeys = @($detected.Keys)
[Array]::Sort($detKeys, [System.StringComparer]::Ordinal)
foreach ($key in $detKeys) {
  if (-not $inSelection.ContainsKey($key)) {
    $parts = $key.Split([char]0)
    [void]$added.Add([ordered]@{ name = $parts[1]; type = $parts[0] })
  }
}

$report.addedCount = $added.Count
$report.removedCount = $removed.Count
$report.changedCount = $changed.Count
$report.added = @($added | Select-Object -First $CAP)
$report.removed = @($removed | Select-Object -First $CAP)
$report.changed = @($changed | Select-Object -First $CAP)
$report.listTruncated = ($added.Count -gt $CAP -or $removed.Count -gt $CAP -or $changed.Count -gt $CAP)
Write-ReportAndExit
