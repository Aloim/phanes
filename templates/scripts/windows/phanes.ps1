# phanes-template v3.0 phanes
# Dispatcher. Routes `phanes <subcommand> [args]` to the sibling script in this directory.
# Resolves siblings by this script's own location, so it works from any working directory.
$ErrorActionPreference = 'Stop'

if ($args.Count -lt 1) {
  Write-Output "phanes: subcommands: new-file loc-check doc-check register-check doc-index module-list list-apis regen-registry api-diff"
  exit 0
}

$sub = $args[0]
$rest = @()
if ($args.Count -gt 1) { $rest = $args[1..($args.Count - 1)] }

$target = Join-Path $PSScriptRoot ($sub + '.ps1')
if (-not (Test-Path -LiteralPath $target)) {
  [Console]::Error.WriteLine("phanes: unknown subcommand '$sub' (no $sub.ps1 in $PSScriptRoot)")
  exit 1
}

& $target @rest
exit $LASTEXITCODE
