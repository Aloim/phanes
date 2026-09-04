<!-- PhanesUpgrade v3.7.1, 2026-09-04. Redirect stub. Phanes is now PhanesLight, in a new repository.
     The upgrade prompt is PhanesLightUpgrade.md at github.com/Aloim/phaneslight. -->
# PhanesUpgrade is now PhanesLightUpgrade, at a new repository

**This file is a redirect, not an upgrade procedure.** Do not execute anything below as an upgrade run.

PhanesLight moved to **`Aloim/phaneslight`** at v3.6.1. This repository is being handed to a separate, more sophisticated Phanes project. v3.7.1 is published to both, as v3.6.1 was, so that existing installations can find it and migrate themselves.

**At v3.7.1 the manual prompt and the Claude Code plugin became separate products.** This file, and the upgrade it points at, serve the **manual** installation. A plugin installation is upgraded by its plugin manager instead, from the marketplace at `Aloim/phanesplugin`.

## If you are an agent that just fetched this file

1. Fetch `https://raw.githubusercontent.com/Aloim/phaneslight/main/PhanesLightUpgrade.md`.
2. Save it as `.claude/commands/phaneslightupgrade.md`.
3. Run that command instead. It performs the version upgrade, the name migration and the repository migration in one pass: it moves `.phanes/` to `.phaneslight/`, moves the `.claude/.phanes` marker, repoints the hook commands in `.claude/settings.json`, repoints every upstream URL at `Aloim/phaneslight`, renames the installed command files, and regenerates the five agents of the current lineup.
4. **STOP** until that command has been run. Do not attempt the migration by hand: the ordering matters, and the run-state marker must move last.

**Restart the session after the upgrade completes.** Hook configuration is snapshotted at session start, so the repointed hooks are inert until you do.
