#!/bin/sh
# phanes-template v2.6 hook-stamp-guard
# PreToolUse(Write) guard. Reads the tool-call JSON from stdin. Denies (exit 2) creation of a NEW
# file under a stamped tree whose content lacks the required header stamp, so new files must go
# through `phanes new-file`. Every other call passes (exit 0). Fails open on any parse trouble.

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

cfg_arr() {
  tr '\n' ' ' < "$2" 2>/dev/null \
    | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p" \
    | grep -o '"[^"]*"' | sed 's/"//g'
}
cfg_str() {
  grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$2" 2>/dev/null | head -1 \
    | sed 's/.*:[[:space:]]*"\(.*\)"$/\1/'
}

raw=$(cat 2>/dev/null)
[ -z "$raw" ] && exit 0

fp=$(printf '%s' "$raw" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 \
  | sed 's/.*:[[:space:]]*"\(.*\)"$/\1/')
[ -z "$fp" ] && exit 0

# Only NEW files are guarded.
[ -e "$fp" ] && exit 0

start=$(dirname "$fp")
root=$(find_root_from "$start") || root=$(find_root_from "$(pwd)") || exit 0

case "$fp" in
  "$root"/*) rel=${fp#"$root"/} ;;
  *) exit 0 ;;
esac

cfgfile="$root/.phanes/config.json"
stamped="src tests documentation"
docRoot=$(cfg_str docRoot "$cfgfile"); [ -n "$docRoot" ] && stamped="$stamped $docRoot"
mods=$(cfg_arr modules "$cfgfile"); [ -n "$mods" ] && stamped="$stamped $mods"
trees=$(cfg_arr stampedTrees "$cfgfile"); [ -n "$trees" ] && stamped="$stamped $trees"

guarded=0
for t in $stamped; do
  [ -n "$t" ] || continue
  case "$rel" in
    "$t"|"$t"/*) guarded=1; break ;;
  esac
done
[ "$guarded" -eq 0 ] && exit 0

# The stamp appears in the content field; grepping the whole tool-call blob is sufficient.
printf '%s' "$raw" | grep -q 'Soft size threshold: 500 LOC' && exit 0
printf '%s' "$raw" | grep -q '<!-- DOC |' && exit 0

DASH=$(printf '\342\200\224')
printf 'New files must be created via `phanes new-file` %s the stamp is what `regen-registry` slices modules by; bypassing it produces silent API-baseline drift.\n' "$DASH" >&2
exit 2
