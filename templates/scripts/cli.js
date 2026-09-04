#!/usr/bin/env node
// phaneslight-template v3.7.1 cli
// Cross-shell entry point: `node .phaneslight/scripts/cli.js <subcommand> [args]` resolves identically
// in PowerShell, cmd, and Git Bash, so agents never depend on PATH or a shell-specific launcher.
// It forwards to the platform dispatcher sibling (phaneslight.ps1 on Windows, the POSIX `phaneslight`
// elsewhere), which owns all subcommand routing: one source of truth, no duplicated dispatch logic.
'use strict';

const { spawnSync } = require('child_process');
const path = require('path');

const here = __dirname;
const args = process.argv.slice(2);
const isWindows = process.platform === 'win32';

let cmd;
let cmdArgs;
if (isWindows) {
  cmd = 'powershell';
  cmdArgs = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(here, 'phaneslight.ps1'), ...args];
} else {
  cmd = 'sh';
  cmdArgs = [path.join(here, 'phaneslight'), ...args];
}

const result = spawnSync(cmd, cmdArgs, { stdio: 'inherit' });
if (result.error) {
  process.stderr.write('cli.js: failed to launch the phaneslight dispatcher (' + result.error.message + ')\n');
  process.exit(1);
}
process.exit(result.status === null ? 1 : result.status);
