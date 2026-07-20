#!/bin/sh
# phanes-template v3.0 module-list
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

cfg_arr() { # cfg_arr KEY FILE -> newline-separated values
  tr '\n' ' ' < "$2" 2>/dev/null \
    | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p" \
    | grep -o '"[^"]*"' | sed 's/"//g'
}

root=$(find_root) || { echo "module-list: .phanes/config.json not found from this directory" >&2; exit 1; }
mods=$(cfg_arr modules "$root/.phanes/config.json")
if [ -z "$mods" ]; then
  echo "(no modules configured)"
  exit 0
fi
printf '%s\n' "$mods"
exit 0
