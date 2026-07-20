<!-- DOC | The install checklist Phanes works through when it fetches the v3.0 script template library. -->
<!-- phanes-template v3.0 CHECKLIST -->

# Template install checklist (v3.0)

Phanes works through this list during Phase 2.5 Step 4 when it fetches the script template library, and mirrors the outcome of every item into the bootstrap session summary. This file ships pinned to the template version, so the checklist and the scripts can never fall out of step.

Provenance note: the scripts in this library take no path substitution. Each script finds the project by walking up from the current directory until it sees `.phanes/config.json`, and every path it uses is relative to that root. There is nothing to adapt, which is the whole point: a value that is never substituted is a value that can never be substituted wrong.

## Items

1. Platform detected. Only the matching variant set is fetched and installed; the other platform variant is not written into the project. The cross-platform `cli.js` dispatcher (v3.0) is fetched and installed on **every** platform (it is in both the `windows` and `posix` arrays of the manifest's `phanes` dispatcher entry).
2. Every fetched file passes the sanity check before it lands: the stamp comment `# phanes-template v3.0 <name>` (or `rem phanes-template v3.0 <name>` for the `.cmd` shim) appears within the first two lines, after the shebang on POSIX or after `@echo off` in the `.cmd` shim. A 404 body or an HTML error page must never be written into `.phanes/scripts/`.
3. Manifest version equals this run's own line 1 stamp version. On a mismatch, treat it as a fetch failure and fall back to generating the scripts from the phanes.md Step 4 and Step 4b specifications.
4. Files install into `.phanes/scripts/` keeping their variant extension (`.ps1` and `.cmd` on Windows, `.sh` on POSIX; `cli.js` on both). The platform dispatcher maps `<name>` to the platform file; the cross-platform `cli.js` forwards to it, so agents invoke `node .phanes/scripts/cli.js <name>` in any shell. The settings fragment references the filenames that carry the extension.
5. POSIX only: the executable bit is set on every installed script.
6. `.phanes/config.json` is written before the first script runs. Scripts read it at invocation, so a missing config is each script's defined error case, reported cleanly, not a crash.
7. Smoke run inside the project via the cross-shell entry: `node .phanes/scripts/cli.js module-list` and `node .phanes/scripts/cli.js register-check` both exit 0 (proving `cli.js` forwards to the platform dispatcher). Each hook script, fed a minimal tool call JSON on stdin, exits 0 on the pass through case, and each also exits 0 at once when run with no piped input (stdin is a terminal), never blocking.
8. The platform settings fragment is merged into `.claude/settings.json`. Existing hooks are preserved, never overwritten. The Step 4b read back verification then passes: every Phanes hook command contains `.phanes/scripts/` and contains no drive letter and no leading slash.
9. The `config.json` `templates` block is written: `{ "version": "3.0", "source": "fetched" }`, or `"generated"` when the fallback path produced the scripts.
10. Any script genuinely edited for this project is recorded in the session summary with the reason. The default is zero edits.
