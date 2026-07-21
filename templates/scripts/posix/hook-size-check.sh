#!/bin/sh
# phanes-template v3.2 hook-size-check
# PostToolUse(Write|Edit) advisory. Reads the tool-call JSON from stdin and routes the touched file
# to the matching audit: a hot file (root CLAUDE.md or CLAUDE.local.md) runs register-check; a
# documentation file runs doc-index then doc-check; anything else runs loc-check on that file.
# Prints any warning into the transcript. Always exits 0.

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

find_root_from() {
  d=$1
  [ -n "$d" ] || return 1
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -f "$d/.phanes/config.json" ] && { printf '%s' "$d"; return 0; }
    d=$(dirname "$d")
  done
  [ -f "/.phanes/config.json" ] && { printf '%s' "/"; return 0; }
  return 1
}
cfg_str() {
  grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$2" 2>/dev/null | head -1 \
    | sed 's/.*:[[:space:]]*"\(.*\)"$/\1/'
}

# Run by hand instead of by a hook (stdin is a terminal, no tool-call JSON is coming): exit
# cleanly rather than blocking forever on a read that never returns.
[ -t 0 ] && exit 0
raw=$(cat 2>/dev/null)
[ -z "$raw" ] && exit 0
fp=$(printf '%s' "$raw" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 \
  | sed 's/.*:[[:space:]]*"\(.*\)"$/\1/')
[ -z "$fp" ] && exit 0

start=$(dirname "$fp")
root=$(find_root_from "$start") || root=$(find_root_from "$(pwd)") || exit 0
docRoot=$(cfg_str docRoot "$root/.phanes/config.json"); [ -z "$docRoot" ] && docRoot=documentation

case "$fp" in
  "$root"/*) rel=${fp#"$root"/} ;;
  *) rel=$fp ;;
esac

out=""
if [ "$rel" = "CLAUDE.md" ] || [ "$rel" = "CLAUDE.local.md" ]; then
  [ -f "$here/register-check.sh" ] && out=$( ( cd "$root" && sh "$here/register-check.sh" ) 2>/dev/null )
else
  case "$rel" in
    "$docRoot"/*)
      [ -f "$here/doc-index.sh" ] && ( cd "$root" && sh "$here/doc-index.sh" ) >/dev/null 2>&1
      [ -f "$here/doc-check.sh" ] && out=$( ( cd "$root" && sh "$here/doc-check.sh" ) 2>/dev/null )
      ;;
    *)
      [ -f "$here/loc-check.sh" ] && out=$( ( cd "$root" && sh "$here/loc-check.sh" "$fp" ) 2>/dev/null )
      ;;
  esac
fi

if [ -n "$out" ]; then
  printf '%s\n' "$out" | while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      *'[OK]'|*': OK') : ;;
      *) echo "[phanes size-check] $line" ;;
    esac
  done
fi
exit 0
