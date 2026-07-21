# phanes-template v3.2 new-file
# Creates a file with the required header stamp. The only sanctioned way to create files.
# Usage: phanes new-file <module> <path> "<description of at least five words>"
# <module> may be a source module, tests, or docs. docs targets get the DOC DISCIPLINE header and
# trigger a doc-index regeneration; source and tests targets get the module stamp in the project's
# comment syntax (read from .phanes/config.json). Refuses a missing or too-short description.
$ErrorActionPreference = 'Stop'

function Find-PhanesRoot {
  $d = (Get-Location).Path
  while ($true) {
    if (Test-Path -LiteralPath (Join-Path $d '.phanes\config.json')) { return $d }
    $p = [System.IO.Path]::GetDirectoryName($d)
    if (-not $p -or $p -eq $d) { return $null }
    $d = $p
  }
}

if ($args.Count -lt 3) {
  [Console]::Error.WriteLine('new-file: usage: phanes new-file <module> <path> "<description of at least five words>"')
  exit 1
}
$module = $args[0]
$relPath = $args[1]
$description = ($args[2..($args.Count - 1)] -join ' ').Trim()

$wordCount = ($description -split '\s+' | Where-Object { $_ -ne '' }).Count
if ($wordCount -lt 5) {
  [Console]::Error.WriteLine("new-file: description must be at least five words (got $wordCount). Refused.")
  exit 1
}

$root = Find-PhanesRoot
if (-not $root) { [Console]::Error.WriteLine('new-file: .phanes/config.json not found from this directory'); exit 1 }

$cfg = Get-Content -LiteralPath (Join-Path $root '.phanes\config.json') -Raw -Encoding utf8 | ConvertFrom-Json
$comment = '//'
if ($cfg.commentSyntax) { $comment = $cfg.commentSyntax }

$full = $relPath
if (-not [System.IO.Path]::IsPathRooted($relPath)) { $full = Join-Path $root $relPath }

if (Test-Path -LiteralPath $full) {
  [Console]::Error.WriteLine("new-file: refuses to overwrite existing file: $relPath")
  exit 1
}

$parent = [System.IO.Path]::GetDirectoryName($full)
if ($parent -and -not (Test-Path -LiteralPath $parent)) {
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
}

# Emit non-ASCII via char codes so this script file stays pure ASCII and survives any re-encoding.
$dash = [string][char]0x2014
$bt = [string][char]0x60

if ($module -eq 'docs') {
  $header = @"
<!-- DOC | $description -->
<!-- DOC DISCIPLINE | Soft ceiling: 500 lines. One topic per file; structure under ## headings.
     The DOC line above feeds ${bt}phanes doc-index${bt} $dash keep it accurate; it is this file's line in _index.md.
     If this file exceeds the ceiling: split it into a same-named folder of focused topic files;
     carry both header lines into every part; update every inbound reference in the same change set;
     finish by running ${bt}phanes doc-index${bt}.
     Consumers: NEVER bulk-read documentation folders $dash read _index.md first, load only what you need.
     Audit: ${bt}phanes doc-check${bt}. -->

"@
  Set-Content -LiteralPath $full -Value $header -NoNewline -Encoding utf8
  Write-Output "new-file: created $relPath (docs)"
  # docs targets finish by regenerating the indexes.
  $docIndex = Join-Path $PSScriptRoot 'doc-index.ps1'
  if (Test-Path -LiteralPath $docIndex) { & $docIndex | Out-Null }
} else {
  $l1 = "$comment $module | $description"
  $l2 = "$comment Soft size threshold: 500 LOC. Run ${bt}phanes loc-check${bt} if uncertain."
  Set-Content -LiteralPath $full -Value "$l1`n$l2`n`n" -NoNewline -Encoding utf8
  Write-Output "new-file: created $relPath ($module)"
}
exit 0
