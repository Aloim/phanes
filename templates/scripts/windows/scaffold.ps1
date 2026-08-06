# phanes-template v3.4.0 scaffold
# Mechanizes Phase 2.5 Steps 1, 1b, and 2: creates the documentation tree (under the
# configured docRoot), the tests tree, and the four verbatim README files, reading the README
# bodies from the installed prompt templates (.claude/template/readme-docs.md and
# readme-tests.md, SECTION blocks). Merge-never-overwrite: an EXISTING file or folder is never
# touched, only absent ones are created, and every creation is listed on stdout. CLAUDE.md and
# CLAUDE.local.md are deliberately NOT scaffold's to create: their blocks carry per-project
# judgment (Pinned Directives, capability register) and the session remains their writer.
# NOT advisory: exit 0 on success (including "nothing to do"); exit 1 when the project, config,
# or a required template cannot be read, or when a write fails (the session then falls back to
# writing the Step 1/1b/2 content from phanes.md directly). On a write failure the items already
# created ARE listed before the error: "nothing created" is achievable for every pre-write
# refusal and is NOT achievable once the eighth of nineteen writes fails, so the contract states
# what the script can actually guarantee rather than a promise it would break in silence.
$ErrorActionPreference = 'Stop'

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
if (-not $root) { [Console]::Error.WriteLine('scaffold: .phanes/config.json not found from this directory'); exit 1 }

# Creating trees in the WRONG place is worse than refusing: a malformed config is exit 1
# here, not a silent default (the docRoot decides where a whole tree lands).
$cfgRead = Read-PhanesJsonFile (Join-Path $root '.phanes\config.json')
if ($cfgRead.Status -cne 'ok') {
  [Console]::Error.WriteLine("scaffold: .phanes/config.json is $($cfgRead.Status) ($($cfgRead.Reason)); nothing created, repair the config first")
  exit 1
}
$cfg = $cfgRead.Value

# D7 repair. docRoot decides where an entire 19-item tree lands, and the draft checked it for
# JSON-parseability and string-ness only. `docRoot: "../escaped docs"` built the whole tree ONE
# LEVEL ABOVE the project and exited 0. This is the same class SS00025's W1.3 item b already
# fixed once elsewhere in the library, which is why it is worth naming rather than just fixing.
# Two related shapes died with unhandled exceptions instead: an absolute docRoot, and a
# whitespace-only docRoot (TrimEnd('/','\') does not trim spaces, so the value survived the
# emptiness test and then failed at the filesystem).
$docRoot = 'documentation'
if ($cfg.docRoot -is [string] -and ([string]$cfg.docRoot).Trim() -cne '') {
  $docRoot = ([string]$cfg.docRoot).Trim().TrimEnd('/', '\')
}
if ($docRoot -ceq '') { $docRoot = 'documentation' }
if ([System.IO.Path]::IsPathRooted($docRoot)) {
  [Console]::Error.WriteLine("scaffold: docRoot '$docRoot' is an absolute path; docRoot must be relative to the project root. Nothing created")
  exit 1
}
if (-not (Test-PhanesContained $root (Join-Path $root ($docRoot -replace '/', '\')))) {
  [Console]::Error.WriteLine("scaffold: docRoot '$docRoot' resolves outside the project root; nothing created")
  exit 1
}

# SECTION parser for the installed prompt templates. A missing or malformed template is a
# refusal naming the file: the fallback (authoring from the phanes.md verbatim blocks) is the
# session's judgment, not this script's.
# The parser was weak in five ways, and every one of them writes WRONG CONTENT at exit 0 rather
# than failing, which merge-never-overwrite then makes permanent: the bad file is never
# corrected on a later run, because a later run sees a file that already exists. That is what
# makes a parser bug here worse than a crash, and why all five refuse instead.
#   D1  section names were looked up case-insensitively (bare @{}), so a damaged template with
#       the wrong casing was silently accepted.
#   D2  duplicate section names silently last-won.
#   D3  an END marker inside a fenced code block closed the section early: observed truncating
#       a body to a 33-byte stub.
#   D4  an empty section produced a 1-byte file.
#   D5  a marker whose name fell outside the [A-Za-z0-9-] charset was not recognized as a
#       marker at all, so the literal marker line shipped verbatim into the README.
# Returns $null for unreadable, or a hashtable; parse defects throw a message the caller turns
# into a refusal naming the file.
function Get-Sections([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  $lines = @()
  try { $lines = @(Get-Content -LiteralPath $path -Encoding utf8) } catch { return $null }
  $sections = New-OrdinalHashtable   # D1
  $cur = $null
  $fenced = $false
  $buf = New-Object System.Collections.ArrayList
  foreach ($ln in $lines) {
    $t = $ln.TrimEnd()
    # D3: track fenced blocks so a marker quoted inside an example cannot close a section.
    if ($t -cmatch '^\s*```') { $fenced = -not $fenced }
    if (-not $fenced) {
      $m = [regex]::Match($t, '^<!-- SECTION (\S+) -->$')
      if ($m.Success) {
        $name = $m.Groups[1].Value
        # D5: a marker that looks like a marker but carries an out-of-charset name is a DAMAGED
        # template, not body text. Refusing beats shipping the marker line into a README.
        if ($name -cnotmatch '^[A-Za-z0-9-]+$') { throw "SECTION name '$name' contains characters outside [A-Za-z0-9-]" }
        if ($null -ne $cur) { throw "SECTION $name opens while SECTION $cur is still open" }
        if ($sections.ContainsKey($name)) { throw "duplicate SECTION $name" }   # D2
        $cur = $name
        $buf = New-Object System.Collections.ArrayList
        continue
      }
      if ($t -ceq '<!-- END SECTION -->') {
        if ($null -eq $cur) { throw 'END SECTION with no open SECTION' }
        $body = (($buf.ToArray() -join "`n") + "`n")
        if ($body.Trim().Length -eq 0) { throw "SECTION $cur is empty" }        # D4
        $sections[$cur] = $body
        $cur = $null
        continue
      }
    }
    if ($null -ne $cur) { [void]$buf.Add($ln) }
  }
  if ($null -ne $cur) { throw "SECTION $cur is never closed" }
  if ($fenced) { throw 'unterminated code fence' }
  return $sections
}

$tplDir = Join-Path $root '.claude\template'
function Read-Template([string]$name) {
  try { return (Get-Sections (Join-Path $script:tplDir $name)) }
  catch {
    [Console]::Error.WriteLine("scaffold: .claude/template/$name is damaged ($($_.Exception.Message)); nothing created. Reinstall templates (phanes install-templates) or fall back to the phanes.md Step 1/1b/2 blocks")
    exit 1
  }
}
$docsTpl = Read-Template 'readme-docs.md'
$testsTpl = Read-Template 'readme-tests.md'
$headerTpl = Read-Template 'doc-header.md'
foreach ($pair in @(
    @('readme-docs.md', $docsTpl, @('session-summaries-readme', 'architecture-readme', 'registry-readme')),
    @('readme-tests.md', $testsTpl, @('tests-readme')),
    @('doc-header.md', $headerTpl, @('doc-discipline-header')))) {
  $fname = $pair[0]; $tpl = $pair[1]; $need = $pair[2]
  if ($null -eq $tpl) { [Console]::Error.WriteLine("scaffold: .claude/template/$fname is missing or unreadable; nothing created. Install templates first (phanes install-templates) or fall back to the phanes.md Step 1/1b/2 blocks"); exit 1 }
  foreach ($s in $need) {
    if (-not $tpl.ContainsKey($s)) { [Console]::Error.WriteLine("scaffold: .claude/template/$fname lacks SECTION $s; nothing created (template damaged or from another version)"); exit 1 }
  }
}

$created = New-Object System.Collections.ArrayList
$skipped = New-Object System.Collections.ArrayList

# D6 repair: both writers were entirely unguarded. A file seeded where a directory belongs
# created EIGHT directories and then died with a raw PowerShell stack trace, no `scaffold:`
# prefix and no summary line, against a contract promising "exit 1, nothing created". The same
# happened under a real deny-Write ACE. Guarding cannot restore "nothing created" once writes
# have begun, so the contract is corrected to what is actually achievable and the failure is
# reported honestly: every item created so far is listed, then the failed item is named.
#
# Every target also passes containment, not just docRoot. docRoot is the value most likely to
# escape, but it is not the only path assembled here, and a per-target gate costs nothing.
function Fail-Scaffold([string]$item, [string]$why) {
  foreach ($c in $script:created) { Write-Output ("CREATED $c") }
  [Console]::Error.WriteLine("scaffold: cannot create $item ($why); $($script:created.Count) item(s) were already created and are listed above")
  exit 1
}
function Ensure-Dir([string]$rel) {
  $full = Join-Path $script:root ($rel -replace '/', '\')
  if (-not (Test-PhanesContained $script:root $full)) { Fail-Scaffold $rel 'resolves outside the project root' }
  if (Test-Path -LiteralPath $full) { [void]$script:skipped.Add($rel + '/'); return }
  try { New-Item -ItemType Directory -Force -Path $full -ErrorAction Stop | Out-Null }
  catch { Fail-Scaffold $rel $_.Exception.Message }
  [void]$script:created.Add($rel + '/')
}
function Ensure-File([string]$rel, [string]$content) {
  $full = Join-Path $script:root ($rel -replace '/', '\')
  if (-not (Test-PhanesContained $script:root $full)) { Fail-Scaffold $rel 'resolves outside the project root' }
  if (Test-Path -LiteralPath $full) { [void]$script:skipped.Add($rel); return }
  try { [System.IO.File]::WriteAllText((Join-Path $script:root ($rel -replace '/', '\')), $content, $UTF8_NO_BOM) }
  catch { Fail-Scaffold $rel $_.Exception.Message }
  [void]$script:created.Add($rel)
}

# Step 1: documentation tree. The dated architecture snapshot folder is Phase 5's job (its
# content is judgment); scaffold creates only the stable skeleton.
foreach ($d in @("$docRoot", "$docRoot/archive", "$docRoot/archive/projects", "$docRoot/session-summaries", "$docRoot/plans", "$docRoot/plans/implementation", "$docRoot/plans/fixes", "$docRoot/architecture", "$docRoot/registry")) { Ensure-Dir $d }
Ensure-File "$docRoot/session-summaries/README.md" $docsTpl['session-summaries-readme']
Ensure-File "$docRoot/architecture/README.md" $docsTpl['architecture-readme']
Ensure-File "$docRoot/registry/README.md" $docsTpl['registry-readme']

# Step 1b: tests tree. Only the literal `tests/` layout is mechanical. When a DIFFERENT
# conventional test directory already exists at the root, the merge is framework judgment
# (phanes.md Step 1b) and stays with the session: report and leave it alone.
$conventional = @('test', '__tests__', 'spec')
$existingConv = $null
foreach ($c in $conventional) {
  if (Test-Path -LiteralPath (Join-Path $root $c)) { $existingConv = $c; break }
}
if ($null -ne $existingConv -and -not (Test-Path -LiteralPath (Join-Path $root 'tests'))) {
  Write-Output ("TESTTREE-EXISTS $existingConv/ (conventional test tree present; the Step 1b merge stays with the session, nothing created)")
} else {
  foreach ($d in @('tests', 'tests/unit', 'tests/integration', 'tests/e2e', 'tests/fixtures', 'tests/helpers')) { Ensure-Dir $d }
  Ensure-File 'tests/README.md' $testsTpl['tests-readme']
}

foreach ($c in $created) { Write-Output ("CREATED $c") }
foreach ($s in $skipped) { Write-Output ("EXISTS $s") }
Write-Output ("scaffold: created $($created.Count), left untouched $($skipped.Count)")
exit 0
