# phaneslight-template v3.7.1 register-check
# Measures the two hot files (root CLAUDE.md and CLAUDE.local.md) in characters and prints a
# status line each: OK (below 35000), SOFT-BREACH (35000 to 40000), CROP-REQUIRED (above 40000).
# Also lists every completed register entry (## checkmark heading) not yet archived
# (COMPLETED-NOT-ARCHIVED, v3.6.1: the marker is legal, the unfinished close-out is the finding),
# reports the standing-blocker section character count separately, and reports the Pinned
# Directives block character count separately (v3.2, the root CLAUDE.md crop-exemption class).
# Advisory: always exits 0.
$ErrorActionPreference = 'Stop'
$SOFT = 35000
$CROP = 40000

function Find-PhanesLightRoot {
  $d = (Get-Location).Path
  while ($true) {
    if (Test-Path -LiteralPath (Join-Path $d '.phaneslight\config.json')) { return $d }
    $p = [System.IO.Path]::GetDirectoryName($d)
    if (-not $p -or $p -eq $d) { return $null }
    $d = $p
  }
}

$root = Find-PhanesLightRoot
if (-not $root) { [Console]::Error.WriteLine('register-check: .phaneslight/config.json not found from this directory'); exit 0 }

# Markers as escaped regex literals. The blocker glyph is a supplementary-plane code point, so it
# must be built with ConvertFromUtf32 (a single [char] cannot hold it).
$MARK_DONE = [regex]::Escape([string][char]0x2705)
$MARK_BLOCK = [regex]::Escape([System.Char]::ConvertFromUtf32(0x1F6D1))

# Count Unicode code points, not UTF-16 code units, so one astral character (an emoji) costs 1
# against the ceiling, matching the POSIX count. .Length counts units and charges an emoji 2;
# each high surrogate marks exactly one pair to subtract.
function Get-CodePointCount([string]$s) {
  if ([string]::IsNullOrEmpty($s)) { return 0 }
  $pairs = 0
  foreach ($c in $s.ToCharArray()) { if ([char]::IsHighSurrogate($c)) { $pairs++ } }
  return $s.Length - $pairs
}

function Status([int]$chars) {
  if ($chars -gt $CROP) { return 'CROP-REQUIRED' }
  if ($chars -ge $SOFT) { return 'SOFT-BREACH' }
  return 'OK'
}

foreach ($name in @('CLAUDE.md', 'CLAUDE.local.md')) {
  $f = Join-Path $root $name
  if (-not (Test-Path -LiteralPath $f)) {
    Write-Output ("{0}: absent" -f $name)
    continue
  }
  # Advisory: an unreadable hot file (denied ACL, a directory in its place) must not abort the run
  # under $ErrorActionPreference = 'Stop'. Say so and skip, rather than reporting a false 0/OK.
  try { $raw = Get-Content -LiteralPath $f -Raw -Encoding utf8 }
  catch {
    [Console]::Error.WriteLine("register-check: cannot read $name, skipping")
    continue
  }
  if ($null -eq $raw) { $raw = '' }
  $chars = Get-CodePointCount $raw
  Write-Output ("{0}: {1} chars [{2}]" -f $name, $chars, (Status $chars))

  try { $lines = Get-Content -LiteralPath $f -Encoding utf8 } catch { $lines = @() }

  # Completed entries not yet archived: headings that begin with '## ' and carry the completed
  # marker. Renamed from COMPLETED-STILL-PRESENT in v3.6.1 and given a reason clause, because the
  # old wording read as "the marker you were told to use is a finding". It is not. The register
  # legend advertises the completed marker as part of its vocabulary, and the marker is CORRECT
  # at the instant it is written; what the register mandate forbids is the entry OUTLIVING it,
  # since marking an entry complete and archiving it are required to be the same change set.
  # The finding is about the missing archival half, so it says so.
  foreach ($ln in $lines) {
    if ($ln -match '^\#\#\s' -and $ln -match $MARK_DONE) {
      Write-Output ("  COMPLETED-NOT-ARCHIVED: {0}" -f $ln.Trim())
      Write-Output "    (the marker is correct; the close-out is unfinished. Archive the entry to documentation/archive/projects/ and delete it here, in one change set.)"
    }
  }

  # Standing-blocker section: from the first heading carrying the blocker marker to the next heading.
  # Unit: code points plus 1 per line for the newline, matching the POSIX section unit.
  $blockerChars = 0
  $inBlock = $false
  foreach ($ln in $lines) {
    $isHeading = $ln -match '^\#{1,6}\s'
    $hasMarker = $ln -match $MARK_BLOCK
    if ($isHeading) {
      if ($hasMarker) { $inBlock = $true; $blockerChars += (Get-CodePointCount $ln) + 1; continue }
      elseif ($inBlock) { $inBlock = $false }
    }
    if ($inBlock) { $blockerChars += (Get-CodePointCount $ln) + 1 }
  }
  if ($blockerChars -gt 0) {
    Write-Output ("  standing-blockers section: {0} chars" -f $blockerChars)
  }

  # Pinned Directives block character count (v3.2): opening marker line to closing marker line, inclusive.
  # Unit: code points plus 1 per line for the newline, matching the POSIX section unit.
  $pinChars = 0
  $inPin = $false
  foreach ($ln in $lines) {
    if ($ln -match '^<!-- PINNED DIRECTIVES') { $inPin = $true }
    if ($inPin) { $pinChars += (Get-CodePointCount $ln) + 1 }
    if ($ln -match '^<!-- /PINNED DIRECTIVES -->') { $inPin = $false }
  }
  if ($pinChars -gt 0) {
    Write-Output ("  pinned-directives block: {0} chars" -f $pinChars)
  }
}
exit 0
