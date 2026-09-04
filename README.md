# PhanesLight has moved. This is the old repository.

> **You are at `Aloim/phanes`. PhanesLight is not developed here any more.**
>
> | What you want | Where it is |
> | --- | --- |
> | **The manual, single-file prompt** (`phaneslight.md`, fetched into `.claude/commands/`) | **[`Aloim/phaneslight`](https://github.com/Aloim/phaneslight)** |
> | **The Claude Code plugin** (`/plugin marketplace add`) | **[`Aloim/phaneslightplugin`](https://github.com/Aloim/phaneslightplugin)** |
>
> **This repository is being handed to a different and larger project, which inherits the Phanes name.** PhanesLight is a bootstrap prompt, it is staying one, and it moved aside rather than being absorbed. Do not expect what is here to keep describing PhanesLight indefinitely.

---

## Why there are still current files here

`phaneslight.md`, `PhanesLightUpgrade.md` and `templates/` in this repository are **real and current at v3.7.1**, not stale copies. They are published here for one reason: **an installation from v3.6.1 or earlier polls this repository's URLs to discover new releases.** If nothing new ever appeared here again, those installations would sit on an old version forever and never learn where to look instead.

So v3.7.1 was published to both repositories, exactly as v3.6.1 was. **Upgrading is what gets you off this repository:** `/phaneslightupgrade` rewrites every distribution URL in your installation to point at `Aloim/phaneslight`, and from then on your version checks go to the right place.

**If you are reading this as a human choosing where to start, start at [`Aloim/phaneslight`](https://github.com/Aloim/phaneslight) instead.** Everything below is for people who already have an older PhanesLight installed.

## If you have an older PhanesLight installed

**Linux / macOS:**

```bash
mkdir -p ~/.claude/commands
curl -L https://raw.githubusercontent.com/Aloim/phaneslight/main/PhanesLightUpgrade.md \
  -o ~/.claude/commands/phaneslightupgrade.md
```

**Windows (PowerShell):**

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.claude\commands" | Out-Null
Invoke-WebRequest `
  -Uri https://raw.githubusercontent.com/Aloim/phaneslight/main/PhanesLightUpgrade.md `
  -OutFile "$env:USERPROFILE\.claude\commands\phaneslightupgrade.md"
```

Then open your project, make sure `git status` is clean, and run **`/phaneslightupgrade`** on Opus 5 at `high` effort. It detects your installed version, plans the jump from the changelog, migrates the structure on a branch you review and merge yourself, and repoints your installation at the new repository. Restart your session afterwards; hook configuration is snapshotted at session start.

Section 0 of [`PhanesLightUpgrade.md`](PhanesLightUpgrade.md) walks through this in full, including the older `/phanes` to `/phaneslight` rename if you are coming from v3.4.1 or earlier.

## What changed in v3.7.1

Two rules in the agent lineup, and a repository split.

- **The haiku tier never writes code.** `<slug>-mechanic` does mechanical non-code work only, and escalates findings from LOW upward rather than MED, because it can no longer absorb even a trivial fix itself.
- **The reviewer plans first.** On a planned launch the orchestrator's first act is a reviewer dispatch against the plan, before any execution step, and the reviewer may write plan files. The old flat claim that it "never writes" is corrected to "never writes code".
- **The plugin and the manual prompt are separate products at separate repositories**, as the table above says. The plugin was built for the Claude community marketplace; publishing it into `Aloim/phaneslight` at v3.7.0 briefly retired the manual install path, which was never the intent and is reverted.

Full detail lives with the project: [`Changelog.md`](https://github.com/Aloim/phaneslight/blob/main/Changelog.md) and [`README.md`](https://github.com/Aloim/phaneslight/blob/main/README.md) at `Aloim/phaneslight`.

## The last pre-ladder release

v3.6.0 replaced the review chain with a model-tier escalation ladder, which is a real change in how work gets verified. [`older version/v3.4.1/`](older%20version/v3.4.1/) holds the complete last pre-ladder distribution, prompt and upgrade prompt and README and changelog and template library, if you would rather stay on that shape.

## License

See [`LICENSE`](LICENSE). Issues and pull requests belong at [`Aloim/phaneslight`](https://github.com/Aloim/phaneslight), not here.
