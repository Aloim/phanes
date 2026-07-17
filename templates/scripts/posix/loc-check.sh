#!/bin/sh
# phanes-template v2.6 loc-check
# Scans tracked source files and prints any over the 500 LOC soft ceiling with line counts.
# With file arguments, checks only those files (this is how hook-size-check invokes it).
# Advisory: always exits 0.
SOFT_CEILING=500

find_root() {
  d=$(pwd)
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -f "$d/.phanes/config.json" ] && { printf '%s' "$d"; return 0; }
    d=$(dirname "$d")
  done
  [ -f "/.phanes/config.json" ] && { printf '%s' "/"; return 0; }
  return 1
}

cfg_str() { # cfg_str KEY FILE
  grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$2" 2>/dev/null | head -1 \
    | sed 's/.*:[[:space:]]*"\(.*\)"$/\1/'
}

root=$(find_root) || { echo "loc-check: .phanes/config.json not found from this directory" >&2; exit 0; }
docRoot=$(cfg_str docRoot "$root/.phanes/config.json"); [ -z "$docRoot" ] && docRoot=documentation

# Build the file list.
list=$(mktemp)
if [ "$#" -gt 0 ]; then
  for a in "$@"; do
    case "$a" in
      /*) f=$a ;;
      *) f="$root/$a" ;;
    esac
    [ -f "$f" ] && printf '%s\n' "$f" >> "$list"
  done
else
  ( cd "$root" && git ls-files 2>/dev/null ) | while IFS= read -r rel; do
    [ -f "$root/$rel" ] && printf '%s\n' "$root/$rel"
  done >> "$list"
fi

offenders=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in
    "$root/$docRoot"/*) continue ;;
    "$root/.phanes/"*) continue ;;
  esac
  case "$f" in
    *.png|*.jpg|*.jpeg|*.gif|*.ico|*.pdf|*.zip|*.exe|*.dll|*.bin|*.woff|*.woff2|*.ttf) continue ;;
  esac
  lines=$(wc -l < "$f" 2>/dev/null | tr -d ' ')
  [ -z "$lines" ] && continue
  if [ "$lines" -gt "$SOFT_CEILING" ]; then
    rel=${f#"$root"/}
    echo "OVER-CEILING: $rel ($lines lines, soft ceiling $SOFT_CEILING)"
    offenders=$((offenders + 1))
  fi
done < "$list"
rm -f "$list"

[ "$offenders" -eq 0 ] && echo "loc-check: OK"
exit 0
