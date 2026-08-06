#!/bin/sh
# phanes-template v3.4.0 module-list
# Prints the configured module list, one per line, read from .phanes/config.json.

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

# cfg_key_bad KEY FILE -> true when KEY is present in the file but these extractors cannot read
# its value. That combination is the signature of a malformed config. POSIX has no JSON parser
# (the helpers above are regex extractors, which cannot fail), so an unreadable config would
# otherwise be indistinguishable from an unset key and would silently degrade to a default.
# Windows refuses outright via ConvertFrom-Json; this restores the same verdict here.
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

root=$(find_root) || { echo "module-list: .phanes/config.json not found from this directory" >&2; exit 1; }
# Unlike new-file (where "no restriction" is a coherent fallback), there is no honest default
# module list to print: "(no modules configured)" would claim the project has none, when the
# truth is the config could not be read. Report the parse failure and refuse, matching Windows.
if cfg_key_bad modules "$root/.phanes/config.json"; then
  echo "module-list: .phanes/config.json is malformed, cannot list modules" >&2
  exit 1
fi
mods=$(cfg_arr modules "$root/.phanes/config.json")
if [ -z "$mods" ]; then
  echo "(no modules configured)"
  exit 0
fi
printf '%s\n' "$mods"
exit 0
