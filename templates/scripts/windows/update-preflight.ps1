# phanes-template v3.4.0 update-preflight
# The update-run fast-path aggregator: runs the sensors (census-diff, hook table, register
# breach state, manifest sha256 drift, module-list vs config, optional spec-version compare)
# and the git delta, and emits ONE JSON verdict {sensors, quiet, gitDelta}. quiet is true only
# on POSITIVE evidence of stasis: a sensor that cannot observe reports available:false and the
# verdict is NOT quiet, because unknown is not quiet. gitDelta is separate from quiet by
# contract: the session requires quiet AND gitDelta.available AND an empty changedFiles before
# taking the fast path. hook-verify folds in here: `update-preflight --hooks-only` prints just
# the hooks sensor (the standalone hook-verify form; same logic, one implementation).
# Optional: --spec-version <v> compares the RUNNING spec's version against the installed one;
# without it that sensor is reported not-provided and excluded from quiet (Step 0's own
# self-version check already covers it and is never skipped). Advisory: always exits 0.
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

# --- arguments
$hooksOnly = $false
$specVersion = $null
$specVersionMissing = $false
for ($i = 0; $i -lt $args.Count; $i++) {
  $a = [string]$args[$i]
  if ($a -ceq '--hooks-only') { $hooksOnly = $true }
  elseif ($a -ceq '--spec-version') {
    # M5 repair, and SS00028's field investigation sharpened this well beyond its recorded
    # severity. This flag IS the new-spec-versus-old-scripts skew sensor, and skew is the NORMAL
    # state of every untouched project after a release: phanes.md propagates globally and
    # instantly from ~/.claude/commands, while scripts propagate to a project only when someone
    # runs an update there. The draft exited 0 printing NOTHING when the flag carried no value,
    # which a caller parses as null and reads as "no skew". A sensor whose whole job is catching
    # the normal post-release condition had a SILENT ALL-CLEAR failure mode. It now falls through
    # and emits the full verdict with the spec sensor explicitly unavailable, so the caller sees
    # could-not-observe rather than nothing at all.
    if ($i + 1 -ge $args.Count) {
      [Console]::Error.WriteLine('update-preflight: --spec-version requires a value; the spec sensor reports unavailable')
      $specVersionMissing = $true
    } else { $specVersion = [string]$args[$i + 1]; $i++ }
  }
  else { [Console]::Error.WriteLine("update-preflight: unknown argument '$a' ignored") }
}

$root = Find-PhanesRoot
if (-not $root) {
  [Console]::Error.WriteLine('update-preflight: .phanes/config.json not found from this directory')
  Write-Output (ConvertTo-NodeJson ([ordered]@{ sensors = [ordered]@{}; quiet = $false; gitDelta = [ordered]@{ available = $false; reason = 'no project root' } }) 0)
  exit 0
}

$cfgRead = Read-PhanesJsonFile (Join-Path $root '.phanes\config.json')
$cfg = $cfgRead.Value
$cfgOk = ($cfgRead.Status -ceq 'ok')

# ---------- hooks sensor (the folded hook-verify) ----------
function Get-HooksSensor {
  $sensor = [ordered]@{ available = $true; delta = $false }
  $settingsPath = Join-Path $script:root '.claude\settings.json'
  # m5 repair, an inverse inconsistency rather than a missing guard. The three input states
  # collapsed into two here, and they collapsed the wrong way round: a MALFORMED settings file
  # correctly reported available: false, while an ABSENT one reported available: true, and an
  # UNREADABLE one (denied ACL) was silently treated as absent by Test-Path's failure. Absent is
  # a genuine observation, and the honest reading of it is "no hooks are configured", so it stays
  # available with delta true from the per-hook loop below. Unreadable and malformed are both
  # could-not-observe and now report identically.
  $settings = $null
  $sr = Read-PhanesJsonFile $settingsPath
  if ($sr.Status -ceq 'ok') { $settings = $sr.Value }
  elseif ($sr.Status -cne 'absent') {
    $sensor.available = $false; $sensor.delta = $true
    $sensor.reason = ".claude/settings.json is $($sr.Status) ($($sr.Reason))"
    return $sensor
  }
  $wanted = @(
    @{ key = 'stampGuard'; event = 'PreToolUse'; needle = 'hook-stamp-guard' },
    @{ key = 'sizeCheck'; event = 'PostToolUse'; needle = 'hook-size-check' },
    @{ key = 'ledgerStatus'; event = 'SessionStart'; needle = 'hook-ledger-status' }
  )
  foreach ($w in $wanted) {
    $entry = [ordered]@{ present = $false; pathDiscipline = $false; scriptExists = $false }
    $cmd = $null
    if ($settings -and $settings.hooks -and $settings.hooks.($w.event)) {
      foreach ($grp in @($settings.hooks.($w.event))) {
        foreach ($h in @($grp.hooks)) {
          if (($h.command -is [string]) -and ([string]$h.command).IndexOf($w.needle, [System.StringComparison]::Ordinal) -ge 0) { $cmd = [string]$h.command; break }
        }
        if ($null -ne $cmd) { break }
      }
    }
    if ($null -ne $cmd) {
      $entry.present = $true
      $entry.pathDiscipline = (($cmd.IndexOf('.phanes/scripts/', [System.StringComparison]::Ordinal) -ge 0) -and -not ($cmd -match '(?i)[a-z]:[\\/]') -and -not ($cmd -match '(^|\s)/'))
      $entry.scriptExists = (Test-Path -LiteralPath (Join-Path $script:root ('.phanes\scripts\' + $w.needle + '.ps1')))
    }
    if (-not ($entry.present -and $entry.pathDiscipline -and $entry.scriptExists)) { $sensor.delta = $true }
    $sensor[$w.key] = $entry
  }
  return $sensor
}

$hooksSensor = Get-HooksSensor
if ($hooksOnly) {
  Write-Output (ConvertTo-NodeJson ([ordered]@{ hooks = $hooksSensor }) 0)
  exit 0
}

$sensors = [ordered]@{}
$here = $PSScriptRoot

# ---------- spec sensor (optional by design) ----------
$spec = [ordered]@{ available = $false; delta = $false; reason = 'spec version not provided; Step 0 covers it' }
# The two not-provided cases are NOT the same and must not report the same thing. Nobody asked
# (no flag) is a quiet, expected state that Step 0 covers by other means. Somebody asked and the
# value was missing is a FAILED sensor reading, and a failed reading is never quiet: delta is
# true so the composite fast-path condition cannot evaluate to quiet on the strength of a
# question that was never actually answered.
if ($specVersionMissing) {
  $spec = [ordered]@{ available = $false; delta = $true; reason = '--spec-version was passed with no value; skew could NOT be measured' }
}
elseif ($null -ne $specVersion) {
  $spec = [ordered]@{ available = $true; delta = $false; spec = $specVersion; installed = $null }
  if ($cfgOk -and ($cfg.phanesVersion -is [string])) { $spec.installed = $cfg.phanesVersion }
  if ($spec.installed -isnot [string] -or ($spec.installed -cne $specVersion)) { $spec.delta = $true }
}
$sensors.spec = $spec

# ---------- census sensor (sibling census-diff, one implementation) ----------
$census = [ordered]@{ available = $false; delta = $true }
try {
  $cdPath = Join-Path $here 'census-diff.ps1'
  if (Test-Path -LiteralPath $cdPath) {
    $cdOut = (& $cdPath) -join "`n"
    if ($LASTEXITCODE -eq 0 -and $cdOut) {
      $cd = $cdOut | ConvertFrom-Json
      $census.available = $true
      $census.delta = (-not $cd.selectionPresent) -or $cd.configUntrusted -or (-not $cd.mcpAvailable) -or ($cd.addedCount -gt 0) -or ($cd.removedCount -gt 0) -or ($cd.changedCount -gt 0)
      $census.addedCount = $cd.addedCount; $census.removedCount = $cd.removedCount; $census.changedCount = $cd.changedCount
      $census.selectionPresent = $cd.selectionPresent; $census.mcpAvailable = $cd.mcpAvailable
    } else { $census.reason = 'census-diff failed or printed nothing' }
  } else { $census.reason = 'census-diff.ps1 not installed' }
} catch { $census.reason = "census-diff crashed ($($_.Exception.Message))" }
$sensors.census = $census

# ---------- hooks sensor ----------
$sensors.hooks = $hooksSensor

# ---------- register sensor (sibling register-check) ----------
$register = [ordered]@{ available = $false; delta = $true }
try {
  $rcPath = Join-Path $here 'register-check.ps1'
  if (Test-Path -LiteralPath $rcPath) {
    $rcOut = @(& $rcPath)
    if ($LASTEXITCODE -eq 0) {
      $register.available = $true
      $register.delta = $false
      $statuses = [ordered]@{}
      foreach ($lnObj in $rcOut) {
        $ln = [string]$lnObj
        $m = [regex]::Match($ln, '^(CLAUDE\.md|CLAUDE\.local\.md): (.*)$')
        if (-not $m.Success) { continue }
        $v = $m.Groups[2].Value
        if ($v -ceq 'absent') { $statuses[$m.Groups[1].Value] = 'absent'; $register.delta = $true }
        elseif ($v.IndexOf('[CROP-REQUIRED]', [System.StringComparison]::Ordinal) -ge 0) { $statuses[$m.Groups[1].Value] = 'CROP-REQUIRED'; $register.delta = $true }
        elseif ($v.IndexOf('[SOFT-BREACH]', [System.StringComparison]::Ordinal) -ge 0) { $statuses[$m.Groups[1].Value] = 'SOFT-BREACH'; $register.delta = $true }
        else { $statuses[$m.Groups[1].Value] = 'OK' }
      }
      $register.status = $statuses
    } else { $register.reason = "register-check exited $LASTEXITCODE" }
  } else { $register.reason = 'register-check.ps1 not installed' }
} catch { $register.reason = "register-check crashed ($($_.Exception.Message))" }
$sensors.register = $register

# ---------- manifest drift sensor ----------
$manifest = [ordered]@{ available = $false; delta = $true }
$manifestPath = Join-Path $root '.phanes\manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) {
  $manifest.reason = '.phanes/manifest.json absent (provenance unknown; pre-v3.4 install or incomplete run)'
} else {
  try {
    $prov = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    $drifted = New-Object System.Collections.ArrayList
    $missing = New-Object System.Collections.ArrayList
    $checked = 0
    foreach ($a in @($prov.artifacts)) {
      if (-not ($a.path -is [string]) -or -not ($a.sha256 -is [string])) { continue }
      $checked++
      $full = Join-Path $root (($a.path -replace '/', '\'))
      if (-not (Test-Path -LiteralPath $full)) { [void]$missing.Add($a.path); continue }
      try { $disk = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash } catch { [void]$drifted.Add($a.path); continue }
      if (-not [string]::Equals($disk, $a.sha256, [System.StringComparison]::OrdinalIgnoreCase)) { [void]$drifted.Add($a.path) }
    }
    $driftedArr = $drifted.ToArray(); [Array]::Sort($driftedArr, [System.StringComparer]::Ordinal)
    $missingArr = $missing.ToArray(); [Array]::Sort($missingArr, [System.StringComparer]::Ordinal)
    $manifest.available = $true
    $manifest.delta = ($driftedArr.Count -gt 0 -or $missingArr.Count -gt 0)
    $manifest.checked = $checked
    $manifest.driftedCount = $driftedArr.Count
    $manifest.drifted = @($driftedArr | Select-Object -First $CAP)
    $manifest.missingCount = $missingArr.Count
    $manifest.missing = @($missingArr | Select-Object -First $CAP)
    $manifest.listTruncated = ($driftedArr.Count -gt $CAP -or $missingArr.Count -gt $CAP)
  } catch {
    $manifest.reason = '.phanes/manifest.json is malformed'
  }
}
$sensors.manifest = $manifest

# ---------- modules sensor (sibling module-list vs config; a consistency check that catches
# ---------- malformed config and a bespoke module-list whose verdict drifted) ----------
$modules = [ordered]@{ available = $false; delta = $true }
try {
  $mlPath = Join-Path $here 'module-list.ps1'
  if (Test-Path -LiteralPath $mlPath) {
    $mlOut = @(& $mlPath | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -eq 0) {
      $modules.available = $true
      $expected = @()
      if ($cfgOk -and $cfg.modules) { $expected = @($cfg.modules | ForEach-Object { [string]$_ }) }
      if ($expected.Count -eq 0) { $expected = @('(no modules configured)') }
      $modules.delta = $false
      if ($mlOut.Count -ne $expected.Count) { $modules.delta = $true }
      else { for ($i = 0; $i -lt $expected.Count; $i++) { if ($mlOut[$i] -cne $expected[$i]) { $modules.delta = $true; break } } }
      $modules.count = $mlOut.Count
    } else { $modules.reason = "module-list exited $LASTEXITCODE (malformed config or bespoke script)" }
  } else { $modules.reason = 'module-list.ps1 not installed' }
} catch { $modules.reason = "module-list crashed ($($_.Exception.Message))" }
$sensors.modules = $modules

# ---------- customization inventory (W3.4) ----------
# This sensor runs OFFLINE. It therefore CANNOT know the current template hash and MUST NOT
# claim staleness: the staleness verdict belongs to install-templates, which holds the staged
# template at the moment it decides to preserve. What this can honestly report is the INVENTORY:
# which files are customized, and whether each one even has a baseline to be compared against
# later. A pre-v3.4 manifest carries no templateSha256, so those entries report
# templateSha256Known false and are counted as UNKNOWN, never as fresh and never as stale.
# This is degrade-never-fabricate applied to a new sensor, which matters given how much of the
# review that produced it was about sensors inventing answers.
#
# Deliberately NOT an input to `quiet`, and the reason is worth stating because it looks like an
# omission. UNKNOWN is the normal, permanent state for every project installed before v3.4, so
# feeding it into quiet would make those projects non-quiet forever and destroy the fast path
# this whole workstream exists to build. This sensor informs; it does not gate.
$customizations = [ordered]@{ available = $false; count = 0; unknownCount = 0; entries = @(); listTruncated = $false }
$mfRead = Read-PhanesJsonFile (Join-Path $root '.phanes\manifest.json') 'artifacts'
if ($mfRead.Status -ceq 'ok') {
  $customizations.available = $true
  $rows = New-Object System.Collections.ArrayList
  $unknown = 0
  foreach ($a in @($mfRead.Value.artifacts)) {
    if (-not ($a.customized -is [bool]) -or -not $a.customized) { continue }
    $known = ($a.templateSha256 -is [string]) -and (([string]$a.templateSha256).Trim() -cne '')
    if (-not $known) { $unknown++ }
    [void]$rows.Add([ordered]@{ path = [string]$a.path; templateSha256Known = $known })
  }
  $customizations.count = $rows.Count
  $customizations.unknownCount = $unknown
  $customizations.entries = @($rows | Select-Object -First $CAP)
  $customizations.listTruncated = ($rows.Count -gt $CAP)
} else {
  $customizations.reason = "manifest is $($mfRead.Status)"
}
$sensors.customizations = $customizations

# ---------- git delta (separate from quiet by contract) ----------
$gitDelta = [ordered]@{ available = $false }
$lastRef = $null
if ($cfgOk -and $cfg.lastRun -and ($cfg.lastRun.ref -is [string]) -and $cfg.lastRun.ref -cne '') { $lastRef = [string]$cfg.lastRun.ref }
if ($null -eq $lastRef) {
  $gitDelta.reason = 'no lastRun.ref recorded in config'
} else {
  try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
  Push-Location $root
  try {
    $diffRaw = & git diff --name-only "$lastRef..HEAD"
    if ($LASTEXITCODE -ne 0) {
      $gitDelta.reason = 'git diff failed (not a repository, git unavailable, or the recorded ref is gone)'
    } else {
      $files = @($diffRaw | ForEach-Object { [string]$_ } | Where-Object { $_ -cne '' })
      $gitDelta.available = $true
      $gitDelta.ref = $lastRef
      $gitDelta.changedCount = $files.Count
      $gitDelta.changedFiles = @($files | Select-Object -First $CAP)
      $gitDelta.listTruncated = ($files.Count -gt $CAP)
      # `git diff <ref>..HEAD` sees COMMITTED history only, so FOUR classes of real work are
      # invisible to it: modified-tracked, staged-uncommitted, untracked, and deleted-tracked.
      # Measured: the composite fast-path condition (quiet AND available AND empty changedFiles)
      # evaluated TRUE on a materially dirty worktree, licensing a skip over uncommitted work.
      # `git status --porcelain` closes all four with one cheap call, and the flag is reported
      # rather than folded into changedFiles, because "committed since the last run" and "dirty
      # right now" are different questions and the session's rule branches on both.
      $worktreeDirty = $null
      try {
        $porcelain = & git status --porcelain
        if ($LASTEXITCODE -eq 0) { $worktreeDirty = (@($porcelain | Where-Object { [string]$_ -cne '' }).Count -gt 0) }
      } catch { $worktreeDirty = $null }
      $gitDelta.worktreeDirty = $worktreeDirty
    }
  } catch {
    # Redirected native stderr under EAP-Stop lands here (the loc-check class), so this path
    # covers the same three causes as the exit-code branch; do not name only one of them.
    $gitDelta.reason = 'git diff failed (not a repository, git unavailable, or the recorded ref is gone)'
  } finally {
    Pop-Location
  }
}

# ---------- verdict ----------
$quiet = $true
foreach ($name in @('census', 'hooks', 'register', 'manifest', 'modules')) {
  $s = $sensors[$name]
  if (-not $s.available -or $s.delta) { $quiet = $false }
}
if ($sensors.spec.available -and $sensors.spec.delta) { $quiet = $false }

Write-Output (ConvertTo-NodeJson ([ordered]@{ sensors = $sensors; quiet = $quiet; gitDelta = $gitDelta }) 0)
exit 0
