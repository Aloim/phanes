# phanes-template v3.4.0 ledger
# Run-progress ledger mechanics (Phase 0 Compaction Survival made mechanical). Subcommands:
#   ledger append "<line>"  appends one caller-composed line (the caller owns the format;
#                           this script only writes; an argument containing CR or LF is
#                           refused, the ledger is line-oriented)
#   ledger status           prints CLOSED / OPEN <last line> / ABSENT
#   ledger close            appends the terminator line "CLOSED, run complete" (idempotent)
#   ledger reset            archives the ledger to run-progress.prev (one generation kept)
#                           and starts fresh (the mechanical arm of the consented fresh-run
#                           choice; the CONSENT stays in the session, decision B6)
# Advisory: always exits 0.
$ErrorActionPreference = 'Stop'
$TERMINATOR = 'CLOSED, run complete'

$UTF8_NO_BOM = New-Object System.Text.UTF8Encoding($false)

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

$root = Find-PhanesRoot
if (-not $root) { [Console]::Error.WriteLine('ledger: .phanes/config.json not found from this directory'); exit 0 }

$phanesDir = Join-Path $root '.phanes'
$ledgerFile = Join-Path $phanesDir 'run-progress'
$prevFile = Join-Path $phanesDir 'run-progress.prev'

# Ledger state, as the THREE answers the caller must be able to tell apart. Returns a hashtable
# with Readable (bool) and Last (the last non-empty line, or $null).
#
# LG-3 repair: the draft returned $null both when the ledger was absent and when it existed but
# could not be read (exclusive lock, denied ACL, a directory sitting in its place), and $null
# meant ABSENT, which is the FRESH PROJECT verdict. So a run whose ledger could not be read
# reported as a project that never had one. Read-PhanesTextFile separates the two, and every
# caller below branches on Readable BEFORE it acts.
#
# Reading by line still tolerates CRLF ledgers written by earlier sessions; everything THIS
# script writes is LF and BOM-free.
function Get-LedgerState {
  $r = Read-PhanesTextFile $ledgerFile
  if ($r.Status -ceq 'absent') { return @{ Readable = $true; Last = $null } }
  if ($r.Status -cne 'ok') { return @{ Readable = $false; Last = $null } }
  $lines = @()
  if ($null -ne $r.Text) { $lines = @($r.Text -split "`r?`n") }
  for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    if ($lines[$i] -is [string] -and $lines[$i].Trim() -cne '') { return @{ Readable = $true; Last = $lines[$i].Trim() } }
  }
  return @{ Readable = $true; Last = $null }
}

$sub = $null
if ($args.Count -ge 1) { $sub = [string]$args[0] }

# LG-2 repair: -casesensitive. A bare switch matches case-insensitively, so `ledger RESET`
# executed the destructive archive. Loose matching on a subcommand name widens exactly the
# surface a consent gate exists to narrow, and `reset` is the one subcommand here that destroys
# state.
switch -casesensitive ($sub) {
  'append' {
    if ($args.Count -lt 2 -or -not ($args[1] -is [string]) -or ([string]$args[1]).Trim() -ceq '') {
      [Console]::Error.WriteLine('ledger: append requires one non-empty line argument; nothing written')
      exit 0
    }
    $line = [string]$args[1]
    if ($line.IndexOf("`r") -ge 0 -or $line.IndexOf("`n") -ge 0) {
      [Console]::Error.WriteLine('ledger: append argument contains a line break; the ledger is line-oriented, nothing written')
      exit 0
    }
    try {
      New-Item -ItemType Directory -Force -Path $phanesDir | Out-Null
      [System.IO.File]::AppendAllText($ledgerFile, $line + "`n", $UTF8_NO_BOM)
    } catch {
      [Console]::Error.WriteLine("ledger: cannot write $ledgerFile ($($_.Exception.Message))")
    }
    exit 0
  }
  'status' {
    $st = Get-LedgerState
    if (-not $st.Readable) { Write-Output 'UNREADABLE' }
    elseif ($null -eq $st.Last) { Write-Output 'ABSENT' }
    elseif ($st.Last -ceq $TERMINATOR) { Write-Output 'CLOSED' }
    else { Write-Output ('OPEN ' + $st.Last) }
    exit 0
  }
  'close' {
    $st = Get-LedgerState
    # LG-1 repair: refuse to append to a ledger whose state could not be read. The draft fell
    # through to the append here, so `close` on a read-denied ledger wrote a SECOND terminator
    # and broke the documented idempotency of this subcommand, mutating a file whose contents it
    # had never seen. Appending blind is the one thing a writer must not do when its read failed.
    if (-not $st.Readable) {
      [Console]::Error.WriteLine('ledger: run-progress exists but cannot be read; nothing appended')
      exit 0
    }
    if ($null -ne $st.Last -and $st.Last -ceq $TERMINATOR) { exit 0 }
    try {
      New-Item -ItemType Directory -Force -Path $phanesDir | Out-Null
      [System.IO.File]::AppendAllText($ledgerFile, $TERMINATOR + "`n", $UTF8_NO_BOM)
    } catch {
      [Console]::Error.WriteLine("ledger: cannot write $ledgerFile ($($_.Exception.Message))")
    }
    exit 0
  }
  'reset' {
    if (-not (Test-Path -LiteralPath $ledgerFile)) {
      [Console]::Error.WriteLine('ledger: no run-progress ledger to reset')
      exit 0
    }
    try {
      Move-Item -LiteralPath $ledgerFile -Destination $prevFile -Force
      [System.IO.File]::WriteAllText($ledgerFile, '', $UTF8_NO_BOM)
      Write-Output ('ledger: archived to run-progress.prev, fresh ledger started')
    } catch {
      [Console]::Error.WriteLine("ledger: reset failed ($($_.Exception.Message)), ledger left as it was")
    }
    exit 0
  }
  default {
    [Console]::Error.WriteLine('ledger: usage: ledger append "<line>" | ledger status | ledger close | ledger reset')
    exit 0
  }
}
