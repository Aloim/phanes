# phanes-template v3.4.0 batch-apply
# Applies a batch of {file, old, new} exact-match edits and prints a per-edit review diff
# computed against saved pre-images. Git is NOT a dependency: the undo substrate is a
# byte-for-byte pre-image of every file touched, saved before the first write, so this
# works on untracked files, gitignored files, dirty trees, and outside any repository.
# Modes: default applies per-edit (failures do not discard the other edits); --atomic is
# all-or-nothing; --reject <indices> restores pre-images and re-applies the surviving
# edits of the SAME batch (the Critic hunk-rejection path).
# Exit codes: 0 every requested edit applied; 1 usage error (nothing touched);
# 2 --reject refused (nothing touched); 3 nothing applied (all edits failed, or a write
# failure was reverted from pre-images); 4 partial (some applied, some failed).
$ErrorActionPreference = 'Stop'
$DIFF_CAP = 20000

function Find-PhanesRoot {
  $d = (Get-Location).Path
  while ($true) {
    if (Test-Path -LiteralPath (Join-Path $d '.phanes\config.json')) { return $d }
    $p = [System.IO.Path]::GetDirectoryName($d)
    if (-not $p -or $p -eq $d) { return $null }
    $d = $p
  }
}

# --- node-parity JSON emitter (JSON.stringify(x, null, 2) format), so the stdout report is
# --- byte-identical to the POSIX sibling and callers can diff outputs across platforms.
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
  if ($value -is [int] -or $value -is [long] -or $value -is [double]) { return [string]$value }
  if ($value -is [System.Collections.IDictionary]) {
    $keys = @($value.Keys)
    if ($keys.Count -eq 0) { return '{}' }
    $parts = @()
    foreach ($k in $keys) { $parts += ($padIn + (ConvertTo-JsonStringLiteral ([string]$k)) + ': ' + (ConvertTo-NodeJson $value[$k] ($indent + 2))) }
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

function Get-Sha256Hex([byte[]]$bytes) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '') }
  finally { $sha.Dispose() }
}
function Decode-Utf8([byte[]]$bytes) {
  $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  if ($bom) { $text = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3) }
  elseif ($bytes.Length -eq 0) { $text = '' }
  else { $text = [System.Text.Encoding]::UTF8.GetString($bytes) }
  return @{ Text = $text; Bom = $bom }
}
function Encode-Utf8([string]$text, [bool]$bom) {
  $body = [System.Text.Encoding]::UTF8.GetBytes($text)
  if ($bom) {
    $out = New-Object byte[] ($body.Length + 3)
    $out[0] = 0xEF; $out[1] = 0xBB; $out[2] = 0xBF
    [Array]::Copy($body, 0, $out, 3, $body.Length)
    return ,$out
  }
  return ,$body
}
# Ordinal occurrence count via IndexOf: never [regex]::Matches with an escaped needle, which
# collapses on multi-megabyte needles (the 400-second M5 cliff), and never the culture-aware
# String.IndexOf(string) default of .NET Framework.
function Count-Occurrences([string]$hay, [string]$needle) {
  $n = 0; $i = 0
  while ($true) {
    $i = $hay.IndexOf($needle, $i, [System.StringComparison]::Ordinal)
    if ($i -lt 0) { break }
    $n++; $i += $needle.Length
  }
  return $n
}
function Get-DominantEol([string]$text) {
  $crlf = Count-Occurrences $text "`r`n"
  $lone = (Count-Occurrences $text "`n") - $crlf
  if ($crlf -gt $lone) { return "`r`n" }
  return "`n"
}
# Match contract: old is normalized to LF, then tried against the buffer both as-is and
# expanded to CRLF (the buffer as earlier edits in this batch left it). Exactly one
# occurrence across the tried forms is required. The replacement takes the convention of
# the matched region; a single-line old takes the buffer-dominant convention for any
# newlines inside new. The splice touches only the matched span, so an edit can never
# change the line-ending convention of text it did not match.
function Find-Match([string]$text, [string]$oldRaw) {
  $oldLf = $oldRaw.Replace("`r`n", "`n")
  $forms = @($oldLf)
  if ($oldLf.IndexOf([char]"`n") -ge 0) { $forms += $oldLf.Replace("`n", "`r`n") }
  $total = 0; $index = -1; $matched = $null
  foreach ($f in $forms) {
    $n = Count-Occurrences $text $f
    $total += $n
    if ($n -gt 0 -and $null -eq $matched) { $index = $text.IndexOf($f, [System.StringComparison]::Ordinal); $matched = $f }
  }
  return @{ Total = $total; Index = $index; Matched = $matched; OldLf = $oldLf }
}
function Split-EditLines([string]$s) {
  $parts = [regex]::Split($s, "`r`n|`n")
  if ($parts.Length -gt 1 -and $parts[$parts.Length - 1] -eq '') { $parts = $parts[0..($parts.Length - 2)] }
  return ,@($parts)
}

function Show-Usage([string]$msg) {
  $line = 'USAGE: batch-apply <edit-batch.json> [--atomic] [--reject <indices>]'
  if ($msg) { $line = $line + ' -- ' + $msg }
  [Console]::Error.WriteLine($line)
  exit 1
}

$root = Find-PhanesRoot
if (-not $root) { [Console]::Error.WriteLine('batch-apply: .phanes/config.json not found from this directory'); exit 1 }

$batchArg = $null; $atomic = $false; $rejectArg = $null
for ($i = 0; $i -lt $args.Count; $i++) {
  $a = [string]$args[$i]
  if ($a -eq '--atomic') { $atomic = $true }
  elseif ($a -eq '--reject') {
    $i++
    if ($i -ge $args.Count) { Show-Usage '--reject needs a comma-separated index list' }
    $rejectArg = [string]$args[$i]
  }
  elseif ($a.Length -gt 1 -and $a.Substring(0, 2) -eq '--') { Show-Usage ('unknown option ' + $a) }
  elseif ($null -eq $batchArg) { $batchArg = $a }
  else { Show-Usage ('unexpected extra argument ' + $a) }
}
if ($null -eq $batchArg) { Show-Usage $null }
if ($atomic -and $null -ne $rejectArg) { Show-Usage '--atomic and --reject cannot be combined; a reject re-apply is always all-or-nothing' }

$batchFile = $batchArg
if (-not [System.IO.Path]::IsPathRooted($batchFile)) { $batchFile = Join-Path (Get-Location).Path $batchFile }
try { $batchFile = [System.IO.Path]::GetFullPath($batchFile) } catch { Show-Usage ('cannot resolve ' + $batchArg) }
$batchBytes = $null
try { $batchBytes = [System.IO.File]::ReadAllBytes($batchFile) } catch { Show-Usage ('cannot read ' + $batchFile + ' (' + $_.Exception.Message + ')') }
$bd = Decode-Utf8 $batchBytes
$batch = $null
try { $batch = $bd.Text | ConvertFrom-Json } catch { Show-Usage ('could not parse ' + $batchFile + ' as JSON: ' + $_.Exception.Message) }
if (-not $batch -or -not ($batch.edits -is [System.Array])) { Show-Usage 'batch must be a JSON object carrying an "edits" array' }
$edits = @($batch.edits)
# An empty batch is bad input, not a failed batch and not a success: nothing was
# attempted, so exit 3 (failed) and exit 0 (applied) would both lie to the caller.
if ($edits.Count -eq 0) { Show-Usage 'edit batch is empty, nothing to apply' }

$rootReal = (Resolve-Path -LiteralPath $root).Path
$rootPrefix = $rootReal.TrimEnd('\') + '\'
$cmpPrefix = $rootPrefix.ToLowerInvariant()
$rootKey = (Get-Sha256Hex ([System.Text.Encoding]::UTF8.GetBytes($rootReal.ToLowerInvariant()))).Substring(0, 16)
$stateDir = Join-Path $env:TEMP (Join-Path 'phanes-batch' $rootKey)
$preDir = Join-Path $stateDir 'pre'
$stateFile = Join-Path $stateDir 'state.json'
$batchSha = Get-Sha256Hex $batchBytes

$buffers = @{}
$bufferOrder = New-Object System.Collections.ArrayList
$dirChecked = @{}
function Test-ReparseAncestor([string]$resolved) {
  $d = [System.IO.Path]::GetDirectoryName($resolved)
  while ($d -and $d.Length -gt $rootReal.Length) {
    $k = $d.ToLowerInvariant()
    if ($dirChecked.ContainsKey($k)) {
      if ($dirChecked[$k]) { return $true }
    } else {
      $isRp = $false
      try {
        $di = Get-Item -LiteralPath $d -Force
        if ($di.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { $isRp = $true }
      } catch { }
      $dirChecked[$k] = $isRp
      if ($isRp) { return $true }
    }
    $d = [System.IO.Path]::GetDirectoryName($d)
  }
  return $false
}
function Get-EditBuffer($fileField) {
  if (-not ($fileField -is [string]) -or $fileField -eq '') { return @{ Err = '"file" must be a non-empty string path' } }
  if ([System.IO.Path]::IsPathRooted($fileField)) { return @{ Err = '"file" must be relative to the project root, not absolute' } }
  $resolved = $null
  try { $resolved = [System.IO.Path]::GetFullPath((Join-Path $rootReal $fileField)) } catch { return @{ Err = ('cannot resolve path: ' + $fileField) } }
  if (-not $resolved.ToLowerInvariant().StartsWith($cmpPrefix, [System.StringComparison]::Ordinal)) { return @{ Err = ('path escapes the project root: resolves to ' + $resolved) } }
  $key = $resolved.ToLowerInvariant()
  if ($buffers.ContainsKey($key)) { return @{ Buf = $buffers[$key] } }
  $item = $null
  try { $item = Get-Item -LiteralPath $resolved -Force } catch { return @{ Err = ('file not found: ' + $fileField) } }
  if ($item.PSIsContainer) { return @{ Err = ('not a regular file: ' + $fileField) } }
  if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return @{ Err = ('refusing to edit through a symbolic link: ' + $fileField) } }
  if (Test-ReparseAncestor $resolved) { return @{ Err = ('resolved path escapes the project root (symlinked parent): ' + $fileField) } }
  $bytes = [System.IO.File]::ReadAllBytes($resolved)
  $d = Decode-Utf8 $bytes
  # Exactness guard: if decode-then-reencode does not reproduce the original bytes, the
  # file is not UTF-8 text (UTF-16, binary, mixed encodings) and a splice through a lossy
  # decode would corrupt the regions this batch never touched. Refuse instead.
  $roundTrip = Encode-Utf8 $d.Text $d.Bom
  if ((Get-Sha256Hex $roundTrip) -ne (Get-Sha256Hex $bytes)) { return @{ Err = ('not UTF-8 text, refusing to edit: ' + $fileField) } }
  $rel = $resolved.Substring($rootPrefix.Length).Replace('\', '/')
  $buf = @{ Key = $key; Resolved = $resolved; Rel = $rel; OrigBytes = $bytes; Text = $d.Text; Bom = $d.Bom; Modified = $false; PostBytes = $null }
  $buffers[$key] = $buf
  [void]$bufferOrder.Add($buf)
  return @{ Buf = $buf }
}

function Invoke-Edits([int[]]$indices) {
  $results = New-Object System.Collections.ArrayList
  $applied = 0; $failed = 0
  foreach ($i in $indices) {
    $e = $edits[$i]
    $fileLabel = '(invalid file field)'
    if ($e -and ($e.file -is [string])) { $fileLabel = $e.file }
    $reason = $null
    if (-not ($e.old -is [string]) -or -not ($e.new -is [string])) { $reason = '"old" and "new" must both be JSON strings' }
    elseif ($e.old -eq '') { $reason = '"old" must not be empty' }
    if ($null -ne $reason) { [void]$results.Add(@{ Index = $i; File = $fileLabel; Status = 'failed'; Reason = $reason }); $failed++; continue }
    $l = Get-EditBuffer $e.file
    if ($l.Err) { [void]$results.Add(@{ Index = $i; File = $fileLabel; Status = 'failed'; Reason = $l.Err }); $failed++; continue }
    $buf = $l.Buf
    $loc = Find-Match $buf.Text $e.old
    if ($loc.Total -eq 0) { $reason = 'old not found in ' + $buf.Rel + ' (matched after CRLF/LF normalization; a span mixing both conventions cannot match)' }
    elseif ($loc.Total -gt 1) { $reason = 'old matches ' + $loc.Total + ' times in ' + $buf.Rel + ', must be unique in the file as earlier edits left it' }
    elseif ($e.new.Replace("`r`n", "`n") -ceq $loc.OldLf) { $reason = '"new" is identical to "old", nothing to change' }
    if ($null -ne $reason) { [void]$results.Add(@{ Index = $i; File = $buf.Rel; Status = 'failed'; Reason = $reason }); $failed++; continue }
    $newLf = $e.new.Replace("`r`n", "`n")
    if ($loc.Matched.IndexOf("`r`n", [System.StringComparison]::Ordinal) -ge 0) { $eol = "`r`n" }
    elseif ($loc.OldLf.IndexOf([char]"`n") -ge 0) { $eol = "`n" }
    else { $eol = Get-DominantEol $buf.Text }
    if ($eol -eq "`r`n") { $newOut = $newLf.Replace("`n", "`r`n") } else { $newOut = $newLf }
    $before = $buf.Text.Substring(0, $loc.Index)
    $after = $buf.Text.Substring($loc.Index + $loc.Matched.Length)
    $line = (Count-Occurrences $before "`n") + 1
    $bl = [regex]::Split($before, "`r`n|`n")
    $ctxBefore = New-Object System.Collections.ArrayList
    for ($k = [Math]::Max(0, $bl.Length - 3); $k -lt $bl.Length - 1; $k++) { [void]$ctxBefore.Add($bl[$k]) }
    $al = [regex]::Split($after, "`r`n|`n")
    $ctxAfter = New-Object System.Collections.ArrayList
    for ($k = 1; $k -lt [Math]::Min(3, $al.Length); $k++) { [void]$ctxAfter.Add($al[$k]) }
    $buf.Text = $before + $newOut + $after
    $buf.Modified = $true
    [void]$results.Add(@{ Index = $i; File = $buf.Rel; Status = 'applied'; Line = $line;
      OldLines = (Split-EditLines $loc.Matched); NewLines = (Split-EditLines $newOut);
      CtxBefore = $ctxBefore; CtxAfter = $ctxAfter })
    $applied++
  }
  return @{ Results = $results; Applied = $applied; Failed = $failed }
}

function Format-ReviewDiff($results) {
  $blocks = @()
  foreach ($r in $results) {
    if ($r.Status -ne 'applied') { continue }
    $lines = @()
    $lines += ('=== edit ' + $r.Index + ': ' + $r.File + ' @ line ' + $r.Line + ' ===')
    foreach ($l in $r.CtxBefore) { $lines += ('  ' + $l) }
    foreach ($l in $r.OldLines) { $lines += ('- ' + $l) }
    foreach ($l in $r.NewLines) { $lines += ('+ ' + $l) }
    foreach ($l in $r.CtxAfter) { $lines += ('  ' + $l) }
    $blocks += ($lines -join "`n")
  }
  $full = $blocks -join "`n`n"
  if ($full.Length -le $DIFF_CAP) { return @{ Text = $full; Truncated = $false } }
  $stat = @()
  foreach ($r in $results) {
    if ($r.Status -ne 'applied') { continue }
    $stat += ('edit ' + $r.Index + ': ' + $r.File + ' @ line ' + $r.Line + ' (-' + @($r.OldLines).Count + ' +' + @($r.NewLines).Count + ' lines)')
  }
  $stat += ('(review diff omitted: ' + $full.Length + ' chars exceeds the ' + $DIFF_CAP + '-char cap; pre-images are kept under ' + $preDir + ', diff any file manually, e.g. git diff --no-index <pre-image> <file>)')
  return @{ Text = ($stat -join "`n"); Truncated = $true }
}

function Write-ReportAndExit([string]$mode, $res, $rejected, [int]$exitCode, [bool]$wrote, $restored) {
  $touched = @()
  if ($wrote) {
    foreach ($b in $bufferOrder) { if ($b.Modified) { $touched += $b.Rel } }
    $touched = @($touched)
    [Array]::Sort($touched, [System.StringComparer]::Ordinal)
  }
  $appliedIdx = New-Object System.Collections.ArrayList
  $failedArr = New-Object System.Collections.ArrayList
  foreach ($r in $res.Results) {
    if ($r.Status -eq 'applied') { [void]$appliedIdx.Add([int]$r.Index) }
    else { [void]$failedArr.Add(([ordered]@{ index = [int]$r.Index; file = $r.File; reason = $r.Reason })) }
  }
  $diffText = '(nothing was written)'; $truncated = $false
  if ($wrote) { $d = Format-ReviewDiff $res.Results; $diffText = $d.Text; $truncated = $d.Truncated }
  $preDirOut = $null
  if ($wrote) { $preDirOut = $stateDir }
  $report = [ordered]@{
    mode = $mode
    appliedCount = [int]$res.Applied
    failedCount = [int]$res.Failed
    applied = $appliedIdx
    failed = $failedArr
    rejectedIndices = $rejected
    touchedFiles = $touched
    restoredFiles = $restored
    preImageDir = $preDirOut
    diffTruncated = $truncated
  }
  Write-Output (ConvertTo-NodeJson $report 0)
  Write-Output '--- review diff (computed against pre-images, uncommitted) ---'
  Write-Output $diffText
  exit $exitCode
}

if ($null -eq $rejectArg) {
  $all = New-Object System.Collections.Generic.List[int]
  for ($i = 0; $i -lt $edits.Count; $i++) { [void]$all.Add($i) }
  $res = Invoke-Edits $all.ToArray()
  foreach ($r in $res.Results) { if ($r.Status -eq 'failed') { [Console]::Error.WriteLine('EDIT-FAILED ' + $r.Index + ': ' + $r.Reason) } }
  $mode = 'partial'
  if ($atomic) { $mode = 'atomic' }
  if ($res.Applied -eq 0) {
    [Console]::Error.WriteLine('BATCH_FAILED: no edit could be applied; nothing was written')
    Write-ReportAndExit $mode $res @() 3 $false @()
  }
  if ($atomic -and $res.Failed -gt 0) {
    [Console]::Error.WriteLine('BATCH_FAILED: ' + $res.Failed + ' edit(s) failed under --atomic; nothing was written')
    Write-ReportAndExit $mode $res @() 3 $false @()
  }
  # A new apply invalidates any previous state: wipe first, then save every pre-image and
  # the state record BEFORE the first target write, so a crash between writes always
  # leaves a complete undo substrate on disk (and a later --reject verifies post-hashes,
  # so a stale or crashed state can never silently revert anything).
  $mods = @()
  foreach ($b in $bufferOrder) { if ($b.Modified) { $mods += ,$b } }
  $mods = @($mods | Sort-Object -Property @{ Expression = { $_.Rel } })
  if (Test-Path -LiteralPath $stateDir) { Remove-Item -LiteralPath $stateDir -Recurse -Force -Confirm:$false }
  New-Item -ItemType Directory -Force -Path $preDir | Out-Null
  $appliedIdx = New-Object System.Collections.ArrayList
  foreach ($r in $res.Results) { if ($r.Status -eq 'applied') { [void]$appliedIdx.Add([int]$r.Index) } }
  $filesDict = [ordered]@{}
  $n = 0
  foreach ($b in $mods) {
    $preName = [string]$n + '.bin'; $n++
    [System.IO.File]::WriteAllBytes((Join-Path $preDir $preName), $b.OrigBytes)
    $b.PostBytes = Encode-Utf8 $b.Text $b.Bom
    $filesDict[$b.Rel] = [ordered]@{ pre = $preName; preSha256 = (Get-Sha256Hex $b.OrigBytes); postSha256 = (Get-Sha256Hex $b.PostBytes) }
  }
  $state = [ordered]@{ batchSha256 = $batchSha; root = $rootReal; createdAt = (Get-Date).ToUniversalTime().ToString('o');
    appliedIndices = $appliedIdx; rejectedIndices = @(); files = $filesDict }
  [System.IO.File]::WriteAllText($stateFile, (ConvertTo-Json -InputObject $state -Depth 10), (New-Object System.Text.UTF8Encoding($false)))
  $written = New-Object System.Collections.ArrayList
  $writeFailed = $null
  try {
    foreach ($b in $mods) { [System.IO.File]::WriteAllBytes($b.Resolved, $b.PostBytes); [void]$written.Add($b) }
    foreach ($b in $mods) {
      $back = [System.IO.File]::ReadAllBytes($b.Resolved)
      if ((Get-Sha256Hex $back) -ne $filesDict[$b.Rel].postSha256) { throw ('post-write read-back mismatch on ' + $b.Rel) }
    }
  } catch { $writeFailed = $_.Exception.Message }
  if ($null -ne $writeFailed) {
    [Console]::Error.WriteLine('BATCH_FAILED: write phase: ' + $writeFailed)
    $revertOk = $true
    foreach ($b in $written) {
      try { [System.IO.File]::WriteAllBytes($b.Resolved, $b.OrigBytes) }
      catch { $revertOk = $false; [Console]::Error.WriteLine('REVERT-FAILED: ' + $b.Rel + ': ' + $_.Exception.Message + ' (pre-image kept: ' + (Join-Path $preDir $filesDict[$b.Rel].pre) + ')') }
    }
    if ($revertOk) {
      [Console]::Error.WriteLine('Reverted ' + $written.Count + ' file(s) to their pre-batch bytes.')
      try { Remove-Item -LiteralPath $stateDir -Recurse -Force -Confirm:$false } catch { }
    }
    Write-ReportAndExit $mode $res @() 3 $false @()
  }
  if ($res.Failed -gt 0) {
    [Console]::Error.WriteLine('PARTIAL: ' + $res.Applied + ' applied, ' + $res.Failed + ' failed; applied edits are kept, failures are listed in the report')
    Write-ReportAndExit $mode $res @() 4 $true @()
  }
  Write-ReportAndExit $mode $res @() 0 $true @()
} else {
  $rejectSet = New-Object 'System.Collections.Generic.HashSet[int]'
  foreach ($part in ($rejectArg -split ',')) {
    $t = $part.Trim()
    if ($t -eq '') { continue }
    $v = 0
    if (-not [int]::TryParse($t, [ref]$v) -or $v -lt 0) { Show-Usage ('--reject indices must be non-negative integers, got ' + $part) }
    if ($v -ge $edits.Count) { Show-Usage ('--reject index ' + $v + ' is out of range for a batch of ' + $edits.Count + ' edit(s)') }
    [void]$rejectSet.Add($v)
  }
  if ($rejectSet.Count -eq 0) { Show-Usage '--reject needs at least one index' }
  function Deny-Reject([string]$msg) { [Console]::Error.WriteLine('REJECT_REFUSED: ' + $msg + '; nothing was changed on disk'); exit 2 }
  $state = $null
  try { $state = Get-Content -LiteralPath $stateFile -Raw -Encoding utf8 | ConvertFrom-Json } catch { $state = $null }
  if (-not $state -or -not $state.files) { Deny-Reject ('no saved pre-image state for this project (' + $stateDir + '); --reject only follows a successful batch-apply of the same batch') }
  if ($state.batchSha256 -cne $batchSha) { Deny-Reject 'the saved state belongs to a different batch file; re-run batch-apply with the original batch' }
  # Every touched file must still be exactly as the last apply (or last reject) left it,
  # otherwise restoring pre-images would destroy interleaved later work. This is the
  # stale-state guard: a crashed or superseded state can never silently revert anything.
  $stFiles = @($state.files.PSObject.Properties | ForEach-Object { $_.Name })
  [Array]::Sort($stFiles, [System.StringComparer]::Ordinal)
  foreach ($rel in $stFiles) {
    $resolved = [System.IO.Path]::GetFullPath((Join-Path $rootReal $rel))
    $cur = $null
    try { $cur = [System.IO.File]::ReadAllBytes($resolved) } catch { Deny-Reject ($rel + ' is unreadable (' + $_.Exception.Message + ')') }
    if ((Get-Sha256Hex $cur) -cne $state.files.$rel.postSha256) { Deny-Reject ($rel + ' changed since the batch was applied') }
  }
  foreach ($rel in $stFiles) {
    $resolved = [System.IO.Path]::GetFullPath((Join-Path $rootReal $rel))
    $key = $resolved.ToLowerInvariant()
    $bytes = [System.IO.File]::ReadAllBytes((Join-Path $preDir $state.files.$rel.pre))
    $d = Decode-Utf8 $bytes
    $buf = @{ Key = $key; Resolved = $resolved; Rel = $rel; OrigBytes = $bytes; Text = $d.Text; Bom = $d.Bom; Modified = $false; PostBytes = $null }
    $buffers[$key] = $buf
    [void]$bufferOrder.Add($buf)
  }
  $survivors = New-Object System.Collections.Generic.List[int]
  foreach ($i in @($state.appliedIndices)) { if (-not $rejectSet.Contains([int]$i)) { [void]$survivors.Add([int]$i) } }
  $res = Invoke-Edits $survivors.ToArray()
  if ($res.Failed -gt 0) {
    foreach ($r in $res.Results) { if ($r.Status -eq 'failed') { [Console]::Error.WriteLine('EDIT-FAILED ' + $r.Index + ': ' + $r.Reason) } }
    Deny-Reject 'a surviving edit no longer applies without the rejected one(s); author a fresh batch instead'
  }
  $restored = New-Object System.Collections.ArrayList
  $newFiles = [ordered]@{}
  foreach ($rel in $stFiles) {
    $resolved = [System.IO.Path]::GetFullPath((Join-Path $rootReal $rel))
    $key = $resolved.ToLowerInvariant()
    $b = $buffers[$key]
    $b.PostBytes = Encode-Utf8 $b.Text $b.Bom
    [System.IO.File]::WriteAllBytes($resolved, $b.PostBytes)
    $newFiles[$rel] = [ordered]@{ pre = $state.files.$rel.pre; preSha256 = $state.files.$rel.preSha256; postSha256 = (Get-Sha256Hex $b.PostBytes) }
    if (-not $b.Modified) { [void]$restored.Add($rel) }
  }
  $rejectedSorted = @($rejectSet)
  [Array]::Sort($rejectedSorted)
  $newState = [ordered]@{ batchSha256 = $state.batchSha256; root = $state.root; createdAt = $state.createdAt;
    appliedIndices = $survivors; rejectedIndices = $rejectedSorted; files = $newFiles }
  [System.IO.File]::WriteAllText($stateFile, (ConvertTo-Json -InputObject $newState -Depth 10), (New-Object System.Text.UTF8Encoding($false)))
  Write-ReportAndExit 'reject' $res $rejectedSorted 0 $true $restored
}
