#!/bin/sh
# phanes-template v3.4.0 new-file
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

cfg_arr() { # cfg_arr KEY FILE -> newline-separated values
  tr '\n' ' ' < "$2" 2>/dev/null \
    | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p" \
    | grep -o '"[^"]*"' | sed 's/"//g'
}

# cfg_key_bad KEY FILE -> true when KEY is present in the file but the extractors above cannot
# read its value. That combination is the signature of a malformed config. POSIX has no JSON
# parser (the helpers are regex extractors, which cannot fail), so an unreadable config would
# otherwise be indistinguishable from an unset key and would silently degrade to a default.
# An absent key is NOT bad: defaults are honest when the user simply did not set the option.
cfg_key_bad() {
  flat=$(tr '\n' ' ' < "$2" 2>/dev/null)
  printf '%s' "$flat" | grep -q "\"$1\"[[:space:]]*:" || return 1
  # Objects, numbers, booleans and null are well-formed JSON these extractors cannot read.
  # Unreadable is not the same as broken: leave those to the caller's default.
  printf '%s' "$flat" | grep -q "\"$1\"[[:space:]]*:[[:space:]]*[{0-9tfn-]" && return 1
  [ -n "$(cfg_str "$1" "$2")" ] && return 1
  [ -n "$(cfg_arr "$1" "$2")" ] && return 1
  printf '%s' "$flat" | grep -q "\"$1\"[[:space:]]*:[[:space:]]*\[[[:space:]]*\]" && return 1
  printf '%s' "$flat" | grep -q "\"$1\"[[:space:]]*:[[:space:]]*\"\"" && return 1
  return 0
}

normalize_path() { # normalize_path PATH -> lexically-normalized path (no filesystem access;
  # purely textual '.'/'..' collapsing, mirroring .NET's GetFullPath so a non-existent
  # target -- or one crossing a nonexistent directory -- can still be checked for
  # containment before anything is created on disk).
  set -f
  IFS=/; set -- $1; unset IFS
  set +f
  out=
  for seg in "$@"; do
    case "$seg" in
      ""|.) : ;;
      ..) out=${out%/*} ;;
      *) out="$out/$seg" ;;
    esac
  done
  [ -n "$out" ] && printf '%s' "$out" || printf '/'
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

# No honest default exists for any of the three values this config supplies: no default
# commentSyntax (a wrong one is a syntax error in the target language), no default docRoot
# (a docs write would land in the wrong tree), and no default module list (the unknown-module
# guard would silently switch off). Creating a file under a config that cannot be read is the
# one case where refusing beats degrading. Matches new-file.ps1's refuse-on-unparseable.
for k in commentSyntax docRoot modules; do
  if cfg_key_bad "$k" "$root/.phanes/config.json"; then
    echo "new-file: .phanes/config.json is malformed ('$k' present but unreadable). Refused." >&2
    exit 1
  fi
done

comment=$(cfg_str commentSyntax "$root/.phanes/config.json"); [ -z "$comment" ] && comment='//'

docRoot=$(cfg_str docRoot "$root/.phanes/config.json"); [ -z "$docRoot" ] && docRoot=documentation
# A trailing slash in docRoot would otherwise leak into every derived path and message
# (an empty basename, doubled separators, and absolute paths where relative ones belong).
while [ "${docRoot%/}" != "$docRoot" ]; do docRoot=${docRoot%/}; done
[ -z "$docRoot" ] && docRoot=documentation
mods=$(cfg_arr modules "$root/.phanes/config.json")
# Legal module names: any configured module, plus the two pseudo-modules (tests, docs).
# When no module list is configured (missing or empty), there is nothing to validate a
# source module name against, so the guard is skipped entirely rather than refusing every
# non-pseudo module. tests/docs are always legal regardless.
if [ -n "$mods" ]; then
  legal="tests
docs
$mods"
  if ! printf '%s\n' "$legal" | grep -qxF "$module"; then
    echo "new-file: unknown module '$module'. Legal values: $(printf '%s' "$legal" | tr '\n' ',' | sed 's/,$//; s/,/, /g'). Refused." >&2
    exit 1
  fi
fi

case "$relPath" in
  /*) full=$relPath ;;
  *) full="$root/$relPath" ;;
esac

# Normalize ONCE, here, and use this single value for every later step: the containment
# check, the existence check, mkdir -p, and both write sites (docs and non-docs alike). A
# prior revision normalized only a throwaway copy for the containment gate while mkdir -p
# and the write still used the raw, un-normalized $full. That let a relPath like
# "documentation/../secrets/../documentation/notes/ok.md" pass the gate (it lexically lands
# back inside docRoot) while mkdir -p, which walks its argument left to right materializing
# each ancestor as it goes, still created a real "secrets/" directory outside docRoot before
# backing out of it again. Normalizing $full itself removes the '..' before mkdir ever sees
# it, so there is nothing left to walk through. This also protects the non-docs branch,
# which has no containment guard at all but ran the same raw-path mkdir -p.
full=$(normalize_path "$full")

# Containment check, every target: must live under the repository root. Without this a source
# or tests target could escape the project entirely (`new-file core ../outside.c` wrote a real
# file next to the repository), which the docs branch already refused but the non-docs branch
# did not. Compared after normalization, so '..' segments are resolved rather than matched.
case "$full" in
  "$root"/*) : ;;
  *) # Name the corrected path: the target lexically normalized, which collapses the '..'
     # segments and leaves the in-repository path the user most likely meant.
     corrected=$(normalize_path "$relPath")
     corrected=${corrected#/}
     echo "new-file: target must live inside the repository root. Got '$relPath', which resolves outside it. Did you mean '$corrected'? Refused." >&2
     exit 1 ;;
esac

# Containment check, docs only: must live under docRoot. A literal prefix match on the raw
# path would be defeated by a relPath containing '..' (e.g. "documentation/../secrets/x.md"
# textually starts with "$root/$docRoot/" even though it resolves outside it); both sides are
# normalized so the comparison reflects where the path actually points.
if [ "$module" = "docs" ]; then
  docBase=$(normalize_path "$root/$docRoot")
  case "$full" in
    "$docBase"/*) : ;;
    *) echo "new-file: docs target must live under '$docRoot/'. Got '$relPath'. Did you mean '$docRoot/$relPath'? Refused." >&2
       exit 1 ;;
  esac
fi

# What to show the user: the normalized location relative to $root, i.e. where the bytes
# actually land. Identical to $relPath verbatim whenever relPath had no '.'/'..' segments to
# collapse (the overwhelming common case); the raw input is kept in the containment-refusal
# message above since that message is about what the user typed, not where anything landed.
displayPath=$full
case "$displayPath" in
  "$root"/*) displayPath=${displayPath#"$root"/} ;;
esac

if [ -e "$full" ]; then
  echo "new-file: refuses to overwrite existing file: $displayPath" >&2
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
    # Exactly one trailing LF after the header block, matching new-file.ps1 byte for byte.
    printf '     Audit: `phanes doc-check`. -->\n'
  } > "$full"
  echo "new-file: created $displayPath (docs)"
  [ -f "$here/doc-index.sh" ] && sh "$here/doc-index.sh" >/dev/null 2>&1
else
  {
    printf '%s %s | %s\n' "$comment" "$module" "$description"
    printf '%s Soft size threshold: 500 LOC. Run `phanes loc-check` if uncertain.\n\n' "$comment"
  } > "$full"
  echo "new-file: created $displayPath ($module)"
fi
exit 0
