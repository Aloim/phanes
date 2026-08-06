# phanes-template v3.4.0 preflight
# Phase 0 mechanical pre-flights, observed and reported, NEVER acted on: run-type marker,
# installed version, upstream stamp (network-tolerant, 10s timeout, single attempt), the four
# standard MCP servers via `claude mcp list`, platform, capability-census counts, and the
# legacy-migration signals. Emits ONE digest JSON. Consent, AskUserQuestion, MCP installs, the
# STOP-and-route-to-phanesupgrade judgment, and every other decision stay in the session: this
# script observes and never mutates anything. Advisory: always exits 0.
$ErrorActionPreference = 'Stop'
$CAP = 20

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

# BEGIN SHARED looseroot

# The loose root, for preflight and preflight only: the one command that must also run against
# a project Phanes has NOT bootstrapped yet, where no .phanes/config.json exists. Strict root
# first, then a BOUNDED walk for a .claude directory, then the current directory.
#
# The walk is bounded because the unbounded version was the worst single defect in this set: it
# walked up into the user profile and censused the whole machine as the project, reporting 6
# project commands and 12 CLAUDE.md files on an EMPTY fixture. The draft's fix excluded one
# literal string, $env:USERPROFILE, and SKIPPED that rung rather than stopping at it, and it
# did not hold. Review reproduced the original signature three separate ways: a subst drive
# aliasing the profile, USERPROFILE unset, and a second .claude sitting above the excluded
# profile. Worse, on this machine that fix held by ACCIDENT OF DIRECTORY LAYOUT rather than by
# construction, because the ladder above the profile happens to contain no .claude today.
#
# Four stop conditions replace the one exclusion, each tied to a reproduced or measured case:
#   1. .git in this directory   Stop after testing this level. Never walk out of a repository
#                               into its parent. This is also what protects a fresh project
#                               sitting under a directory that has grown its own .claude:
#                               there is no C:\Projects\.claude on this machine today, and a
#                               single mkdir would otherwise make twelve sibling projects
#                               census as one.
#   2. the home directory       Stop. Resolved by identity through three candidates, not by
#                               comparing one environment string that can be unset or spelled
#                               differently from the walk's own spelling.
#   3. no parent                A drive root and a UNC share root are never project roots, and
#                               this is refused WITHOUT testing the directory, which is what
#                               closes the subst case without P/Invoking
#                               GetFinalPathNameByHandle: R: mapped onto the profile is reached
#                               as a drive root and refused there. Note carefully that the
#                               refusal only works because it is evaluated before the accept.
#                               R:\ genuinely does carry a .claude (it IS the profile), so a
#                               no-parent check placed after the accept never runs.
#   4. depth cap of 24          A backstop, not a rule. It should never be the thing that stops
#                               a real walk, and if it ever is, Source and StoppedBy say so.
#
# Returns a hashtable: Root, Source ('config' | 'claude-walk' | 'cwd' | 'none') and StoppedBy.
# It reports HOW it chose, not just what it chose, because preflight is observe-only and the
# session does the judging. A root reached by guessing is something the caller is entitled to
# know about before it acts on a census taken there; the draft returned a bare path, which is
# precisely why a mis-root was indistinguishable from a correct root in the output.
function Find-PhanesRootLoose {
  $strict = Find-PhanesRoot
  if ($strict) { return @{ Root = $strict; Source = 'config'; StoppedBy = $null } }
  $homeDir = Get-PhanesHomeDirectory
  $start = Get-PhanesStartDirectory
  $cwd = $null
  if ($null -ne $start) { $cwd = $start.FullName }
  $d = $start
  $depth = 0
  $stopped = 'exhausted'
  while ($null -ne $d) {
    # EVERY refusing stop is evaluated BEFORE the accept, and that grouping is the whole design,
    # not a style choice. A stop placed after the accept does not stop anything: the walk still
    # ends on the forbidden directory, it just gets there by SUCCEEDING instead of by
    # continuing, which is the original defect wearing a different shape. This was written the
    # wrong way round twice while drafting and caught both times only by running it: first the
    # home stop sat after the accept and a deep directory under the profile returned
    # C:\Users\<user> as a claude-walk root; then, with home fixed, the no-parent stop still sat
    # after the accept and `subst R: %USERPROFILE%` returned R:\ as a claude-walk root, which is
    # the profile again wearing a drive letter. Two instances, one class. Keep the stops
    # together and above the accept, and the class cannot recur.
    if ($depth -ge 24) { $stopped = 'depth-cap'; break }
    if ($homeDir -and [string]::Equals($d.FullName, $homeDir, [System.StringComparison]::OrdinalIgnoreCase)) {
      $stopped = 'home'; break
    }
    if ($null -eq $d.Parent) { $stopped = 'filesystem-root'; break }
    try {
      if (Test-Path -LiteralPath (Join-Path $d.FullName '.claude')) {
        return @{ Root = $d.FullName; Source = 'claude-walk'; StoppedBy = $null }
      }
    } catch { }
    try {
      if (Test-Path -LiteralPath (Join-Path $d.FullName '.git')) { $stopped = 'git-root'; break }
    } catch { }
    $d = $d.Parent
    $depth = $depth + 1
  }
  if ($cwd) { return @{ Root = $cwd; Source = 'cwd'; StoppedBy = $stopped } }
  return @{ Root = $null; Source = 'none'; StoppedBy = $stopped }
}
# END SHARED looseroot

# --- REMOVED 2026-08-05: the local ConvertTo-JsonStringLiteral / ConvertTo-NodeJson pair and
# --- the local Find-Root now live in the shared regions above. The emitter was one of five
# --- byte-identical copies in two clusters, and Find-Root was the single hand-modified copy of
# --- Find-PhanesRoot in the whole set, which is exactly the copy that carried the mis-root
# --- defect. Both are now stated once, in Task 0 Step 1.
# Root discovery is looser than the other scripts on purpose: preflight is the one command that
# must also run against a project Phanes has NOT fully bootstrapped (partial installs, the
# anomaly case). Find-PhanesRootLoose reports HOW it chose as well as what it chose, and that
# is surfaced in the JSON below: an observe-only sensor that had to guess its own root must say
# so, or the session cannot tell a real census from a census of the wrong tree.
$rootInfo = Find-PhanesRootLoose
$root = $rootInfo.Root
if (-not $root) { $root = '.' }

# --- marker and run type (phanes.md: "The .claude/.phanes marker file is the SOLE authority
# --- on install state"; the anomaly rule is applied by the SESSION, this only reports it)
#
# B4 repair, and this is the most consequential single fix in the script. The draft caught the
# read failure and set $marker = $null, which is the SAME value an absent marker produces. The
# marker is the sole authority on install state, so an ACL-denied marker on a fully installed
# project reported a verdict the session acts on by running setup again, with no stderr note
# and no flag anywhere in the JSON to say the authority had not actually been consulted. Three
# states, three answers: markerReadable false means could-not-observe and is never conflated
# with an absent marker.
$marker = $null
$markerReadable = $true
$markerPath = Join-Path $root '.claude\.phanes'
$mk = Read-PhanesTextFile $markerPath
if ($mk.Status -ceq 'ok') { $marker = ([string]$mk.Text).Trim() }
elseif ($mk.Status -cne 'absent') {
  $markerReadable = $false
  [Console]::Error.WriteLine("preflight: the .claude/.phanes marker exists but could not be read; install state is UNKNOWN, not fresh")
}

# --- installed version from .phanes/config.json (guarded; malformed reads as null, and the
# --- three failure states stay distinct for the same reason the marker's do)
$cfg = $null
$installedVersion = $null
$docRoot = 'documentation'
$configReadable = $true
$cfgPath = Join-Path $root '.phanes\config.json'
$cfgRead = Read-PhanesJsonFile $cfgPath
if ($cfgRead.Status -ceq 'ok') { $cfg = $cfgRead.Value }
elseif ($cfgRead.Status -cne 'absent') { $configReadable = $false }
if ($null -ne $cfg) {
  if ($cfg.phanesVersion -is [string]) { $installedVersion = $cfg.phanesVersion }
  if ($cfg.docRoot -is [string] -and ([string]$cfg.docRoot).Trim() -cne '') { $docRoot = ([string]$cfg.docRoot).Trim().TrimEnd('/', '\') }
}

# N3 repair. runType is decided from the marker, which is the spec's sole authority, and the
# anomaly branch exists for the partial-bootstrap case: marker absent but project furniture
# present. The draft tested only whether `.phanes` EXISTS, and after a successful full-chain
# install `.phanes` always exists, so a healthy fresh install reported `anomaly`. The branch
# now requires the furniture to be present AND the marker to be genuinely absent rather than
# merely unread, which is what the phanes.md rule actually describes.
$runType = 'setup'
if (-not $markerReadable) { $runType = 'unknown' }
elseif ($null -ne $marker) { $runType = 'update' }
elseif ((Test-Path -LiteralPath (Join-Path $root '.phanes\config.json')) -or (Test-Path -LiteralPath (Join-Path (Join-Path $root $docRoot) 'session-summaries'))) { $runType = 'anomaly' }

# --- upstream stamp (network-tolerant: single attempt, 10 second timeout, sanity-checked;
# --- every failure shape degrades to null, never to a stop)
$upstream = $null
$tmp = Join-Path $env:TEMP ("phanes-upstream-" + [System.Guid]::NewGuid().ToString('N') + ".md")
try {
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
  Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/Aloim/phanes/main/phanes.md' -OutFile $tmp -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
  $line1 = Get-Content -LiteralPath $tmp -TotalCount 1 -Encoding utf8
  if ($line1 -is [string] -and $line1.StartsWith('<!-- Phanes v', [System.StringComparison]::Ordinal)) {
    $m = [regex]::Match($line1, 'Phanes v(\d+\.\d+(?:\.\d+)?)')
    if ($m.Success) { $upstream = $m.Groups[1].Value }
  }
} catch {
  $upstream = $null
  [Console]::Error.WriteLine('preflight: upstream stamp fetch failed (offline, rate-limited, or unreachable); upstream reported as null')
} finally {
  if (Test-Path -LiteralPath $tmp) { try { Remove-Item -LiteralPath $tmp -Force } catch { } }
}

# --- the four standard MCP servers via `claude mcp list` (native call in try/catch under
# --- EAP-Stop; a failed listing degrades all four to null, never to false: an empty result
# --- from a FAILED call is not an authoritative empty set)
$mcpLines = $null
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
try {
  # B5 repair: no `2>$null` on a native call under EAP-Stop. Redirecting a native command's
  # stderr inside PowerShell 5.1 wraps each stderr line in an ErrorRecord, which under
  # $ErrorActionPreference = 'Stop' becomes TERMINATING. So one line of incidental stderr,
  # beside a perfectly VALID server list on stdout, threw straight past this catch's intent and
  # discarded the entire MCP surface as "unavailable or failed". That is a live path, not a
  # hypothetical: node and npx deprecation notices print to stderr on an npx-launched CLI. The
  # exit code, not the presence of stderr, decides whether the listing is usable. This is the
  # same reasoning Global Constraint line 20 already applies to install-templates' smoke run.
  $mcpRaw = & claude mcp list
  if ($LASTEXITCODE -ne 0) { $mcpRaw = $null }
  if ($null -ne $mcpRaw) { $mcpLines = @($mcpRaw | ForEach-Object { [string]$_ } | Where-Object { $_.Contains(': ') }) }
} catch {
  $mcpLines = $null
}
$mcp = [ordered]@{ context7 = $null; deepwiki = $null; serena = $null; semble = $null }
$mcpServerCount = $null
if ($null -ne $mcpLines) {
  $names = @()
  foreach ($ln in $mcpLines) {
    $i = $ln.IndexOf(': ', [System.StringComparison]::Ordinal)
    if ($i -gt 0) { $names += $ln.Substring(0, $i) }
  }
  $mcpServerCount = $names.Count
  foreach ($k in @('context7', 'deepwiki', 'serena', 'semble')) {
    $found = $false
    foreach ($n in $names) { if ($n.IndexOf($k, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $found = $true; break } }
    $mcp[$k] = $found
  }
} else {
  [Console]::Error.WriteLine('preflight: `claude mcp list` unavailable or failed; mcp fields reported as null, not false')
}

# --- census counts, disk-visible surfaces only (auth probing stays in the session)
#
# B8 repair. Both counters returned 0 on an unreadable directory, and 0 is an authoritative
# number: "this project has no project commands" is a different claim from "I could not look".
# The consumer of this JSON cannot tell them apart, and the census is one of the inputs to the
# legacy-migration judgment. $null is the could-not-observe value throughout this script (the
# mcp fields already use it for exactly this reason), so the counters use it too, and every
# unreadable surface is named on stderr rather than silently flattened.
$censusUnreadable = New-Object System.Collections.ArrayList
function Count-Files([string]$dir, [string]$filter) {
  if (-not (Test-Path -LiteralPath $dir)) { return 0 }
  try { return @(Get-ChildItem -LiteralPath $dir -File -Filter $filter -ErrorAction Stop).Count }
  catch { [void]$censusUnreadable.Add($dir); [Console]::Error.WriteLine("preflight: cannot enumerate $dir; reported as null, not 0"); return $null }
}
function Count-Dirs([string]$dir) {
  if (-not (Test-Path -LiteralPath $dir)) { return 0 }
  try { return @(Get-ChildItem -LiteralPath $dir -Directory -ErrorAction Stop).Count }
  catch { [void]$censusUnreadable.Add($dir); [Console]::Error.WriteLine("preflight: cannot enumerate $dir; reported as null, not 0"); return $null }
}

# B2 repair: never Join-Path onto $env:USERPROFILE directly. With USERPROFILE unset that raises
# a TERMINATING error under EAP-Stop, so this script, which is contractually bound to always
# exit 0 and always emit one JSON digest, exited 1 with no output at all. Get-PhanesHomeDirectory
# resolves the home directory through three candidates and returns $null rather than throwing;
# a $null home degrades the two user-scoped counts to could-not-observe, which is the honest
# answer and the same shape B8 uses.
$userHome = Get-PhanesHomeDirectory
$userClaude = $null
if ($userHome) { $userClaude = Join-Path $userHome '.claude' }
$agentFiles = @()
$agentsDir = Join-Path $root '.claude\agents'
if (Test-Path -LiteralPath $agentsDir) {
  try { $agentFiles = @(Get-ChildItem -LiteralPath $agentsDir -File -Filter '*.md' -ErrorAction Stop) } catch { $agentFiles = @() }
}
$pluginCount = $null
$pluginsJson = $null
if ($userClaude) { $pluginsJson = Join-Path $userClaude 'plugins\installed_plugins.json' }
if ($pluginsJson -and (Test-Path -LiteralPath $pluginsJson)) {
  $pluginCount = 0
  try {
    $pj = Get-Content -LiteralPath $pluginsJson -Raw -Encoding utf8 | ConvertFrom-Json
    if ($pj.plugins -is [System.Management.Automation.PSCustomObject]) {
      foreach ($prop in @($pj.plugins.PSObject.Properties | ForEach-Object { $_ })) {
        foreach ($inst in @($prop.Value)) {
          $scopeOk = ($inst.scope -ceq 'user') -or (($inst.scope -ceq 'project') -and ($inst.projectPath -is [string]) -and ([string]::Equals($inst.projectPath, $root, [System.StringComparison]::OrdinalIgnoreCase)))
          if ($scopeOk) { $pluginCount++; break }
        }
      }
    }
  } catch { $pluginCount = $null; [Console]::Error.WriteLine("preflight: cannot read $pluginsJson; plugins reported as null, not 0") }
}
elseif ($userClaude) { $pluginCount = 0 }
$censusCounts = [ordered]@{
  agents = $agentFiles.Count
  commandsProject = Count-Files (Join-Path $root '.claude\commands') '*.md'
  commandsUser = $(if ($userClaude) { Count-Files (Join-Path $userClaude 'commands') '*.md' } else { $null })
  plugins = $pluginCount
  skillsProject = Count-Dirs (Join-Path $root '.claude\skills')
  skillsUser = $(if ($userClaude) { Count-Dirs (Join-Path $userClaude 'skills') } else { $null })
  mcpServers = $mcpServerCount
}

# --- legacy-migration signals (phanes.md: "no phanesVersion in .phanes/config.json and no
# --- version stamp anywhere; agents referencing sequential-thinking or an MCP memory server;
# --- ... per-subfolder CLAUDE.md sprawl; ... unprefixed template-shaped agents"). Signals
# --- only; the STOP-and-route-to-phanesupgrade judgment stays in the session.
$archetypes = @('executor', 'critic', 'planner', 'architect', 'designer', 'cleaner', 'synthesizer', 'close-verifier', 'scout', 'orchestrator', 'researcher', 'patch-author')
$unprefixed = New-Object System.Collections.ArrayList
$seqRefs = New-Object System.Collections.ArrayList
foreach ($f in $agentFiles) {
  $stem = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
  foreach ($a in $archetypes) { if ($stem -ceq $a) { [void]$unprefixed.Add($f.Name); break } }
  try {
    $head = (Get-Content -LiteralPath $f.FullName -TotalCount 60 -Encoding utf8) -join "`n"
    if ($head.IndexOf('sequential-thinking', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { [void]$seqRefs.Add($f.Name) }
  } catch { }
}
$claudeMdSprawl = $null
try {
  $claudeMdSprawl = @(Get-ChildItem -LiteralPath $root -Recurse -Depth 3 -File -Filter 'CLAUDE.md' -ErrorAction SilentlyContinue | Where-Object { $_.DirectoryName -cne $root }).Count
} catch { $claudeMdSprawl = $null }
$unprefixedArr = $unprefixed.ToArray(); [Array]::Sort($unprefixedArr, [System.StringComparer]::Ordinal)
$seqArr = $seqRefs.ToArray(); [Array]::Sort($seqArr, [System.StringComparer]::Ordinal)

# B7 repair: exact counts and a listTruncated flag, per Global Constraint line 25. The draft
# capped both lists at 20 and reported neither the true count nor the fact of truncation, so a
# consumer could not tell 20 legacy agents from 25 or from 200, on the signals that feed the
# legacy-migration STOP judgment. This was simultaneously a PLAN defect: the Interfaces block
# defined legacyMarkers without these fields, so the contract itself contradicted the Global
# Constraint and the implementation faithfully followed the contract. census-diff already
# implements the pattern correctly and is the reference shape.
$legacyMarkers = [ordered]@{
  noVersionStamp = (($runType -cne 'setup') -and ($null -eq $installedVersion))
  unprefixedTemplateAgents = @($unprefixedArr | Select-Object -First $CAP)
  unprefixedTemplateAgentsCount = $unprefixedArr.Count
  sequentialThinkingAgents = @($seqArr | Select-Object -First $CAP)
  sequentialThinkingAgentsCount = $seqArr.Count
  subfolderClaudeMdCount = $claudeMdSprawl
  listTruncated = (($unprefixedArr.Count -gt $CAP) -or ($seqArr.Count -gt $CAP))
}

$digest = [ordered]@{
  runType = $runType
  marker = $marker
  markerReadable = $markerReadable
  configReadable = $configReadable
  rootSource = $rootInfo.Source
  installedVersion = $installedVersion
  upstream = $upstream
  mcp = $mcp
  platform = 'windows'
  censusCounts = $censusCounts
  censusUnreadable = @($censusUnreadable.ToArray())
  legacyMarkers = $legacyMarkers
}
Write-Output (ConvertTo-NodeJson $digest 0)
exit 0
