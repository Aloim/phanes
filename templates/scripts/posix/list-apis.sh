#!/bin/sh
# phanes-template v2.6.1 list-apis
# Prints the API baseline entries for one module to stdout, read from the machine baseline at
# .phanes/registry/<module>.json (produced by regen-registry). Sub-agents call this as a tool.

find_root() {
  d=$(pwd)
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -f "$d/.phanes/config.json" ] && { printf '%s' "$d"; return 0; }
    d=$(dirname "$d")
  done
  [ -f "/.phanes/config.json" ] && { printf '%s' "/"; return 0; }
  return 1
}

if [ "$#" -lt 1 ]; then
  echo "list-apis: usage: phanes list-apis <module>" >&2
  exit 1
fi
module=$1

root=$(find_root) || { echo "list-apis: .phanes/config.json not found from this directory" >&2; exit 1; }
baseline="$root/.phanes/registry/$module.json"
if [ ! -f "$baseline" ]; then
  echo "list-apis: no baseline for '$module'. Run: phanes regen-registry $module" >&2
  exit 1
fi
cat "$baseline"
exit 0
