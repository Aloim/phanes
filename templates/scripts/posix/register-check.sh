#!/bin/sh
# phanes-template v3.1 register-check
# Measures the two hot files (root CLAUDE.md and CLAUDE.local.md) in characters and prints a status
# line each: OK (below 35000), SOFT-BREACH (35000 to 40000), CROP-REQUIRED (above 40000). Also lists
# every completed register entry (## checkmark heading) still present, and reports the
# standing-blocker section character count separately. Advisory: always exits 0.
SOFT=35000
CROP=40000

find_root() {
  d=$(pwd)
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -f "$d/.phanes/config.json" ] && { printf '%s' "$d"; return 0; }
    d=$(dirname "$d")
  done
  [ -f "/.phanes/config.json" ] && { printf '%s' "/"; return 0; }
  return 1
}

root=$(find_root) || { echo "register-check: .phanes/config.json not found from this directory" >&2; exit 0; }

# Markers as UTF-8 byte sequences (checkmark U+2705, no-entry U+1F6D1).
MARK_DONE=$(printf '\342\234\205')
MARK_BLOCK=$(printf '\360\237\233\221')

status() {
  c=$1
  if [ "$c" -gt "$CROP" ]; then echo "CROP-REQUIRED"
  elif [ "$c" -ge "$SOFT" ]; then echo "SOFT-BREACH"
  else echo "OK"; fi
}

for name in CLAUDE.md CLAUDE.local.md; do
  f="$root/$name"
  if [ ! -f "$f" ]; then
    echo "$name: absent"
    continue
  fi
  chars=$(wc -m < "$f" 2>/dev/null | tr -d ' ')
  [ -z "$chars" ] && chars=0
  echo "$name: $chars chars [$(status "$chars")]"

  # Completed entries still present.
  grep -E "^##[[:space:]]" "$f" 2>/dev/null | grep -F "$MARK_DONE" 2>/dev/null | while IFS= read -r ln; do
    echo "  COMPLETED-STILL-PRESENT: $ln"
  done

  # Standing-blocker section character count: first blocker heading to the next heading.
  blk=$(awk -v m="$MARK_BLOCK" '
    /^#{1,6}[[:space:]]/ {
      if (index($0, m) > 0) { inblk=1; chars += length($0)+1; next }
      else if (inblk) { inblk=0 }
    }
    inblk { chars += length($0)+1 }
    END { print chars+0 }
  ' "$f")
  if [ "$blk" -gt 0 ] 2>/dev/null; then
    echo "  standing-blockers section: $blk chars"
  fi
done
exit 0
