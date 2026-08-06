# phanes-template v3.4.0 manifest-write
# Recomputes sha256 provenance for every installed script (.phanes/scripts/) and prompt
# template (.claude/template/) and rewrites .phanes/manifest.json (schema: phanes.md Phase 5).
# Blessing the CURRENT disk state is this script's one job: drift detection against the
# recorded state belongs to `update-preflight`; deciding whether drift was legitimate belongs
# to the session. Entries of every other class (agents, workflows, commands, config-blocks,
# doc-scaffolds) are preserved verbatim; each recomputed entry keeps its recorded `customized`
# flag (new entries: false). NOT advisory: exit 0 on success; exit 1 (nothing written) when
# the project, config, or an existing manifest cannot be read safely.
$ErrorActionPreference = 'Stop'

$UTF8_NO_BOM = New-Object System.Text.UTF8Encoding($false)
$DROP_CAP = 20   # MW-7: cap on the stale-entry and collision lists printed to stdout

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

$root = Find-PhanesRoot
if (-not $root) { [Console]::Error.WriteLine('manifest-write: .phanes/config.json not found from this directory'); exit 1 }

# Config: phanesVersion and projectSlug feed the manifest header. A malformed config is a
# refusal (exit 1): this script writes the provenance record other tooling trusts, and
# writing it while the project's own config is unreadable would bless an unknown state.
# MW-5 repair: the draft's try/catch never fired on a 0-byte, whitespace-only, literal-null,
# bare-array or bare-string config, so a manifest was written with null phanesVersion and null
# projectSlug at exit 0, blessing a state the script could not read. RequireMember is not used
# here because a config legitimately may not carry either key; requiring a parsed OBJECT is the
# gate, and that alone rejects all five shapes.
$cfgRead = Read-PhanesJsonFile (Join-Path $root '.phanes\config.json')
if ($cfgRead.Status -cne 'ok') {
  [Console]::Error.WriteLine("manifest-write: .phanes/config.json is $($cfgRead.Status) ($($cfgRead.Reason)); nothing written, repair the config first")
  exit 1
}
$cfg = $cfgRead.Value

# MW-1 repair, the CRITICAL one. Rewriting over a manifest we cannot parse destroys the
# agent-class and workflow-class provenance entries only the session can reconstruct, so the
# draft refused on a parse failure. But the refusal never fired for FIVE corrupt shapes, by two
# distinct mechanisms:
#   1. Get-Content -Raw on a 0-byte file emits $null, so the pipeline never invoked
#      ConvertFrom-Json and the catch never ran. A 0-byte file is the canonical interrupted-
#      write corruption, i.e. the likeliest real case and precisely the one that got through.
#   2. Whitespace-only, literal null, bare-array and bare-string contents PARSE cleanly, so the
#      catch never ran either; the value simply had no .artifacts member and the loop below
#      silently iterated nothing.
# Either way the manifest was rewritten from scratch at exit 0 and the preserved classes were
# gone. Requiring a parsed OBJECT carrying an ARTIFACTS ARRAY closes all five with one guard.
$manifestPath = Join-Path $root '.phanes\manifest.json'
$existing = $null
$mfRead = Read-PhanesJsonFile $manifestPath 'artifacts'
if ($mfRead.Status -ceq 'ok') { $existing = $mfRead.Value }
elseif ($mfRead.Status -cne 'absent') {
  [Console]::Error.WriteLine("manifest-write: existing .phanes/manifest.json is $($mfRead.Status) ($($mfRead.Reason)); nothing written. Repair or deliberately delete it, then re-run")
  exit 1
}
if ($null -ne $existing -and -not ($existing.artifacts -is [System.Collections.IEnumerable]) ) {
  [Console]::Error.WriteLine('manifest-write: existing .phanes/manifest.json has a non-array artifacts member; nothing written')
  exit 1
}

# phanesVersion: config first, then templates.version, then the existing manifest, then null
# (a Phase 2.5 install runs before Phase 5 stamps phanesVersion; null is honest there).
$phanesVersion = $null
if ($cfg.phanesVersion -is [string]) { $phanesVersion = $cfg.phanesVersion }
elseif ($cfg.templates -and ($cfg.templates.version -is [string])) { $phanesVersion = $cfg.templates.version }
elseif ($existing -and ($existing.phanesVersion -is [string])) { $phanesVersion = $existing.phanesVersion }
$projectSlug = $null
if ($cfg.projectSlug -is [string]) { $projectSlug = $cfg.projectSlug }
elseif ($existing -and ($existing.projectSlug -is [string])) { $projectSlug = $existing.projectSlug }

# Recorded state: preserved classes pass through verbatim; recomputed-scope paths contribute
# their recorded class and customized flag.
function Normalize-Rel([string]$p) { return ($p -replace '\\', '/') }

# MW-6 and MW-10 are resolved together, because they pull in opposite directions and N4 flagged
# that fixing them separately would silently undo one of them. The boundary rule in Global
# Constraints decides it: this table maps a recorded path to the FILE ON DISK it describes, and
# "is this recorded path the same file as this disk path" is a filesystem identity question on
# NTFS, so the lookup is OrdinalIgnoreCase (MW-6: an Ordinal prefix test here created a
# permanent phantom manifest entry and dropped `customized: true`, because the recorded entry
# never matched the file it described).
#
# That alone would reintroduce MW-10, where two recorded entries differing only in case collapse
# into one and the loser is neither preserved nor reported as dropped. So collisions are
# DETECTED and reported instead of being made impossible: an OrdinalIgnoreCase table plus an
# explicit ContainsKey check before each insert. Nothing vanishes silently, and the disk lookup
# still behaves the way NTFS does.
$recordedByPath = New-Object System.Collections.Hashtable ([System.StringComparer]::OrdinalIgnoreCase)
$pathCollisions = New-Object System.Collections.ArrayList
$preserved = New-Object System.Collections.ArrayList
if ($existing -and $existing.artifacts) {
  foreach ($a in @($existing.artifacts)) {
    if (-not ($a.path -is [string])) { continue }
    $np = Normalize-Rel $a.path
    # MW-6: the scan-scope prefix test is a path check, and Global Constraints list it in the
    # exhaustive OrdinalIgnoreCase exceptions for exactly this reason. Under Ordinal, a recorded
    # `.PHANES/scripts/x.ps1` fell out of the recomputed scope, was filed as a preserved entry,
    # and then the same file was recomputed and added again: a permanent duplicate, with the
    # recorded `customized: true` dropped from the live copy.
    if ($np.StartsWith('.phanes/scripts/', [System.StringComparison]::OrdinalIgnoreCase) -or $np.StartsWith('.claude/template/', [System.StringComparison]::OrdinalIgnoreCase)) {
      if ($recordedByPath.ContainsKey($np)) { [void]$pathCollisions.Add($np) }
      $recordedByPath[$np] = $a
    } else {
      [void]$preserved.Add($a)
    }
  }
}

# Recompute: every file under .phanes/scripts/ and .claude/template/.
$artifacts = New-Object System.Collections.ArrayList
$removed = New-Object System.Collections.ArrayList
$seen = @{}
$scanRoots = @(
  @{ dir = (Join-Path $root '.phanes\scripts'); prefix = '.phanes/scripts/'; class = 'script' },
  @{ dir = (Join-Path $root '.claude\template'); prefix = '.claude/template/'; class = 'template' }
)
$counts = @{ script = 0; hook = 0; template = 0 }
# Found during W3.2 execution, 2026-08-05: the Interfaces block already required this and the
# body never did it. Both scanned trees are FLAT by contract (CHECKLIST item 4 installs scripts
# flat, and templates are flat for the same reason), and the enumeration below is deliberately
# non-recursive to match. The defect was not the flatness, it was the silence: a nested file was
# omitted from the manifest with no trace anywhere, so a file that IS installed carried no
# provenance and nothing ever said so. It is named here rather than turned into a refusal,
# because a new exit-1 condition would make a project carrying one stray nested file unable to
# record provenance until a human intervened, which is the fails-forever class N1 just repaired.
$nestedFound = New-Object System.Collections.ArrayList
foreach ($sr in $scanRoots) {
  if (-not (Test-Path -LiteralPath $sr.dir)) { continue }
  $srFull = $sr.dir
  try { $srFull = (Get-Item -LiteralPath $sr.dir -Force).FullName } catch { }
  try {
    foreach ($nf in @(Get-ChildItem -LiteralPath $sr.dir -File -Recurse -ErrorAction Stop)) {
      # A path compared against a path is the filesystem identity question, so OrdinalIgnoreCase
      # governs here, per the name-versus-path rule in Global Constraints.
      if (-not [string]::Equals($nf.DirectoryName, $srFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        [void]$nestedFound.Add($sr.prefix + ($nf.FullName.Substring($srFull.Length + 1).Replace('\', '/')))
      }
    }
  } catch { }
  # MW-9 repair: this sat outside any try/catch, so an unreadable scan directory produced a raw
  # PowerShell stack trace instead of a `manifest-write:` message. It degraded safely (exit 1,
  # manifest untouched), so the fix is about the contract in Global Constraints that every
  # failure message names the failed item, not about the outcome.
  $files = @()
  try { $files = @(Get-ChildItem -LiteralPath $sr.dir -File -ErrorAction Stop) }
  catch { [Console]::Error.WriteLine("manifest-write: cannot enumerate $($sr.dir) ($($_.Exception.Message)); nothing written"); exit 1 }
  $names = @($files | ForEach-Object { $_.Name })
  [Array]::Sort($names, [System.StringComparer]::Ordinal)
  foreach ($n in $names) {
    $rel = $sr.prefix + $n
    $full = Join-Path $sr.dir $n
    try { $sha = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant() }
    catch { [Console]::Error.WriteLine("manifest-write: cannot hash $rel; nothing written"); exit 1 }
    $class = $sr.class
    $customized = $false
    # W3.4: templateSha256 is the hash of the TEMPLATE the file was installed from, which is a
    # different question from sha256, the hash of the file ON DISK. For an uncustomized file the
    # two are equal; for a customized one they diverge, and templateSha256 is the fingerprint of
    # the template the user customized AWAY FROM. This script cannot know it (it has no network
    # and no staging directory), so it PRESERVES a recorded value and never invents one. The
    # value is sourced by install-templates, which holds the staged template at the moment it
    # decides to preserve. A pre-v3.4 manifest carries none and stays UNKNOWN forever: the
    # template a user customized away from is unrecoverable after the fact, and a guessed value
    # would produce a false all-clear, which is worse than an admitted unknown.
    $templateSha = $null
    if ($recordedByPath.ContainsKey($rel)) {
      $rec = $recordedByPath[$rel]
      if ($rec.class -is [string]) { $class = $rec.class }
      if ($rec.customized -is [bool]) { $customized = $rec.customized }
      if ($rec.templateSha256 -is [string]) { $templateSha = $rec.templateSha256 }
    } elseif ($sr.class -ceq 'script' -and $n.StartsWith('hook-', [System.StringComparison]::Ordinal)) {
      $class = 'hook'
    }
    # An UNCUSTOMIZED file is byte-identical to the template it came from, so the disk hash IS
    # the template hash and recording it is an observation, not a guess. This is the migration
    # path for pre-v3.4 manifests: uncustomized entries populate on the first v3.4 run,
    # customized ones stay unknown.
    if ($null -eq $templateSha -and -not $customized) { $templateSha = $sha }
    if ($counts.ContainsKey($class)) { $counts[$class]++ }
    $seen[$rel] = $true
    [void]$artifacts.Add([ordered]@{ path = $rel; class = $class; sha256 = $sha; templateSha256 = $templateSha; customized = $customized })
  }
}
foreach ($rel in @($recordedByPath.Keys)) {
  if (-not $seen.ContainsKey($rel)) { [void]$removed.Add($rel) }
}
$removedArr = $removed.ToArray(); [Array]::Sort($removedArr, [System.StringComparer]::Ordinal)

foreach ($a in $preserved) { [void]$artifacts.Add($a) }

$manifest = [ordered]@{
  manifestVersion = 1
  phanesVersion = $phanesVersion
  # MW-4 repair: .ToString(<format>) is the CULTURE-SENSITIVE method form (unlike the [string]
  # cast, which PowerShell performs with the invariant culture). Under fi-FI and sv-SE the time
  # separator is a period, so this emitted `2026-08-05T11.32.34+02:00`: parseable JSON, but not
  # ISO 8601, and it round-trips through no date parser. The invariant culture is passed
  # explicitly rather than relied upon.
  stampedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK', [System.Globalization.CultureInfo]::InvariantCulture)
  projectSlug = $projectSlug
  artifacts = @($artifacts)
}
try {
  [System.IO.File]::WriteAllText($manifestPath, ((ConvertTo-NodeJson $manifest 0) + "`n"), $UTF8_NO_BOM)
} catch {
  [Console]::Error.WriteLine("manifest-write: cannot write $manifestPath ($($_.Exception.Message))")
  exit 1
}
$msg = "manifest-write: recorded $($artifacts.Count) artifacts ($($counts['script']) scripts, $($counts['hook']) hooks, $($counts['template']) templates, $($preserved.Count) preserved other-class)"
# MW-7 repair: this list was uncapped and unflagged, and 300 stale entries produced 9,122
# characters on stdout, straight into the calling session's context. Global Constraints require
# a cap with the exact count and a truncation flag; the count was already here, the cap and the
# flag were not.
if ($removedArr.Count -gt 0) {
  $shown = @($removedArr | Select-Object -First $DROP_CAP)
  $msg += "; dropped $($removedArr.Count) stale entries: $($shown -join ', ')"
  if ($removedArr.Count -gt $DROP_CAP) { $msg += " [list truncated, $($removedArr.Count - $DROP_CAP) more]" }
}
if ($pathCollisions.Count -gt 0) {
  $msg += "; WARNING: $($pathCollisions.Count) recorded path(s) differ only by case and were merged: $((@($pathCollisions | Select-Object -First $DROP_CAP)) -join ', ')"
}
if ($nestedFound.Count -gt 0) {
  $nestedArr = $nestedFound.ToArray(); [Array]::Sort($nestedArr, [System.StringComparer]::Ordinal)
  $shownN = @($nestedArr | Select-Object -First $DROP_CAP)
  [Console]::Error.WriteLine("manifest-write: $($nestedArr.Count) nested file(s) were NOT recorded; both scanned trees are flat by contract: $($shownN -join ', ')")
  $msg += "; NOT recorded, nested: $($nestedArr.Count)"
}
Write-Output $msg
exit 0
