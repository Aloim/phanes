#!/bin/sh
# phanes-template v3.0 new-file
# Creates a file with the required header stamp. The only sanctioned way to create files.
# Usage: phanes new-file <module> <path> "<description of at least five words>"
# <module> may be a source module, tests, or docs. docs targets get the DOC DISCIPLINE header and
# trigger a doc-index regeneration; source and tests targets get the module stamp in the project's
# comment syntax (read from .phanes/config.json). Refuses a missing or too-short description.

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

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

if [ "$#" -lt 3 ]; then
  echo 'new-file: usage: phanes new-file <module> <path> "<description of at least five words>"' >&2
  exit 1
fi
module=$1
relPath=$2
shift 2
description=$*

wordCount=$(printf '%s\n' "$description" | wc -w | tr -d ' ')
if [ "$wordCount" -lt 5 ]; then
  echo "new-file: description must be at least five words (got $wordCount). Refused." >&2
  exit 1
fi

root=$(find_root) || { echo "new-file: .phanes/config.json not found from this directory" >&2; exit 1; }
comment=$(cfg_str commentSyntax "$root/.phanes/config.json"); [ -z "$comment" ] && comment='//'

case "$relPath" in
  /*) full=$relPath ;;
  *) full="$root/$relPath" ;;
esac

if [ -e "$full" ]; then
  echo "new-file: refuses to overwrite existing file: $relPath" >&2
  exit 1
fi

mkdir -p "$(dirname "$full")"

DASH=$(printf '\342\200\224')  # em dash, kept out of the source as bytes

if [ "$module" = "docs" ]; then
  {
    printf '<!-- DOC | %s -->\n' "$description"
    printf '<!-- DOC DISCIPLINE | Soft ceiling: 500 lines. One topic per file; structure under ## headings.\n'
    printf '     The DOC line above feeds `phanes doc-index` %s keep it accurate; it is this file'"'"'s line in _index.md.\n' "$DASH"
    printf '     If this file exceeds the ceiling: split it into a same-named folder of focused topic files;\n'
    printf '     carry both header lines into every part; update every inbound reference in the same change set;\n'
    printf '     finish by running `phanes doc-index`.\n'
    printf '     Consumers: NEVER bulk-read documentation folders %s read _index.md first, load only what you need.\n' "$DASH"
    printf '     Audit: `phanes doc-check`. -->\n\n'
  } > "$full"
  echo "new-file: created $relPath (docs)"
  [ -f "$here/doc-index.sh" ] && sh "$here/doc-index.sh" >/dev/null 2>&1
else
  {
    printf '%s %s | %s\n' "$comment" "$module" "$description"
    printf '%s Soft size threshold: 500 LOC. Run `phanes loc-check` if uncertain.\n\n' "$comment"
  } > "$full"
  echo "new-file: created $relPath ($module)"
fi
exit 0
