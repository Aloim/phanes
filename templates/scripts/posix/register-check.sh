#!/bin/sh
# phanes-template v3.4.0 register-check
# Measures the two hot files (root CLAUDE.md and CLAUDE.local.md) in characters and prints a status
# line each: OK (below 35000), SOFT-BREACH (35000 to 40000), CROP-REQUIRED (above 40000). Also lists
# every completed register entry (## checkmark heading) still present, reports the
# standing-blocker section character count separately, and reports the Pinned Directives
# block character count separately (v3.2, the root CLAUDE.md crop-exemption class).
# Advisory: always exits 0.
SOFT=35000
CROP=40000

# Count Unicode code points, not bytes and not UTF-16 units, so one astral character (an emoji)
# costs 1 against the ceiling on every platform. Reads stdin. `wc -m` cannot be used: under LC_ALL=C
# it degenerates to byte counting (an emoji costs 4), and on builds with a 16-bit wchar_t
# (Git for Windows) even a UTF-8 locale yields UTF-16 units (an emoji costs 2). Stripping UTF-8
# continuation bytes (0x80 to 0xBF) leaves exactly one byte per code point, with no locale dependency.
# A leading UTF-8 BOM is dropped first: Windows reads these files with Get-Content -Encoding utf8,
# which strips the BOM, so keeping it here would make the two platforms disagree by one character.
BOM=$(printf '\357\273\277')
count_chars() {
  LC_ALL=C sed "1s/^$BOM//" | LC_ALL=C tr -d '\200-\277' | wc -c | tr -d ' '
}

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

# Without the counting tools every measurement would silently read 0 and every file would report OK.
# Say so instead of lying, and still exit 0 (advisory).
for tool in tr wc sed awk; do
  command -v "$tool" >/dev/null 2>&1 || { echo "register-check: $tool unavailable, cannot measure" >&2; exit 0; }
done

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
  # An unreadable hot file must be named, not silently reported as 0 chars and OK.
  if [ ! -r "$f" ]; then
    echo "register-check: cannot read $name, skipping" >&2
    continue
  fi
  # Code points, not bytes (see count_chars).
  chars=$(count_chars < "$f" 2>/dev/null)
  [ -z "$chars" ] && chars=0
  echo "$name: $chars chars [$(status "$chars")]"

  # Completed entries still present.
  grep -E "^##[[:space:]]" "$f" 2>/dev/null | grep -F "$MARK_DONE" 2>/dev/null | while IFS= read -r ln; do
    echo "  COMPLETED-STILL-PRESENT: $ln"
  done

  # Standing-blocker section character count: first blocker heading to the next heading.
  # awk emits the section verbatim (one trailing newline per line, matching the old +1 per line)
  # and count_chars converts it to code points, so the unit matches the file total above.
  blk=$(awk -v m="$MARK_BLOCK" '
    /^#{1,6}[[:space:]]/ {
      if (index($0, m) > 0) { inblk=1; print; next }
      else if (inblk) { inblk=0 }
    }
    inblk { print }
  ' "$f" | count_chars)
  if [ "$blk" -gt 0 ] 2>/dev/null; then
    echo "  standing-blockers section: $blk chars"
  fi

  # Pinned Directives block character count (v3.2): opening marker line to closing marker line, inclusive.
  # Code points, same unit as the file total (see count_chars).
  pin=$(awk '
    /^<!-- PINNED DIRECTIVES/ { inpin=1 }
    inpin { print }
    /^<!-- \/PINNED DIRECTIVES -->/ { inpin=0 }
  ' "$f" | count_chars)
  if [ "$pin" -gt 0 ] 2>/dev/null; then
    echo "  pinned-directives block: $pin chars"
  fi
done
exit 0
