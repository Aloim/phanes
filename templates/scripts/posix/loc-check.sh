#!/bin/sh
# phaneslight-template v3.7.1 loc-check
# Scans tracked source files and prints any over the 500 LOC soft ceiling with line counts.
# With file arguments, checks only those files (this is how hook-size-check invokes it).
# Advisory: always exits 0.
SOFT_CEILING=500

find_root() {
  d=$(pwd)
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -f "$d/.phaneslight/config.json" ] && { printf '%s' "$d"; return 0; }
    d=$(dirname "$d")
  done
  [ -f "/.phaneslight/config.json" ] && { printf '%s' "/"; return 0; }
  return 1
}

cfg_str() { # cfg_str KEY FILE
  grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$2" 2>/dev/null | head -1 \
    | sed 's/.*:[[:space:]]*"\(.*\)"$/\1/'
}

root=$(find_root) || { echo "loc-check: .phaneslight/config.json not found from this directory" >&2; exit 0; }
docRoot=$(cfg_str docRoot "$root/.phaneslight/config.json"); [ -z "$docRoot" ] && docRoot=documentation
# A trailing slash in docRoot would otherwise leak into every derived path and message
# (an empty basename, doubled separators, and absolute paths where relative ones belong).
while [ "${docRoot%/}" != "$docRoot" ]; do docRoot=${docRoot%/}; done
[ -z "$docRoot" ] && docRoot=documentation

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
    "$root/.phaneslight/"*) continue ;;
  esac
  case "$f" in
    *.png|*.jpg|*.jpeg|*.gif|*.ico|*.pdf|*.zip|*.exe|*.dll|*.bin|*.woff|*.woff2|*.ttf) continue ;;
  esac
  lines=$(awk 'END{print NR}' "$f" 2>/dev/null | tr -d ' ')
  [ -z "$lines" ] && continue
  if [ "$lines" -gt "$SOFT_CEILING" ]; then
    rel=${f#"$root"/}
    echo "OVER-CEILING: $rel ($lines lines, soft ceiling $SOFT_CEILING)"
    offenders=$((offenders + 1))
  fi
done < "$list"
rm -f "$list"

# A terminating count line, always (v3.6.1). The offender list can run to dozens of lines, and a
# reader who sees only the tail of it -- a truncated transcript, a scrolled terminal, a hook that
# surfaced the last few lines -- has no way to know how many lines came before. That is not
# hypothetical: a run counted 12 OVER-CEILING lines off a truncated tail when 19 had been printed,
# and wrote the 12 into a document. The count is now the LAST thing printed, so the tail carries it.
# Exit stays 0: this check is advisory by design, the ceiling is soft, and a non-zero exit here
# would fail the pre-commit hook and CI on a threshold nobody intended as a gate.
if [ "$offenders" -eq 0 ]; then
  echo "loc-check: OK"
else
  echo "loc-check: $offenders file(s) OVER-CEILING (soft ceiling $SOFT_CEILING lines). Advisory, exit 0."
fi
exit 0
