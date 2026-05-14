# Phanes

**Phanes** is a bootstrap prompt for [Claude Code](https://claude.com/claude-code) that turns an empty (or chaotic) repository into a fully-wired, opinionated, multi-agent development environment in one command.

It is not a tool you install once and forget — it is a *re-runnable specification*. Each time you invoke `/phanes`, it re-surveys the project, upgrades existing sub-agents, fills in missing infrastructure, and increments a hidden run counter. The result is an agentic ecosystem that evolves with the codebase rather than rotting alongside it.

---

## What it does

When you run `/phanes` in a repo for the first time, the prompt drives Claude Code through a strict, multi-phase setup:

1. **Pre-flight** — verifies (and installs if missing) the MCP servers it relies on: `sequential-thinking`, `context7`, and `serena` (or `memory` as a fallback).
2. **Repository comprehension** — reads the README, source tree, configs, and CI to infer the project's *true* purpose, primary language, build system, and module boundaries. Extraneous directories (vendored deps, example packs, demo content) are filtered out.
3. **Project memory infrastructure** — scaffolds the substrate every sub-agent operates against:
   - `documentation/` — session summaries, plans, dated architecture snapshots, and a two-tier API registry (tier 1 generated, tier 2 curated annotations).
   - `tests/` — `unit/`, `integration/`, `e2e/`, `fixtures/`, `helpers/` with a verbatim README and the same `phanes new-file` header-stamp discipline as `src/`.
   - `.phanes/scripts/` — a script library that owns *all* mechanical rules: file creation with header stamps, line-of-code checks, registry regeneration, API diffs, module listing.
   - `.phanes/config.json` — confirmed module list, language, build system, hook prefs.
4. **Tiered workflow definition** — every task is triaged into T1 (single-file quick fix), T2 (single-module feature), or T3 (cross-cutting). Each tier loads a different amount of context and engages a different chain of agents. Promotion mid-task requires halting and asking the orchestrator.
5. **Sub-agent roster generation** — deeply-scoped, world-class personas written to `.claude/agents/*.md`:
   - **Architect/Designer** — the *sole writer* of tier 2 registry and architecture snapshots.
   - **api-monitor** — the *sole writer* of tier 1 registry; runs after every structural change.
   - **Critic agents** — produce numbered, ID-tagged audit reports.
   - **Executor** — applies approved diffs only; uses `phanes new-file` for every new file.
   - **Synthesizer/Arbiter** — consolidates parallel-perspective outputs into one unified plan.
   - Plus Analyzer, Planner, Validator, Optimizer, Integrator, Monitor, Cleaner variants tuned to your specific stack.
6. **Workflow codification** — `.claude/workflows/` is populated with YAML chains (Explore-Plan-Code-Commit, TDD, parallel-perspectives, etc.), and `CLAUDE.md` is updated so the primary agent knows how to triage, delegate, review, and end every T2/T3 chain with `api-monitor`.
7. **Bootstrap session summary** — `documentation/session-summaries/SS00001_phanes-bootstrap_<date>.md` records the install, the confirmed module list, the agent roster, and any deferred TODOs.

Re-runs detect the existing install and upgrade in place — agents, workflows, scripts, and READMEs are evaluated against the latest version of `phanes.md` and refreshed where they have drifted.

### Core principles enforced by Phanes

- **Procedure in scripts, judgment in prompts.** Any rule a script can enforce (LOC limits, header stamps, registry edits, API diffs) lives in `.phanes/scripts/`. Sub-agent prompts hold rules only for judgment work. Mechanical rules in prompts get forgotten under context pressure; scripts don't forget.
- **Single-writer per artifact.** Every registry tier, snapshot, and summary has exactly one writing agent. Many readers, one writer.
- **No direct code modification by sub-agents.** Coding agents emit a report containing a proposed diff; a Critic reviews it; the Executor applies it. The primary Claude Code agent does not edit code directly either — it orchestrates.
- **Context injection over context inheritance.** Sub-agents receive only the slice of context their tier permits. Pollution from sibling tasks is structurally impossible.

---

## How to install

Phanes is a single Markdown file (`phanes.md`) — installation just means putting it where Claude Code can invoke it as a slash command.

### Prerequisites

- [Claude Code](https://claude.com/claude-code) installed and authenticated.
- `git`, plus whichever language toolchain your project actually uses.
- Optional but strongly recommended: `uv` (for the `serena` MCP server). The Phase 0 pre-flight will install it for you if missing.

### Install as a user-level slash command (recommended)

This makes `/phanes` available in every repo you open.

**Linux / macOS:**

```bash
mkdir -p ~/.claude/commands
curl -L https://raw.githubusercontent.com/Aloim/phanes/main/phanes.md \
  -o ~/.claude/commands/phanes.md
```

**Windows (PowerShell):**

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.claude\commands" | Out-Null
Invoke-WebRequest `
  -Uri https://raw.githubusercontent.com/Aloim/phanes/main/phanes.md `
  -OutFile "$env:USERPROFILE\.claude\commands\phanes.md"
```

### Install per-project (alternative)

If you only want Phanes inside one repo and want it tracked in version control:

```bash
mkdir -p .claude/commands
curl -L https://raw.githubusercontent.com/Aloim/phanes/main/phanes.md \
  -o .claude/commands/phanes.md
```

### Run it

Open the target repository in Claude Code, then type:

```
/phanes
```

Optional arguments are forwarded through `$ARGUMENTS` and prioritized over the default plan, so you can steer the run:

```
/phanes focus on the api/ module; skip pre-commit hook install
```

The first run takes several minutes and will pause to confirm a few choices (module boundaries, hook install). Subsequent runs are faster — only diffs are written.

### What gets created on first run

```
documentation/        # session summaries, plans, architecture snapshots, registries
tests/                # unit, integration, e2e, fixtures, helpers
.phanes/              # scripts (new-file, regen-registry, api-diff, loc-check, ...) and config
.claude/agents/       # generated sub-agent definitions
.claude/workflows/    # codified multi-agent workflows (YAML)
.claude/template/     # report.md template used by every sub-agent
.claude/.phanes       # run counter (hidden)
CLAUDE.md             # primary-agent operating instructions, per-folder
CLAUDE.local.md       # live register of projects in motion (gitignored by convention)
```

`.claude/`, `.phanes/`, and other runtime artifacts are excluded by the default `.gitignore` shipped with this repo. Adjust to taste in your own project.

---

## License

Phanes is released under the **Creative Commons Attribution-NonCommercial 4.0 International** license (see [`LICENSE`](LICENSE)).

You are free to use, share, and adapt Phanes for any **non-commercial** purpose with attribution. Commercial use is not granted by this license — for commercial licensing terms, contact the author directly.

---

## Contributing

Issues and pull requests are welcome. Substantive changes to `phanes.md` should explain *which class of failure mode* the change closes — Phanes is a defensive document, and every clause is load-bearing.
