#!/bin/sh
# phanes-template v3.4.0 doc-check
# Scans the documentation tree (archive/ excluded) for living documents over the 500-line ceiling
# or missing a DOC header line, for folders holding docs but no _index.md, and for indexes older
# than their newest sibling. Prints offenders with line counts. Frozen artifact classes (session
# summaries, dated architecture snapshot folders, archive/) are never flagged for content
# conformance. Advisory: always exits 0.
CEILING=500

find_root() {
  d=$(pwd)
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

cfg_arr() { # cfg_arr KEY FILE -> newline-separated values
  tr '\n' ' ' < "$2" 2>/dev/null \
    | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p" \
    | grep -o '"[^"]*"' | sed 's/"//g'
}

norm_entries() { # norm_entries DOCROOT  (reads raw entries on stdin)
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    e=$(printf '%s' "$e" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$e" ] || continue
    e=$(printf '%s' "$e" | tr '\\' '/' | sed 's#^/*##; s#/*$##')
    case "$e" in
      "$1"/*) e=${e#"$1"/} ;;
    esac
    [ -n "$e" ] && printf '%s\n' "$e"
  done
}

is_listed() { # is_listed REL LIST
  _rel=$1
  printf '%s\n' "$2" | while IFS= read -r e; do
    [ -n "$e" ] || continue
    case "$e" in
      */*) case "$_rel" in "$e"|"$e"/*) echo hit ;; esac ;;
      *)   case "/$_rel/" in *"/$e/"*) echo hit ;; esac ;;
    esac
  done | grep -q hit
}

root=$(find_root) || { echo "doc-check: .phanes/config.json not found from this directory" >&2; exit 0; }
docRoot=$(cfg_str docRoot "$root/.phanes/config.json"); [ -z "$docRoot" ] && docRoot=documentation
# A trailing slash in docRoot would otherwise leak into every derived path and message
# (an empty basename, doubled separators, and absolute paths where relative ones belong).
while [ "${docRoot%/}" != "$docRoot" ]; do docRoot=${docRoot%/}; done
[ -z "$docRoot" ] && docRoot=documentation
docPath="$root/$docRoot"
[ -d "$docPath" ] || { echo "doc-check: no documentation tree"; exit 0; }

frozenlist=$(cfg_arr frozen_classes "$root/.phanes/config.json" | norm_entries "$docRoot")
exclusions=$(cfg_arr index_exclusions "$root/.phanes/config.json" | norm_entries "$docRoot")

is_frozen() { # is_frozen REL
  rel=$1
  case "/$rel/" in
    */archive/*) return 0 ;;
    */session-summaries/*) return 0 ;;
  esac
  # dated snapshot folder segment (YYYY-MM-DD...)
  printf '%s' "$rel" | grep -qE '(^|/)[0-9]{4}-[0-9]{2}-[0-9]{2}' && return 0
  if [ -n "$frozenlist" ]; then
    dir=$(dirname "$rel")
    [ "$dir" = "." ] && dir=""
    if [ -n "$dir" ] && is_listed "$dir" "$frozenlist"; then return 0; fi
  fi
  return 1
}

offenders=$(mktemp)
echo 0 > "$offenders"
bump() { n=$(cat "$offenders"); echo $((n + 1)) > "$offenders"; }

# 1. File-level checks on living .md documents.
find "$docPath" -type f -name '*.md' ! -path '*/archive/*' | while IFS= read -r f; do
  base=$(basename "$f")
  [ "$base" = "_index.md" ] && continue
  [ "$base" = "_index_archive.md" ] && continue
  rel=${f#"$docPath"/}
  is_frozen "$rel" && continue

  lines=$(awk 'END{print NR}' "$f" 2>/dev/null | tr -d ' ')
  if [ -n "$lines" ] && [ "$lines" -gt "$CEILING" ]; then
    echo "OVER-CEILING: $rel ($lines lines)"; bump
  fi
  if ! head -n 8 "$f" 2>/dev/null | grep -qE '<!--[[:space:]]*DOC[[:space:]]*\|'; then
    echo "NO-DOC-HEADER: $rel"; bump
  fi
done

# 2. Folder-level checks: missing or stale _index.md.
find "$docPath" -type d ! -path '*/archive' ! -path '*/archive/*' | while IFS= read -r folder; do
  # any non-index md children?
  has=$(ls "$folder" 2>/dev/null | grep -E '\.md$' | grep -vE '^_index\.md$|^_index_archive\.md$' | grep -c .)
  [ "$has" -eq 0 ] && continue
  rel=${folder#"$root"/}
  drel=${folder#"$docPath"}
  drel=$(printf '%s' "$drel" | sed 's#^/*##')
  if [ -n "$exclusions" ] && [ -n "$drel" ] && is_listed "$drel" "$exclusions"; then continue; fi
  if [ ! -f "$folder/_index.md" ]; then
    echo "NO-INDEX: $rel/"; bump
    continue
  fi
  # stale: any child .md newer than the index?
  newer=$(find "$folder" -maxdepth 1 -type f -name '*.md' ! -name '_index.md' ! -name '_index_archive.md' -newer "$folder/_index.md" 2>/dev/null | grep -c .)
  if [ "$newer" -gt 0 ]; then
    echo "STALE-INDEX: $rel/ (run phanes doc-index)"; bump
  fi
done

n=$(cat "$offenders"); rm -f "$offenders"
[ "$n" -eq 0 ] && echo "doc-check: OK"
exit 0
