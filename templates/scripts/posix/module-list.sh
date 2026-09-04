#!/bin/sh
# phaneslight-template v3.7.1 module-list
# Prints the configured module list, one per line, read from .phaneslight/config.json.
# With --all, additionally prints the two pseudo-modules `new-file` accepts (tests, docs), which
# the config never carries. Default output is UNCHANGED and stays exactly the configured list:
# `update-preflight`'s modules sensor compares it line-for-line against config.modules, so a
# pseudo-module on the default path would read as a permanent drift verdict.

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

root=$(find_root) || { echo "module-list: .phaneslight/config.json not found from this directory" >&2; exit 1; }
# Unlike new-file (where "no restriction" is a coherent fallback), there is no honest default
# module list to print: "(no modules configured)" would claim the project has none, when the
# truth is the config could not be read. Report the parse failure and refuse, matching Windows.
if cfg_key_bad modules "$root/.phaneslight/config.json"; then
  echo "module-list: .phaneslight/config.json is malformed, cannot list modules" >&2
  exit 1
fi
showAll=0
[ "$1" = "--all" ] && showAll=1

mods=$(cfg_arr modules "$root/.phaneslight/config.json")
if [ -z "$mods" ]; then
  echo "(no modules configured)"
else
  printf '%s\n' "$mods"
fi
if [ "$showAll" -eq 1 ]; then
  # The two names `new-file` accepts that no config lists. They live here so the answer to "what
  # may I pass as <module>?" is reachable from the command that claims to answer it, rather than
  # only from new-file's refusal message.
  echo "tests"
  echo "docs"
fi
exit 0
