# phanes-template v3.4.0 install-templates
# Mechanizes CHECKLIST items 1-4, 6-9, and 11 for the Windows platform: fetches the manifest's
# windows script set plus the every-platform files (cli.js, prompt templates) into a staging
# directory, sanity-checks every stamp THERE, and only then installs (scripts flat into
# .phanes/scripts/, prompts to their installPath), merges the settings fragment preserving
# existing hooks, verifies the merge, smoke-runs the cli chain, writes the config templates
# block, and records provenance by invoking the just-installed manifest-write. Stage-then-
# commit: every fetch or stamp failure aborts BEFORE anything touches the project. Preserve
# rules: a manifest entry with customized:true, and any prompt template whose on-disk sha no
# longer matches its manifest record, are never overwritten. NOT advisory: exit 0 success,
# exit 1 failure with the failed item named (the session then falls back to spec-generation
# exactly as CHECKLIST item 3 prescribes). Optional: --source <baseUrlOrDir> overrides the
# pinned raw URL (testing, mirrors, air-gapped installs).
$ErrorActionPreference = 'Stop'

$UTF8_NO_BOM = New-Object System.Text.UTF8Encoding($false)
$SMOKE_TIMEOUT_MS = 60000   # N5: explicit bound on each smoke-run child process

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

function Fail([string]$msg) { [Console]::Error.WriteLine("install-templates: FAILED: $msg"); exit 1 }

# --- arguments
$source = $null
for ($i = 0; $i -lt $args.Count; $i++) {
  if ([string]$args[$i] -ceq '--source') {
    if ($i + 1 -ge $args.Count) { Fail 'usage: --source requires a value (base URL or directory)' }
    $source = [string]$args[$i + 1]; $i++
  } else { Fail ("unknown argument '$($args[$i])'") }
}

# --- own version from this file's stamp (the CHECKLIST item 3 comparison substrate)
$ownVersion = $null
try {
  $selfHead = Get-Content -LiteralPath $PSCommandPath -TotalCount 2 -Encoding utf8
  $m = [regex]::Match(($selfHead -join "`n"), 'phanes-template v(\d+\.\d+\.\d+)')
  if ($m.Success) { $ownVersion = $m.Groups[1].Value }
} catch { }
if ($null -eq $ownVersion) { Fail 'cannot read own version stamp' }
if ($null -eq $source) { $source = "https://raw.githubusercontent.com/Aloim/phanes/v$ownVersion/templates" }
$sourceIsDir = Test-Path -LiteralPath $source -PathType Container

$root = Find-PhanesRoot
if (-not $root) { Fail '.phanes/config.json not found from this directory (CHECKLIST item 6: config is written before the first script runs)' }
$cfg = $null
try {
  $cfg = Get-Content -LiteralPath (Join-Path $root '.phanes\config.json') -Raw -Encoding utf8 | ConvertFrom-Json
} catch {
  Fail '.phanes/config.json is malformed; repair it before installing (item 6)'
}

# Existing provenance (preserve substrate). Absent = fresh install, no records. Malformed =
# refuse: without readable records the customized-file preserve rule cannot be honored, and
# overwriting blind is exactly the destroy reflex this library forbids.
$manifestPath = Join-Path $root '.phanes\manifest.json'
# C3 repair. The two halves of the preserve rule disagreed about case: preservation was DECIDED
# by ContainsKey on a bare @{} (OrdinalIgnoreCase) and flagged back with -ccontains
# (case-sensitive). So a file preserved through a case-differing record was never flagged, and
# `manifest-write` then blessed its current sha as canonical, which means THE NEXT RUN
# OVERWRITES IT, while this run printed that it had preserved it. Silent loss of user
# customization, announced as a preservation. Both halves are now OrdinalIgnoreCase, which is
# the NTFS path exception applied consistently: on this filesystem those two spellings are the
# same file, so both halves must agree that they are.
$recordByPath = New-Object System.Collections.Hashtable ([System.StringComparer]::OrdinalIgnoreCase)
if (Test-Path -LiteralPath $manifestPath) {
  try {
    $prov = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    foreach ($a in @($prov.artifacts)) { if ($a.path -is [string]) { $recordByPath[($a.path -replace '\\', '/')] = $a } }
  } catch {
    Fail '.phanes/manifest.json exists but cannot be parsed; the customized-file preserve rule cannot be honored, nothing installed. Repair or deliberately delete it first'
  }
}

# --- staging fetch (nothing below touches the project until every file passed its check)
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
$staging = Join-Path $env:TEMP ("phanes-install-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $staging | Out-Null
function Fetch-One([string]$rel) {
  $dest = Join-Path $script:staging ($rel -replace '/', '\')
  # C2, the staging half: `rel` is also manifest-sourced, so a traversing rel escapes the
  # staging directory exactly as a traversing installPath escaped the project. Refusing here
  # means a hostile or damaged manifest cannot write anywhere on the way in either.
  if ([System.IO.Path]::IsPathRooted($rel) -or -not (Test-PhanesContained $script:staging $dest)) {
    [Console]::Error.WriteLine("install-templates: manifest path '$rel' escapes the staging directory; refusing")
    return $false
  }
  $destDir = [System.IO.Path]::GetDirectoryName($dest)
  New-Item -ItemType Directory -Force -Path $destDir | Out-Null
  if ($script:sourceIsDir) {
    $src = Join-Path $script:source ($rel -replace '/', '\')
    if (-not (Test-Path -LiteralPath $src)) { return $false }
    Copy-Item -LiteralPath $src -Destination $dest -Force
    return $true
  }
  try {
    Invoke-WebRequest -Uri ($script:source.TrimEnd('/') + '/' + $rel) -OutFile $dest -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
    return $true
  } catch { return $false }
}

if (-not (Fetch-One 'MANIFEST.json')) { Fail "cannot fetch MANIFEST.json from $source" }
$man = $null
try { $man = Get-Content -LiteralPath (Join-Path $staging 'MANIFEST.json') -Raw -Encoding utf8 | ConvertFrom-Json } catch { Fail 'fetched MANIFEST.json does not parse (a 404 body or HTML error page must never be installed)' }
if (-not ($man.version -is [string]) -or $man.version -cne $ownVersion) { Fail "manifest version '$($man.version)' does not match this script's stamp version '$ownVersion' (item 3); fall back to spec-generation" }

# item 1: platform detected; only the windows variant set plus every-platform files fetched.
$plan = New-Object System.Collections.ArrayList   # entries: rel, name, kind(script|prompt), installPath
foreach ($s in @($man.scripts)) {
  $files = @($s.windows | Where-Object { $_ -is [string] })
  if ($files.Count -eq 0) { Write-Output ("SKIPPED (no windows variant): $($s.name)"); continue }
  foreach ($rel in $files) {
    [void]$plan.Add(@{ rel = [string]$rel; name = [string]$s.name; kind = 'script'; installPath = ('.phanes/scripts/' + [System.IO.Path]::GetFileName([string]$rel)) })
  }
}
foreach ($p in @($man.promptTemplates)) {
  [void]$plan.Add(@{ rel = [string]$p.file; name = [string]$p.name; kind = 'prompt'; installPath = ([string]$p.installPath -replace '\\', '/') })
}
$fragRel = $null
if ($man.settingsFragments -and ($man.settingsFragments.windows -is [string])) { $fragRel = [string]$man.settingsFragments.windows }
if ($null -eq $fragRel) { Fail 'manifest carries no windows settings fragment' }

foreach ($e in $plan) { if (-not (Fetch-One $e.rel)) { Fail "cannot fetch $($e.rel) from $source; nothing installed" } }
if (-not (Fetch-One $fragRel)) { Fail "cannot fetch $fragRel from $source; nothing installed" }

# item 2: stamp sanity per staged file, BEFORE any install. The fragment is pure JSON (it
# cannot carry a comment stamp); its sanity check is a parse plus a hooks key.
foreach ($e in $plan) {
  $staged = Join-Path $staging ($e.rel -replace '/', '\')
  $head = @()
  try { $head = @(Get-Content -LiteralPath $staged -TotalCount 2 -Encoding utf8) } catch { }
  $want = "phanes-template v$ownVersion $($e.name)"
  $ok = $false
  foreach ($ln in $head) { if (([string]$ln).IndexOf($want, [System.StringComparison]::Ordinal) -ge 0) { $ok = $true; break } }
  if (-not $ok) { Fail "stamp check failed for $($e.rel) (expected '$want' within the first two lines); nothing installed" }
}
$frag = $null
try {
  $frag = Get-Content -LiteralPath (Join-Path $staging ($fragRel -replace '/', '\')) -Raw -Encoding utf8 | ConvertFrom-Json
  if (-not $frag.hooks) { throw 'no hooks key' }
} catch { Fail "fetched settings fragment $fragRel is not a hooks JSON; nothing installed" }

# --- install (item 4: flat into .phanes/scripts/, extension kept; prompts to installPath).
# C2 repair, and the severity comes from where the string originates. `installPath` is taken
# verbatim from the FETCHED manifest, and the default source is a remote raw URL, so this is a
# path traversal whose payload is REMOTE CONTENT. `"installPath": "../ESCAPED-OUTSIDE-ROOT.md"`
# wrote above the project root and the run printed `install-templates: OK` and exited 0. An
# absolute installPath was caught only by accident of a .NET Join-Path artifact, with a message
# that explained nothing. This repeats the class SS00025's W1.3 item b already fixed once.
#
# The gate runs in the PRE-COPY verification pass, so a rejected plan lands in state (A),
# untouched, rather than part-installed. The staging destination is validated on the same
# principle in Fetch-One: a traversing `rel` must not escape the staging directory either.
foreach ($e in $plan) {
  if ([System.IO.Path]::IsPathRooted($e.installPath)) {
    Fail "manifest installPath '$($e.installPath)' is absolute; installPath must be relative to the project root. Nothing installed"
  }
  if (-not (Test-PhanesContained $root (Join-Path $root ($e.installPath -replace '/', '\')))) {
    Fail "manifest installPath '$($e.installPath)' resolves outside the project root; nothing installed"
  }
}

# Only now, with every installPath validated, is the project touched at all. This ordering is
# load-bearing for the state (A) guarantee: the directory creation below used to run BEFORE the
# gate, so a refused hostile manifest still left `.phanes/scripts/` behind. An empty directory
# is not damage, but "untouched" has to mean untouched or the contract is only approximately
# true, and approximately-true contracts are what this review kept finding.
New-Item -ItemType Directory -Force -Path (Join-Path $root '.phanes\scripts') | Out-Null
$installed = New-Object System.Collections.ArrayList
$preserved = New-Object System.Collections.ArrayList
$staleCustomizations = New-Object System.Collections.ArrayList   # W3.4
foreach ($e in $plan) {
  $target = Join-Path $root ($e.installPath -replace '/', '\')
  $targetDir = [System.IO.Path]::GetDirectoryName($target)
  if (Test-Path -LiteralPath $target) {
    $rec = $null
    if ($recordByPath.ContainsKey($e.installPath)) { $rec = $recordByPath[$e.installPath] }
    if ($null -ne $rec) {
      $keep = ($rec.customized -is [bool] -and $rec.customized)
      if (-not $keep -and $e.kind -ceq 'prompt' -and ($rec.sha256 -is [string])) {
        try { $disk = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash } catch { $disk = '' }
        if (-not [string]::Equals($disk, $rec.sha256, [System.StringComparison]::OrdinalIgnoreCase)) { $keep = $true }
      }
      if ($keep) {
        [void]$preserved.Add($e.installPath)
        Write-Output ("PRESERVED (user-customized): $($e.installPath)")
        # W3.4: this is the ONE place in the system that can honestly answer "has the template
        # moved on since you customized this", because it is holding the staged replacement
        # template right now. update-preflight runs offline and must never claim it. The
        # preserve rule is NOT changed by any of this: the file is preserved either way, and
        # the user is simply told their reason to customize may have expired.
        $stagedSha = $null
        try { $stagedSha = (Get-FileHash -LiteralPath (Join-Path $staging ($e.rel -replace '/', '\')) -Algorithm SHA256).Hash.ToLowerInvariant() } catch { $stagedSha = $null }
        $recTpl = $null
        if ($rec.templateSha256 -is [string]) { $recTpl = ([string]$rec.templateSha256).ToLowerInvariant() }
        if ($null -ne $stagedSha -and $null -ne $recTpl) {
          if (-not [string]::Equals($stagedSha, $recTpl, [System.StringComparison]::OrdinalIgnoreCase)) {
            $shortRec = $recTpl.Substring(0, [Math]::Min(8, $recTpl.Length))
            $shortNew = $stagedSha.Substring(0, [Math]::Min(8, $stagedSha.Length))
            Write-Output ("CUSTOMIZATION STALE: $($e.installPath) (customized from template $shortRec, template is now $shortNew; your edit is preserved, review whether it is still needed)")
            [void]$staleCustomizations.Add($e.installPath)
          }
        }
        continue
      }
    }
  }
  try {
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    Copy-Item -LiteralPath (Join-Path $staging ($e.rel -replace '/', '\')) -Destination $target -Force
  } catch {
    Fail "copy failed for $($e.installPath) ($($_.Exception.Message)); installed so far: $($installed -join ', ')"
  }
  [void]$installed.Add($e.installPath)
}
Write-Output ("installed: $($installed.Count) files, preserved: $($preserved.Count)")

# --- item 8: merge the settings fragment into .claude/settings.json, preserving existing
# --- hooks; a malformed existing settings file is a refusal, never a clobber.
$settingsPath = Join-Path $root '.claude\settings.json'
$settings = $null
if (Test-Path -LiteralPath $settingsPath) {
  try { $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding utf8 | ConvertFrom-Json } catch { Fail '.claude/settings.json exists but cannot be parsed; merge refused so user settings are never clobbered. Repair it, then re-run' }
} else {
  New-Item -ItemType Directory -Force -Path (Join-Path $root '.claude') | Out-Null
  $settings = [pscustomobject]@{}
}
if (-not $settings.hooks) { $settings | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) -Force }
$mergedNew = 0; $mergedKept = 0
foreach ($evProp in @($frag.hooks.PSObject.Properties | ForEach-Object { $_ })) {
  $ev = $evProp.Name
  if (-not $settings.hooks.$ev) { $settings.hooks | Add-Member -NotePropertyName $ev -NotePropertyValue @() -Force }
  $existingCmds = @()
  foreach ($grp in @($settings.hooks.$ev)) { foreach ($h in @($grp.hooks)) { if ($h.command -is [string]) { $existingCmds += $h.command } } }
  foreach ($grp in @($evProp.Value)) {
    $newCmds = @()
    foreach ($h in @($grp.hooks)) { if ($h.command -is [string]) { $newCmds += $h.command } }
    $allPresent = $true
    foreach ($c in $newCmds) { if ($existingCmds -cnotcontains $c) { $allPresent = $false; break } }
    if ($allPresent -and $newCmds.Count -gt 0) { $mergedKept++; continue }
    $settings.hooks.$ev = @($settings.hooks.$ev) + $grp
    $mergedNew++
  }
}
try { [System.IO.File]::WriteAllText($settingsPath, ((ConvertTo-NodeJson $settings 0) + "`n"), $UTF8_NO_BOM) } catch { Fail "cannot write .claude/settings.json ($($_.Exception.Message))" }
Write-Output ("settings: merged $mergedNew hook group(s), $mergedKept already present")

# Read-back verification (the Step 4b path-discipline check, mechanical): every Phanes hook
# command must contain .phanes/scripts/ and carry no drive letter and no leading slash.
#
# N1 repair, the highest-value single fix in this task. A PRE-EXISTING legacy hook carrying an
# absolute path (the form Phanes installed before the path-discipline rule existed) made this
# check Fail on a condition THIS RUN DID NOT CREATE AND COULD NOT CLEAR. Result: exit 1, state
# (B), and every subsequent run repeated it identically. The only escape was a hand-edit of
# settings.json, which is precisely the manual step mechanization exists to remove, and it is
# the `:777` update-run hook-repair duty's own target.
#
# So a legacy Phanes hook is REPAIRED rather than refused: the absolute prefix is rewritten to
# the canonical relative form, the change is reported, and the file is written back. Two fences
# keep this from becoming a destroy reflex. First, only commands already identified as Phanes
# hooks (they contain `.phanes/scripts/`) are touched; a non-Phanes hook is never rewritten,
# whatever it looks like. Second, if the rewrite does not produce a compliant command, the run
# still fails with the original message rather than writing something it cannot vouch for.
$verifyRead = Read-PhanesJsonFile $settingsPath
if ($verifyRead.Status -cne 'ok') { Fail ".claude/settings.json is $($verifyRead.Status) after the merge ($($verifyRead.Reason))" }
$verify = $verifyRead.Value
$repairedHooks = New-Object System.Collections.ArrayList
foreach ($evProp in @($verify.hooks.PSObject.Properties | ForEach-Object { $_ })) {
  foreach ($grp in @($evProp.Value)) {
    foreach ($h in @($grp.hooks)) {
      if (-not ($h.command -is [string])) { continue }
      $c = [string]$h.command
      if ($c.IndexOf('.phanes/scripts/', [System.StringComparison]::Ordinal) -lt 0) { continue }  # not a Phanes hook
      $bad = ($c -match '(?i)[a-z]:[\\/]') -or ($c -match '(^|\s)/')
      if (-not $bad) { continue }
      # Rewrite everything up to and including the drive-letter or leading-slash prefix so the
      # command starts at `.phanes/scripts/`, keeping the invocation words before it intact.
      $idx = $c.IndexOf('.phanes/scripts/', [System.StringComparison]::Ordinal)
      $head = $c.Substring(0, $idx)
      $tail = $c.Substring($idx)
      $head = [regex]::Replace($head, '(?i)([a-z]:[\\/]|(?<=^|\s)/)\S*$', '')
      $fixed = ($head + $tail)
      if (($fixed -match '(?i)[a-z]:[\\/]') -or ($fixed -match '(^|\s)/')) {
        Fail "hook command carries a non-relative path that could not be repaired (path discipline): $c"
      }
      $h.command = $fixed
      [void]$repairedHooks.Add($c)
    }
  }
}
if ($repairedHooks.Count -gt 0) {
  try {
    [System.IO.File]::WriteAllText($settingsPath, ((ConvertTo-NodeJson $verify 0) + "`n"), $UTF8_NO_BOM)
  } catch {
    Fail "could not write the repaired hook path(s) back to .claude/settings.json ($($_.Exception.Message))"
  }
  Write-Output ("settings: repaired $($repairedHooks.Count) legacy absolute-path hook command(s) to the relative form")
  foreach ($rc in $repairedHooks) { Write-Output ("  was: $rc") }
}
Write-Output 'settings: read-back verification passed (relative .phanes/scripts/ commands only)'

# --- item 7: smoke run through the cross-shell entry. Native stderr is NOT redirected here:
# --- under EAP-Stop a redirected native stderr line becomes a terminating ErrorRecord (the
# --- loc-check class), which would turn a benign warning into a false smoke failure.
$smokeFail = $null
Push-Location $root
try {
  # N5: the Global Constraint requires an explicit timeout on every child process, and these two
  # spawns carried none. A hung `node` would hang the install with no bound. Start-Process with
  # -PassThru plus WaitForExit(ms) gives a bound without a detached child and without Start-Job
  # (a second powershell process, which the termination discipline also discourages).
  function Invoke-Smoke([string]$sub) {
    $p = Start-Process -FilePath 'node' -ArgumentList @('.phanes/scripts/cli.js', $sub) -NoNewWindow -PassThru
    # Touching .Handle caches the process handle in the .NET object. Without it, ExitCode comes
    # back EMPTY once the process has exited, because PowerShell has already released the
    # handle, and the failure message then reads "cli.js module-list exited " with no number.
    # Found by running this: the timeout fix introduced the defect the message was meant to
    # report. A smoke failure that cannot say WHAT the exit code was is barely a report at all.
    $null = $p.Handle
    if (-not $p.WaitForExit($script:SMOKE_TIMEOUT_MS)) {
      try { $p.Kill() } catch { }
      return "cli.js $sub did not finish within $([int]($script:SMOKE_TIMEOUT_MS / 1000))s and was terminated"
    }
    if ($p.ExitCode -ne 0) { return "cli.js $sub exited $($p.ExitCode)" }
    return $null
  }
  $smokeFail = Invoke-Smoke 'module-list'
  if ($null -eq $smokeFail) {
    $smokeFail = Invoke-Smoke 'register-check'
  }
} catch {
  $smokeFail = "node unavailable ($($_.Exception.Message))"
} finally {
  Pop-Location
}
if ($null -ne $smokeFail) { Fail "smoke run failed: $smokeFail (scripts are on disk but unverified; no provenance recorded)" }
Write-Output 'smoke: module-list OK, register-check OK'

# --- item 11 provenance: sha256 recording via the just-installed manifest-write (one hashing
# --- implementation, not two).
#
# ORDER CORRECTED 2026-08-05. This block used to run AFTER the config templates block below,
# which quietly falsified the state (B) contract: `templates: {...}` in config is exactly the
# marker a later run reads as "this project has a completed install", so all three
# provenance-failure paths (manifest-write missing, manifest-write nonzero, flag-back failure)
# left that marker on disk with NO manifest beside it. The contract was repaired by moving the
# code to match it, not by weakening the wording to match the code.
$mwPath = Join-Path $root '.phanes\scripts\manifest-write.ps1'
if (-not (Test-Path -LiteralPath $mwPath)) { Fail 'manifest-write.ps1 is not in the installed set; provenance not recorded' }
$mwOut = & $mwPath
if ($LASTEXITCODE -ne 0) { Fail "manifest-write exited $LASTEXITCODE; provenance not recorded" }
Write-Output ("provenance: $mwOut")

# A file this run PRESERVED is durably customized: flag it, or the freshly blessed sha would
# make the next install overwrite it (the preserve signal must not be consumed by recording).
if ($preserved.Count -gt 0) {
  try {
    $prov2 = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    foreach ($a in @($prov2.artifacts)) {
      # C3: matched OrdinalIgnoreCase, the same way preservation was decided above. A
      # case-sensitive test here is what silently dropped the flag.
      $ap = ($a.path -replace '\\', '/')
      $isPreserved = $false
      if ($a.path -is [string]) {
        foreach ($pp in $preserved) { if ([string]::Equals($pp, $ap, [System.StringComparison]::OrdinalIgnoreCase)) { $isPreserved = $true; break } }
      }
      if ($isPreserved) { $a.customized = $true }
      # W3.4: record the template this run WOULD have installed as the fingerprint the user is
      # customized away from, but only when the manifest does not already carry one. Overwriting
      # an existing value would silently re-baseline the customization to the current template
      # and permanently erase the staleness this field exists to detect: the entry would read
      # fresh forever, which is the false all-clear W3.4 was created to prevent.
      if ($isPreserved -and -not ($a.templateSha256 -is [string])) {
        foreach ($pe in $plan) {
          if ([string]::Equals($pe.installPath, $ap, [System.StringComparison]::OrdinalIgnoreCase)) {
            try {
              $tsha = (Get-FileHash -LiteralPath (Join-Path $staging ($pe.rel -replace '/', '\')) -Algorithm SHA256).Hash.ToLowerInvariant()
              if ($a.PSObject.Properties.Match('templateSha256').Count -gt 0) { $a.templateSha256 = $tsha }
              else { $a | Add-Member -NotePropertyName templateSha256 -NotePropertyValue $tsha }
            } catch { }
            break
          }
        }
      }
    }
    [System.IO.File]::WriteAllText($manifestPath, ((ConvertTo-NodeJson $prov2 0) + "`n"), $UTF8_NO_BOM)
    Write-Output ("provenance: marked customized: $($preserved -join ', ')")
  } catch {
    Fail "could not flag preserved files as customized in .phanes/manifest.json ($($_.Exception.Message))"
  }
}
if ($staleCustomizations.Count -gt 0) {
  Write-Output ("customizations possibly stale: $($staleCustomizations.Count) (listed above; the preserve rule is unchanged and every edit was kept)")
}

# --- item 9: config templates block. LAST, after provenance succeeded (see the ordering note
# --- above): this block is the marker a later run reads as a completed install, so it must not
# --- exist on disk unless the install actually completed.
$tplBlock = [pscustomobject]@{ version = $ownVersion; source = 'fetched' }
if ($cfg.PSObject.Properties.Match('templates').Count -gt 0) { $cfg.templates = $tplBlock }
else { $cfg | Add-Member -NotePropertyName templates -NotePropertyValue $tplBlock }
try { [System.IO.File]::WriteAllText((Join-Path $root '.phanes\config.json'), ((ConvertTo-NodeJson $cfg 0) + "`n"), $UTF8_NO_BOM) } catch { Fail "cannot write config templates block ($($_.Exception.Message))" }
Write-Output ('config: templates block written {version: ' + $ownVersion + ', source: fetched}')

try { Remove-Item -LiteralPath $staging -Recurse -Force } catch { }
Write-Output 'install-templates: OK'
exit 0
