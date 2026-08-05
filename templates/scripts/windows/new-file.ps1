# phanes-template v3.4.0 new-file
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

try {
  $cfg = Get-Content -LiteralPath (Join-Path $root '.phanes\config.json') -Raw -Encoding utf8 | ConvertFrom-Json
} catch {
  # No honest default exists for any of the three values this config supplies: no default
  # commentSyntax (a wrong one is a syntax error in the target language, e.g. "//" in a .py file),
  # no default docRoot (a docs write would land in the wrong tree), and no default module list
  # (an unreadable config would silently switch off the module guard this release ships as a
  # breaking change). new-file is the project's only sanctioned creation path and it writes to
  # disk, so refusing on an unparseable config is strictly safer than guessing at any of the three.
  [Console]::Error.WriteLine('new-file: .phanes/config.json is malformed and could not be parsed. Refused.')
  exit 1
}
$comment = '//'
if ($cfg.commentSyntax) { $comment = $cfg.commentSyntax }
$docRoot = 'documentation'
if ($cfg.docRoot) { $docRoot = $cfg.docRoot }
# A trailing slash in docRoot would otherwise leak into every derived path and message.
$docRoot = ([string]$docRoot).TrimEnd('/', '\')
if (-not $docRoot) { $docRoot = 'documentation' }

$UTF8_NO_BOM = New-Object System.Text.UTF8Encoding($false)
function Write-Utf8([string]$path, [string]$content) {
  [System.IO.File]::WriteAllText($path, $content, $UTF8_NO_BOM)
}

# Legal module names: any configured module, plus the two pseudo-modules.
# When no module list is configured (missing or empty), there is nothing to validate
# a source module name against, so the guard is skipped entirely rather than refusing
# every non-pseudo module. tests/docs are always legal regardless.
$configuredModules = @()
if ($cfg.modules) { $configuredModules = @($cfg.modules) }
if ($configuredModules.Count -gt 0) {
  $legal = @('tests', 'docs') + $configuredModules
  if ($legal -cnotcontains $module) {
    [Console]::Error.WriteLine("new-file: unknown module '$module'. Legal values: $($legal -join ', '). Refused.")
    exit 1
  }
}

$full = $relPath
if (-not [System.IO.Path]::IsPathRooted($relPath)) { $full = Join-Path $root $relPath }

# Cached once; reused below both for the containment guard and for header selection.
# Case-sensitive (-ceq): matches the POSIX sibling's literal `[ "$module" = "docs" ]`, and
# the legal-module check above, which is now case-sensitive too (-cnotcontains).
$isDocs = ($module -ceq 'docs')

# Containment check, every target: must live under the repository root. Without this a source
# or tests target could escape the project entirely (`new-file core ../outside.c` wrote a real
# file next to the repository), which the docs branch already refused but the non-docs branch
# did not. GetFullPath resolves '..' first, so the comparison reflects where the path points.
$rootResolved = [System.IO.Path]::GetFullPath($root)
$fullResolved = [System.IO.Path]::GetFullPath($full)
$dirSep = [System.IO.Path]::DirectorySeparatorChar
if (-not $fullResolved.StartsWith($rootResolved.TrimEnd($dirSep) + $dirSep, [System.StringComparison]::OrdinalIgnoreCase)) {
  # Name the corrected path: the target lexically normalized, which collapses the '..' segments
  # and leaves the in-repository path the user most likely meant. Mirrors the POSIX
  # normalize_path helper rather than GetFullPath, which cannot express a root-relative result.
  # A List, not an array slice: $a[0..($a.Count - 2)] on a one-element array becomes $a[0..-1],
  # which PowerShell reads as indices 0 and -1 and duplicates the element instead of emptying it.
  $stack = New-Object System.Collections.Generic.List[string]
  foreach ($seg in ($relPath -replace '\\', '/').Split('/')) {
    if ($seg -eq '' -or $seg -eq '.') { continue }
    if ($seg -eq '..') { if ($stack.Count -gt 0) { $stack.RemoveAt($stack.Count - 1) }; continue }
    $stack.Add($seg)
  }
  $corrected = $stack -join '/'
  [Console]::Error.WriteLine("new-file: target must live inside the repository root. Got '$relPath', which resolves outside it. Did you mean '$corrected'? Refused.")
  exit 1
}

# What to show the user: the normalized location relative to $root, with forward slashes, i.e.
# where the bytes actually land. Matches the POSIX sibling's output byte for byte, where the
# raw $relPath would have echoed back separators and '..' segments the user typed but that
# nothing on disk reflects.
$displayPath = $fullResolved.Substring($rootResolved.TrimEnd($dirSep).Length).TrimStart($dirSep) -replace '\\', '/'

if ($isDocs) {
  $docBase = [System.IO.Path]::GetFullPath((Join-Path $root $docRoot))
  if (-not $fullResolved.StartsWith($docBase.TrimEnd($dirSep) + $dirSep, [System.StringComparison]::OrdinalIgnoreCase)) {
    $suggest = (Join-Path $docRoot $relPath) -replace '\\', '/'
    [Console]::Error.WriteLine("new-file: docs target must live under '$docRoot/'. Got '$relPath'. Did you mean '$suggest'? Refused.")
    exit 1
  }
}

if (Test-Path -LiteralPath $full) {
  [Console]::Error.WriteLine("new-file: refuses to overwrite existing file: $displayPath")
  exit 1
}

$parent = [System.IO.Path]::GetDirectoryName($full)
if ($parent -and -not (Test-Path -LiteralPath $parent)) {
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
}

# Emit non-ASCII via char codes so this script file stays pure ASCII and survives any re-encoding.
$dash = [string][char]0x2014
$bt = [string][char]0x60

if ($isDocs) {
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
  Write-Utf8 $full $header
  Write-Output "new-file: created $displayPath (docs)"
  # docs targets finish by regenerating the indexes.
  $docIndex = Join-Path $PSScriptRoot 'doc-index.ps1'
  if (Test-Path -LiteralPath $docIndex) { & $docIndex | Out-Null }
} else {
  $l1 = "$comment $module | $description"
  $l2 = "$comment Soft size threshold: 500 LOC. Run ${bt}phanes loc-check${bt} if uncertain."
  Write-Utf8 $full "$l1`n$l2`n`n"
  Write-Output "new-file: created $displayPath ($module)"
}
exit 0
