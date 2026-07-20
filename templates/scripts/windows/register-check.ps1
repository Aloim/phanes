# phanes-template v3.0 register-check
# Measures the two hot files (root CLAUDE.md and CLAUDE.local.md) in characters and prints a
# status line each: OK (below 35000), SOFT-BREACH (35000 to 40000), CROP-REQUIRED (above 40000).
# Also lists every completed register entry (## checkmark heading) still present, and reports the
# standing-blocker section character count separately. Advisory: always exits 0.
$ErrorActionPreference = 'Stop'
$SOFT = 35000
$CROP = 40000

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
if (-not $root) { [Console]::Error.WriteLine('register-check: .phanes/config.json not found from this directory'); exit 0 }

# Markers as escaped regex literals. The blocker glyph is a supplementary-plane code point, so it
# must be built with ConvertFromUtf32 (a single [char] cannot hold it).
$MARK_DONE = [regex]::Escape([string][char]0x2705)
$MARK_BLOCK = [regex]::Escape([System.Char]::ConvertFromUtf32(0x1F6D1))

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
  $raw = Get-Content -LiteralPath $f -Raw -Encoding utf8
  if ($null -eq $raw) { $raw = '' }
  $chars = $raw.Length
  Write-Output ("{0}: {1} chars [{2}]" -f $name, $chars, (Status $chars))

  $lines = Get-Content -LiteralPath $f -Encoding utf8

  # Completed entries still present: headings that begin with '## ' and carry the completed marker.
  foreach ($ln in $lines) {
    if ($ln -match '^\#\#\s' -and $ln -match $MARK_DONE) {
      Write-Output ("  COMPLETED-STILL-PRESENT: {0}" -f $ln.Trim())
    }
  }

  # Standing-blocker section: from the first heading carrying the blocker marker to the next heading.
  $blockerChars = 0
  $inBlock = $false
  foreach ($ln in $lines) {
    $isHeading = $ln -match '^\#{1,6}\s'
    $hasMarker = $ln -match $MARK_BLOCK
    if ($isHeading) {
      if ($hasMarker) { $inBlock = $true; $blockerChars += $ln.Length + 1; continue }
      elseif ($inBlock) { $inBlock = $false }
    }
    if ($inBlock) { $blockerChars += $ln.Length + 1 }
  }
  if ($blockerChars -gt 0) {
    Write-Output ("  standing-blockers section: {0} chars" -f $blockerChars)
  }
}
exit 0
