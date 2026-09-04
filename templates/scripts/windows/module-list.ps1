# phaneslight-template v3.7.1 module-list
# Prints the configured module list, one per line, read from .phaneslight/config.json.
# With --all, additionally prints the two pseudo-modules `new-file` accepts (tests, docs), which
# the config never carries. Default output is UNCHANGED and stays exactly the configured list:
# `update-preflight`'s modules sensor compares it line-for-line against config.modules, so a
# pseudo-module on the default path would read as a permanent drift verdict.
$ErrorActionPreference = 'Stop'

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
if (-not $root) { [Console]::Error.WriteLine('module-list: .phaneslight/config.json not found from this directory'); exit 1 }

$cfg = $null
try {
  $cfg = Get-Content -LiteralPath (Join-Path $root '.phaneslight\config.json') -Raw -Encoding utf8 | ConvertFrom-Json
} catch {
  # Unlike new-file (where "no restriction" is a coherent fallback), there is no honest default
  # module list to print here: printing "(no modules configured)" would claim the project has
  # none, when the truth is the config could not be read. Report the parse failure and refuse.
  [Console]::Error.WriteLine('module-list: .phaneslight/config.json is malformed, cannot list modules')
  exit 1
}
# Case-sensitive, matching the POSIX sibling's literal `[ "$1" = "--all" ]`.
$showAll = ($args.Count -gt 0 -and ($args -ccontains '--all'))

if (-not $cfg.modules -or $cfg.modules.Count -eq 0) {
  Write-Output '(no modules configured)'
} else {
  foreach ($m in $cfg.modules) { Write-Output $m }
}
if ($showAll) {
  # The two names `new-file` accepts that no config lists. They live here so the answer to "what
  # may I pass as <module>?" is reachable from the command that claims to answer it, rather than
  # only from new-file's refusal message.
  Write-Output 'tests'
  Write-Output 'docs'
}
exit 0
