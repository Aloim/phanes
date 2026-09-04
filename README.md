# PhanesLight

> ## ⚠️ v3.7.1 — This repository is the MANUAL install again
>
> **The plugin release that landed here at v3.7.0 was a mistake, and it is reverted.** The plugin was built for the **Claude community marketplace** and was never meant to replace this repository's contents. Publishing it here retired the manual install path as a side effect, which was not the intent. It has been moved to its own home at [`github.com/Aloim/phanesplugin`](https://github.com/Aloim/phanesplugin), and **this repository is the manual, single-file PhanesLight, as it was through v3.6.1.**
>
> **If you are on the manual install (you fetched `phaneslight.md` into `.claude/commands/`), nothing was ever taken away from you.** v3.6.2 announced that your path was closing. Disregard it. Fetch v3.7.1 and carry on; see [Upgrading an older install](#upgrading-an-older-install).
>
> **If you installed the plugin from this repository in the meantime**, the marketplace here no longer resolves. Either re-add it from `Aloim/phanesplugin`, or move to the manual install; both routes are written out under [Coming from the plugin](#coming-from-the-plugin).
>
> **There is no manual v3.7.0**, because v3.7.0 was the plugin. A manual install goes from v3.6.1 straight to v3.7.1.
>
> **Two rules changed in the lineup.** The haiku tier, `<slug>-mechanic`, no longer writes code of any kind, and escalates from LOW upward because it can no longer absorb even a trivial fix itself. And `<slug>-reviewer` now reviews your plan before the run starts, and may write plan files; the old flat claim that it "never writes" was always contradicted by its own job and is corrected to "never writes code".
>
> **v3.7.1 is published to BOTH `Aloim/phaneslight` and the legacy `Aloim/phanes`,** as v3.6.1 was, so an install still checking the old URL sees it once and repoints itself.
>
> **What to do:** run `/phaneslightupgrade`. **Restart your session afterwards**; hooks are snapshotted at session start. Full accounting in [`Changelog.md`](Changelog.md).
>
> <details><summary>The v3.6.1 notice, kept for installs upgrading from v3.4.1 or earlier</summary>
>
> **v3.6.1 was a major release. It renames the project, moves the repository, and changes how runs handle their own durability.**
>
> **The project is now PhanesLight.** `phanes.md` → `phaneslight.md`, `/phanes` → `/phaneslight`, `/phanesupgrade` → `/phaneslightupgrade`, and project state moved from `.phanes/` to `.phaneslight/`.
>
> **The repository has moved to [`github.com/Aloim/phaneslight`](https://github.com/Aloim/phaneslight).** This is the new home. Update your bookmarks and any scripted fetch.
>
> **Why both:** a **more sophisticated Phanes project** is coming, and it will inherit the `Aloim/phanes` repository and the Phanes name. PhanesLight is not becoming that tool. It is a bootstrap prompt, it is staying one, and it is getting out of the way of the larger project rather than being absorbed into it. The two will ship side by side.
>
> **v3.6.1 is published to BOTH repositories,** deliberately and once. Installations that still check the old URL will see this release, offer you the upgrade, and repoint themselves at the new repository as part of it. **Later versions ship to `Aloim/phaneslight`**, and v3.7.1 was published to both again for the same reason. If you skip this upgrade, your install stops seeing releases and will eventually be checking a repository that holds a different product.
>
> **The plugin now lives at [`Aloim/phanesplugin`](https://github.com/Aloim/phanesplugin)**: `/plugin marketplace add Aloim/phanesplugin`, then `/plugin install phaneslight@phaneslight`.
>
> **Prefer the old workflow? It is kept whole.** v3.6.0 replaced the review chain with an escalation ladder, which is a real change in how work gets verified, so [`older version/v3.4.1/`](older%20version/v3.4.1/) now holds the **complete** last pre-ladder distribution — prompt, upgrade prompt, README, changelog and full template library — rather than a bare prompt file. Every earlier version has been removed from that folder. Read both and pick; the choice is yours, not ours.
>
> **What to do:** run `/phaneslightupgrade`. It performs the version upgrade, the name migration and the repository migration in one pass, on a branch you review and merge yourself. See [Upgrading an older install](#upgrading-an-older-install). **Restart your session afterwards**; hooks are snapshotted at session start.
>
> </details>
>
> Beyond the migration, v3.6.1 fixed thirteen defects found in production use. The headline ones: sub-agent returns are now persisted to disk before the next dispatch, so a context ceiling or an API crash is a bookmark rather than a data-loss event; a pinned model that runs out of quota degrades down a documented ladder instead of halting the tier; and owner-authorized deviations from a generated directive survive regeneration in a new `pinned:project` block. Full accounting in [`Changelog.md`](Changelog.md).

---

**PhanesLight** is a bootstrap prompt for [Claude Code](https://claude.com/claude-code). One command turns an empty or chaotic repository into a fully wired, opinionated, multi-agent development environment.

It is not install-once-and-forget. It is a living specification you re-run: each `/phaneslight` surveys the project again, upgrades the sub-agents, fills in missing infrastructure, and bumps a run counter. The result is an agentic team that grows with your codebase instead of rotting beside it.

**The prompt is one file.** You install a single Markdown file as your `/phaneslight` command. The scripts, hooks, agents and documents it sets up are created inside your repository during the run: language-independent scripts and prompt templates are fetched as tested templates pinned to the prompt's own version, everything else is generated. If the fetch fails, the run generates those too, so an offline install is still complete.

**Run `/phaneslight` and `/phaneslightupgrade` on Opus 5 at `high` effort** (`claude --model opus --effort high`). Those runs build and maintain the whole setup, so they are the ones worth spending on. The team they install is designed to run on Sonnet 5 afterwards, which is what keeps a Max 5x plan viable. See [Which model for which run](#which-model-for-which-run).

**Modular by design.** The core stays one file on purpose; anything beyond bootstrapping ships as a separate [companion tool](#companion-tools) that works standalone in any repository and snaps into PhanesLight's structures when it finds them.

| Your situation | What to use |
| --- | --- |
| Fresh project, or one with no PhanesLight yet | `phaneslight.md` → `/phaneslight`. Re-running it also keeps a current install up to date. |
| A project carrying an older PhanesLight or Phanes (any version) | `PhanesLightUpgrade.md` → `/phaneslightupgrade`. Refreshes your command, then upgrades the whole structure on a dedicated branch behind an evidence-verified checklist. Accumulated knowledge is preserved, never rewritten. |

**Contents** · [What it does](#what-it-does) · [Which model for which run](#which-model-for-which-run) · [How to use](#how-to-use) · [Core principles](#core-principles-enforced-by-phaneslight) · [From zero](#for-inexperienced-users-step-by-step-from-zero) · [How to install](#how-to-install) · [Upgrading](#upgrading-an-older-install) · [Companion tools](#companion-tools) · [Third-party enhancements](#recommended-third-party-enhancements) · [Version](#version) · [License](#license) · [Contributing](#contributing)

---

## What it does

**1. Pre-flight.** The run checks itself first: it fetches the published `phaneslight.md` and compares version stamps, offering the upgrade if a newer one has shipped. It then installs the four MCP servers it benefits from, and only four, because every tool schema costs context in every session and each server has to remove more context than its schema costs:

- **`context7`** for live library documentation, on demand.
- **`deepwiki`** for digest answers about GitHub dependencies, so agents never pull dependency source into context.
- **`semble`** for hybrid code search, so an agent finds the exact snippet instead of grepping a module and reading whole files.
- **`serena`** for symbol-level navigation. **(v3.6.1)** Granted only where its language servers actually cover your stack; on a PowerShell, shell or Markdown project it degrades to file search that `semble` already does better, so it is skipped and the reason recorded.

These are enhancements, not dependencies: a failed install becomes a TODO and the run continues degraded. The pre-flight then detects your platform, runs a capability census probing each server for real reachability, and asks you once which capabilities it may build policy around. Nothing you installed is ever changed or removed. A ledger at `.phaneslight/run-progress` lets a session that dies or compacts mid-bootstrap resume from the last completed phase.

**2. Repository comprehension.** It reads the README, source tree, configs and CI to work out the project's purpose, primary language, build system and module boundaries, filtering out vendored dependencies, example packs and demo content.

**3. Project memory infrastructure.** The substrate every sub-agent works against:

- **`documentation/`** — session summaries, plans, dated architecture snapshots, and a curated API registry capturing what code search cannot see (deprecations, contracts beyond type signatures, anti-patterns). Every folder carries a **generated `_index.md`**, so agents find knowledge by descending indexes at a few hundred tokens a hop instead of scanning the tree. **(v3.6.1)** Indexes are ordered by filename rather than modification time, so a sequenced folder's newest entry is its first line and editing an old document no longer reorders the whole index. Files respect a 500-line soft ceiling.
- **`tests/`** — `unit/`, `integration/`, `e2e/`, `fixtures/`, `helpers/`, with the same header-stamp discipline `src/` uses.
- **`.phaneslight/scripts/`** — the library that owns every mechanical rule: stamped file creation, line counts, documentation audit, index regeneration, hot-file character budgets, API baseline regeneration and diffing. Each script finds the project by walking up to `.phaneslight/config.json` and uses only root-relative paths, so a hook can never be wired to the wrong tree. **On Windows, ten more commands** mechanize what a run previously did by hand — `preflight`, `update-preflight`, `install-templates`, `scaffold`, `manifest-write`, `ledger`, `census-diff`, `hook-ledger-status`, `repo-manifest`, `batch-apply` — turning thirty to fifty tool calls into one digest and letting a re-run measure what moved before rebuilding. **Every one observes or writes what it is told to and decides nothing.** On POSIX they are refused by name rather than faked, and the manual flow is unchanged.
- **`.phaneslight/returns/`** — **(v3.6.1)** durable sub-agent returns, written before the next dispatch. See [Core principles](#core-principles-enforced-by-phaneslight).
- **`.claude/settings.json`** — hooks that enforce rules at the harness layer: a blocking guard denying any unstamped new file, an advisory check running size and documentation audits on every write. Prompts forget under context pressure. Hooks cannot.

**4. Tiered workflows.** Every task is sorted into **T1** (single-file fix), **T2** (feature inside one module) or **T3** (cross-module). Each tier loads different context and engages a different chain, but **disclosure is universal**: even a T1 fix is named in a report, and closure reconciles what landed against what was intended at every close. Only the paper trail scales with tier. A task that outgrows its tier mid-flight stops and asks for promotion.

**5. The roster: five agents, always the same five,** named by model tier. Domain expertise is composed per task and injected into the spawn prompt rather than baked into an agent file, so the always-on context cost is fixed rather than growing with the project.

| Agent | Model | What it is for |
| --- | --- | --- |
| `<slug>-orchestrator` | Opus 5 | Authors, applies and dispatches. Main executor as well as orchestrator. |
| `<slug>-reviewer` | Fable 5.1 | HIGH and CRIT findings, **and the plan review at every planned launch (v3.7.1)**. Writes a fix plan and hands it back; never applies. Writes **plan files and review artifacts** and names every one; never code. |
| `<slug>-worker` | Sonnet 5 | The default working tier for authored code, within a dispatched scope, disclosing every edit. |
| `<slug>-mechanic` | Haiku 4.5 | Mechanical **non-code** transforms, doc indexing, archive condensation, fetch-and-digest retrieval. **Never writes code of any kind (v3.7.1)**, and escalates from LOW upward because it cannot fix anything itself. |
| `<slug>-closure` | Sonnet 5 | Independent re-derivation at every close. Writes no code; its output is a flag, never a fix. |

The expensive tier is affordable because it is rare: worker and mechanic escalate to whoever spawned them, the orchestrator handles MED itself, and only an undeferred HIGH or CRIT reaches Fable. **(v3.6.1)** A pinned model that is unreachable is retried with backoff, then substituted down a documented ladder with the substitution recorded, rather than halting its tier.

**6. Workflow codification.** YAML files in `.claude/workflows/` codify task *sequences*: what happens in what order, which scripts run when. Who spawns whom is fixed in the prompt, not per project. **(v3.6.1)** At least one workflow must cover **recurring maintenance** (backlog triage, conformance audit, snapshot refresh) rather than change-type work alone, with an explicit trigger and the understanding that finding nothing is a successful run.

**7. Bootstrap session summary.** `documentation/session-summaries/SS00001_phaneslight-bootstrap_<date>.md` records the install, module list, roster and deferred TODOs.

> **After the first run, restart your Claude Code session.** Hook configuration is snapshotted at session start, so the enforcement hooks arm on the next one.

### How the five work together

Where work enters depends on its size: a single task or a short plan is triaged and run directly; a plan of five steps or more engages `<slug>-orchestrator`, which walks the plan and holds the run's context so your own session does not.

Only two agents can spawn: the orchestrator and the reviewer. That is what
bounds the whole system to three levels, and it is why the picture below is
this shape rather than an open mesh.

**Work travels down with a brief. Findings travel up by severity.**

```text
                                  YOU
                                   │
                     a task, or a plan of steps
                                   ▼
   ╭─────────────────────────────────────────────────────────────────╮
   │ <slug>-orchestrator                                       opus  │
   │ the only agent that both decides and applies                    │
   │ writes anywhere · spawns all four · holds the run's context     │
   ╰──┬──────────────┬───────────────┬───────────────────┬───────────╯
      │ a composed   │ a composed    │ a HIGH or CRIT    │ "this step is
      │ brief: scope,│ brief: fetch  │ it chose not      │  applied.
      │ conventions, │ this, digest  │ to defer          │  verify it"
      │ acceptance   │ it            │                   │
      ▼              ▼               ▼                   ▼
 ╭──────────╮  ╭───────────╮  ╭─────────────╮  ╭────────────────────╮
 │ -worker  │  │ -mechanic │  │  -reviewer  │  │      -closure      │
 │  sonnet  │  │   haiku   │  │    fable    │  │       sonnet       │
 ├──────────┤  ├───────────┤  ├─────────────┤  ├────────────────────┤
 │ authored │  │ mechanical│  │ plans the   │  │ re-derives from    │
 │ code,    │  │ transforms│  │ fix and     │  │ source: registry,  │
 │ inside   │  │ and bulky │  │ hands it    │  │ api-diff, and it   │
 │ its own  │  │ retrieval │  │ back        │  │ re-runs the build  │
 │ scope    │  │           │  │             │  │ and tests itself   │
 ├──────────┤  ├───────────┤  ├─────────────┤  ├────────────────────┤
 │ writes   │  │ writes NO │  │ writes      │  │ writes no code,    │
 │ in scope │  │ code, ever│  │ PLANS only  │  │ ever               │
 ╰────┬─────╯  ╰─────┬─────╯  ╰──────┬───┬──╯  ╰─────────┬──────────╯
      │              │               │   │               │
      │              │               │   ╰── may spawn -worker and -mechanic
      │              │               │       for its own cheap sub-tasks
      │              │               │                   │
      ╰──────────────┴───────────────┴───────────────────╯
                               │
                               ▼
            every return goes to ITS OWN spawner, never past it,
            and is written to .phaneslight/returns/ BEFORE the
            next dispatch goes out

   what comes back
     -worker    the code, and EVERY edit it made, named in its report
     -mechanic  a digest with file:line refs and no judgment of its own
     -reviewer  a fix PLAN. Never a diff, never an edit.
     -closure   FLAGS graded on the ladder: API drift, the build and
                tests it re-ran itself, doc breaches. Never a fix.
```

A worker spawned by the reviewer reports to the **reviewer**, not to the
orchestrator. Nobody reaches past the agent that dispatched them, and nobody is
ever forked: every spawn carries a self-contained brief rather than inheriting a
parent's context.

### What happens to a finding

Any agent can raise one. There is one ladder, and only the top three rungs
create work anywhere:

```text
   CRIT  ·  HIGH  ·  MED   ──►  create work
   LOW   ·  INFO           ──►  create none, ever. They stay in the report,
                                are never rehomed, never become follow-ups.

   -worker finds something MED or above
   -mechanic finds something LOW or above  (v3.7.1: it may not write
        │                                   code, so it cannot absorb
        │                                   even a trivial fix itself)
        │   stops immediately. Does NOT attempt the fix.
        ▼
   its own spawner
        │
        ▼
   -orchestrator, now holding a HIGH or CRIT
        │
        ▼   the decision matrix: can this wait until after the run?
   ╭──────────────────────────╮   ╭──────────────────────────────────╮
   │ DEFER                    │   │ ESCALATE                         │
   │ recorded with its grade, │   │ spawn -reviewer, which plans the │
   │ its file:line and a      │   │ fix and hands the plan back      │
   │ one-line justification.  │   │                │                 │
   │ Travels in the handover  │   │                ▼                 │
   │ until resolved or        │   │ -orchestrator applies it. The    │
   │ explicitly closed. A     │   │ reviewer never touches source.   │
   │ deferred CRIT is named   │   ╰──────────────────────────────────╯
   │ in the handover's first  │
   │ line.                    │        MED never reaches the reviewer.
   ╰──────────────────────────╯        The orchestrator handles it itself,
                                       which is what keeps the most
                                       expensive tier rare.

   ── and independently of all of the above ──────────────────────────

   -closure runs at every phase close, every T2/T3 step close, and before
   every handover. It re-derives rather than trusting, so it catches what
   nobody reported: an edit no one disclosed comes back as drift.
```

**This is the shape PhanesLight is built for.** It pays off most when you write a plan first, as numbered steps grouped into phases, each step with a clear boundary and each phase with an exit condition — that is what gives the orchestrator something to route. A vague sentence still works; it just gives the machinery less to hold onto.

Re-running `/phaneslight` detects the existing install through the `.claude/.phaneslight` marker and refreshes in place, measuring agents, workflows, scripts, hooks and READMEs against the latest spec and refreshing whatever drifted.

---

## Which model for which run

Two questions get confused. **Which model you launch the session on** changes per run. **Which model each generated agent runs on** is decided by PhanesLight and is not your dial. This is about the first.

| The run | Recommended model | Effort |
| --- | --- | --- |
| **Install** — first `/phaneslight` in a project | **Opus 5**, or **Fable 5** if you can afford it | `high` |
| **Update** — re-running `/phaneslight` | **Opus 5**, or **Fable 5** if you can afford it | `high` |
| **Upgrade** — `/phaneslightupgrade` | **Opus 5**, or **Fable 5** if you can afford it | `high` |
| **Everyday work** with the installed team | **Sonnet 5** (what makes Max 5x workable), or Opus 5 if budget allows. **Fable 5 for pre-planning only** | `high` |

```bash
claude --model opus   --effort high     # installing, updating, or upgrading
claude --model sonnet --effort high     # everyday work with the installed team
```

**The bootstrap runs hot because it is paid once.** `/phaneslight` and `/phaneslightupgrade` are single-shot, judgment-dense runs that survey a repository, decide module boundaries and author a whole roster, and you live inside that output for weeks. Everyday execution is the opposite: a repeated cost, paid daily, multiplied by every agent in every chain, which is what Sonnet 5 at `high` is designed around.

**Fable 5 earns its price in daily use for pre-planning, and only pre-planning.** The plan is the highest-leverage thinking in the cycle, written once, inherited by every downstream agent. Drafting on Fable and executing on Sonnet is a good trade; a whole execution session on Fable is not.

**Effort is `high` everywhere and is not a dial.** It is fixed at session launch and governs the primary session and every sub-agent; `xhigh` is retired. Set it at launch, since changing it mid-session writes to your global settings and leaks into other projects and parallel sessions.

---

## How to use

### First run

Type `/phaneslight` in your project. Three things make it land well:

- **Start on Opus 5 at `high` effort** (`claude --model opus --effort high`). The first run decides your module boundaries and authors your whole roster, and you live inside that for weeks.
- **Give it something to read, ideally a plan.** On an empty repository, create at least a `plan.md` describing what you want to build, so the setup is shaped around the project you intend rather than an empty folder. **Numbered steps grouped into phases** is the shape the run is designed to consume.
- **Steer it.** Anything typed after the command is a directive that takes priority over defaults: `/phaneslight focus on the api/ module; skip pre-commit hook install`.

Restart your session when it finishes so the hooks arm.

### Re-running `/phaneslight`

Think of it as refreshing Claude's knowledge of your project. **Launch update runs on Opus 5 too** — they are deciding what your team looks like, not using it.

**A re-run measures before it rebuilds** (Windows). It opens by asking what actually moved: spec version, capability census, hook table, register, file hashes, git history since the last run. Nothing moved and a clean worktree means it verifies rather than regenerates, which makes a habitual re-run cheap enough to be habitual. Where it cannot see (no git, no recorded previous run) it does the full pass, because not knowing is not the same as nothing having changed.

- **Early, small project:** run it freely, several times a day.
- **Before an implementation plan** — the highest-value run of all. Write the plan, then run `/phaneslight` and paste the plan or its path after the command, so the team is tuned to execute exactly it.
- **Session bookends:** end of a workday, or first thing next morning.
- **Grown project:** once or twice a day, plus one before a large plan.

---

## Core principles enforced by PhanesLight

- **Procedure in scripts, judgment in prompts, hooks at the harness layer.** Any rule a script can enforce lives in `.phaneslight/scripts/`, and hooks make the critical ones unskippable: a blocking stamp guard, an advisory size check, and on Windows a session-start check that speaks only when a previous run died mid-flight. Mechanical rules in prompts get forgotten under context pressure. Scripts do not forget; hooks cannot be skipped.
- **Durable returns (v3.6.1).** Every sub-agent return is written to `.phaneslight/returns/` **before the next dispatch**, verbatim. Bounded fan-out governs how many agents run; nothing governed **durability**, and that was where runs lost their most expensive work: a return lives in exactly one place, the spawner's context, and that context has a ceiling it is guaranteed to reach. Three incidents cost 66 rows of reconstruction triage. Once the rule was explicit, the same run survived three consecutive API crashes with zero loss.
- **Model degradation is documented (v3.6.1).** "Fixed by role" governs the *choice*, not the *availability*. An unreachable pinned model is retried with backoff, then substituted down a per-role ladder, recorded in three places. The reviewer's ladder goes **up** (Fable → Opus): review is load-bearing and the wrong axis to economize on.
- **Verification is load-bearing, not polish (v3.6.1).** Worker dispositions are repeatedly overturned on review, and so occasionally is the orchestrator's own HIGH finding. That is the design working. Budget the review pass into the plan rather than the slack; worker output is not shippable as-received, and a pass that finds nothing is a successful pass, never grounds for skipping the next.
- **Single writer per artifact.** Every registry file, snapshot, summary and generated `_index.md` has exactly one writing agent. Many readers, one writer.
- **Write rights follow the lineup, and every edit is disclosed.** The orchestrator writes unrestricted; the worker only inside a dispatched scope, naming every edit; **the mechanic the same, but never code (v3.7.1)**; **the reviewer never writes code, and does write plan files and review artifacts, naming every one (v3.7.1)**; closure never writes code. An undisclosed edit is reported as drift.
- **No UI approval by prose.** A proposal declares its viewports and reference designs up front; after apply, closure captures and runs an explicit pass/fail checklist. "Looks good" is not evidence. Missing capture tooling is diagnosed, remembered, and marked visually unverified rather than passed silently.
- **Context injection over inheritance.** A sub-agent receives only the slice its tier allows and pulls bulky material through a mechanic digest. **(v3.6.1)** That digest is *unverified* material, not a source: any fact from one heading into a durable document is re-derived first, and counting tasks in particular are a false economy at that tier.
- **Bounded fan-out.** No more than 5 sub-agents at once, whatever the harness allows. A wider sweep is recommended to you, never quietly self-multiplied. Every session summary records the fan-out ledger.
- **Compaction survival.** A run keeps a phase ledger on disk and resumes from it after a mid-flight death, and re-reads the spec from disk the moment it can no longer see its exact text rather than executing a lossy summary of itself.
- **Index-first navigation.** No agent bulk-reads `documentation/`. It descends the indexes, loads the target, and reads nothing else.

---

## For inexperienced users: step-by-step from zero

Experienced Claude Code users can skip to [How to install](#how-to-install).

**1. Create a Claude account** at [claude.ai](https://claude.ai).

**2. Get a plan that can carry PhanesLight.** A single task can run chains of several Claude instances, each using part of your allowance. **Pro is not enough.** You need **Claude Max 5x** (workable entry point), **Claude Max 20x** (recommended headroom), or the **Claude API** pay-per-token at [console.anthropic.com](https://console.anthropic.com) — bearing in mind multi-agent orchestration uses far more tokens than ordinary chat. Check current pricing on the official pages.

**3. Install Claude Code.**

```bash
curl -fsSL https://claude.ai/install.sh | bash          # macOS / Linux
```
```powershell
irm https://claude.ai/install.ps1 | iex                 # Windows
```

With Node.js 18+ you can instead run `npm install -g @anthropic-ai/claude-code`. Install `git` too ([git-scm.com](https://git-scm.com)); PhanesLight requires it. Verify with `claude --version`.

**4. Sign in.** Run `claude` in any project folder and follow the prompt, or type `/login`. Choose **Claude account** for Max, **Anthropic Console** for API.

**5. Install PhanesLight** — continue directly below. It is two commands.

---

## How to install

### Prerequisites

- [Claude Code](https://claude.com/claude-code), installed and authenticated.
- `git`, plus your project's own language toolchain.
- On **Windows, PowerShell 5.1+** (ships with Windows); the pre-flight runs its install commands through it. POSIX uses any standard shell.
- Recommended: `uv`, which runs the `serena` and `semble` MCP servers. The pre-flight installs it if missing.

### As a user-level slash command (recommended)

Makes `/phaneslight` available in every repository.

**Linux / macOS:**

```bash
mkdir -p ~/.claude/commands
curl -L https://raw.githubusercontent.com/Aloim/phaneslight/main/phaneslight.md \
  -o ~/.claude/commands/phaneslight.md
```

**Windows (PowerShell):**

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.claude\commands" | Out-Null
Invoke-WebRequest `
  -Uri https://raw.githubusercontent.com/Aloim/phaneslight/main/phaneslight.md `
  -OutFile "$env:USERPROFILE\.claude\commands\phaneslight.md"
```

### Per project (alternative)

```bash
mkdir -p .claude/commands
curl -L https://raw.githubusercontent.com/Aloim/phaneslight/main/phaneslight.md \
  -o .claude/commands/phaneslight.md
```

### Run it

Open the repository in Claude Code and type `/phaneslight`. Anything after the command is forwarded through `$ARGUMENTS` and takes priority over the default plan:

```
/phaneslight focus on the api/ module; skip pre-commit hook install
```

The first run takes several minutes, pauses to confirm module boundaries and hook install, and ends by asking you to restart the session. Later runs are faster; only differences are written.

### What gets created

```
your-repo/
├─ documentation/        # project memory, navigated by index, never bulk-read
│  ├─ _index.md          #   generated index (sole writer: phaneslight doc-index)
│  ├─ session-summaries/ #   SS0000N run records
│  ├─ plans/             #   dated implementation plans
│  ├─ snapshots/         #   dated architecture snapshots
│  └─ registry/          #   curated API registry (sole writer: orchestrator)
├─ tests/                # unit · integration · e2e · fixtures · helpers
├─ .phaneslight/         # scripts, config, and machine-owned state
│  ├─ scripts/           #   cli.js · new-file · doc-index · loc/doc/register-check · hook-*
│  │                     #   Windows also: preflight · update-preflight · install-templates
│  │                     #   scaffold · ledger · manifest-write · census-diff · repo-manifest
│  │                     #   batch-apply
│  ├─ registry/          #   generated API baseline (sole writer: closure)
│  ├─ returns/           #   durable sub-agent returns, per run (v3.6.1)
│  ├─ inventory/         #   source file list + one-line summaries (Windows)
│  ├─ config.json        #   confirmed modules · language · build system
│  ├─ manifest.json      #   installed-artifact provenance and hashes
│  └─ run-progress       #   phase ledger for crash / compaction resume
├─ .claude/              # harness wiring
│  ├─ agents/            #   the five fixed agents of the lineup
│  ├─ workflows/         #   YAML task sequences; §IV governs routing
│  ├─ settings.json      #   stamp-guard (blocking) + size-check (advisory) hooks
│  │                     #   Windows also: ledger-status (SessionStart, silent unless a run died)
│  ├─ template/          #   fetched prompt templates
│  └─ .phaneslight       #   run counter + install-state marker (hidden)
├─ CLAUDE.md             # root: orchestration mandates; modules: local guidance
└─ CLAUDE.local.md       # live register of work in motion (35k/40k char budget)
```

The shipped `.gitignore` excludes `.claude/`, `.phaneslight/` and other runtime artifacts. Adjust to taste.

---

## Upgrading an older install

Install the upgrader alongside `/phaneslight`:

**Linux / macOS:**

```bash
curl -L https://raw.githubusercontent.com/Aloim/phaneslight/main/PhanesLightUpgrade.md \
  -o ~/.claude/commands/phaneslightupgrade.md
```

**Windows (PowerShell):**

```powershell
Invoke-WebRequest `
  -Uri https://raw.githubusercontent.com/Aloim/phaneslight/main/PhanesLightUpgrade.md `
  -OutFile "$env:USERPROFILE\.claude\commands\phaneslightupgrade.md"
```

**Run the upgrade on Opus 5 at `high` effort.** It performs file surgery on knowledge your project cannot re-earn, which makes it the worst run in this library to economize on.

Then open the project and run `/phaneslightupgrade`. It refreshes your `/phaneslight` command, detects the installed version, plans the jump from the changelog, and computes exactly what to archive, generate and regenerate from the installed-artifact manifest. **From v3.6.1 it also performs the name migration (`.phanes/` → `.phaneslight/`) and the repository migration, repointing every distribution URL at `Aloim/phaneslight`.** Everything runs on a dedicated `phaneslight-upgrade-<date>` branch behind an evidence-verified checklist; knowledge is preserved byte for byte, superseded artifacts are archived rather than deleted, and you review and merge the branch yourself. The only precondition is a clean `git status`.

You normally get here from `/phaneslight` itself: whenever a newer version has shipped, the version check at the start of every run offers the upgrade and routes you here.

### Upgrading from v3.6.1 specifically

v3.6.1 is the last manual release before this one, so this is the common case. **There is no manual v3.7.0**; v3.7.0 was the plugin, so you go straight from v3.6.1 to v3.7.1 and skip nothing that applies to you. Three steps:

1. **Refresh both command files** with the fetch commands above. `/phaneslightupgrade` refreshes `/phaneslight` for you as its Phase U0 Step 2, so fetching the upgrader alone is enough if you would rather not do it by hand.
2. **Run `/phaneslightupgrade`** in the project, on Opus 5 at `high` effort, with a clean `git status`.
3. **Restart your session**, then run `/phaneslight` once. Hook configuration is snapshotted at session start, so anything the upgrade registered is inert until you do.

The jump is small and additive. Nothing in your project structure moves, `migrationBoundaries` is unchanged, and the work is confined to regenerating `<slug>-mechanic` and `<slug>-reviewer` for the two new rules, restating them in the root `CLAUDE.md` Pinned Directives block, and reinstalling the template library at its `v3.7.1` stamps. Your accumulated knowledge is untouched.

### Coming from the plugin

The plugin published at v3.7.0 was meant for the Claude community marketplace and should never have replaced this repository's contents. It now lives at [`Aloim/phanesplugin`](https://github.com/Aloim/phanesplugin). **A marketplace you added from `Aloim/phaneslight` no longer resolves**, because the plugin tree has been removed from here. Pick one of two routes.

**Route A: stay on the plugin.** Nothing in this repository applies to you, and no command you type changes. The plugin and the marketplace both kept the name `phaneslight`, so only the source moved:

```
/plugin marketplace remove phaneslight
/plugin marketplace add Aloim/phanesplugin
/plugin install phaneslight@phaneslight
```

Then restart Claude Code and run `/phaneslight:upgrade`. Your entry points remain `/phaneslight:run` and `/phaneslight:upgrade`.

**Route B: move back to the manual install.** Do this if you preferred the single-file prompt, or if you want your hooks recorded in your own `.claude/settings.json` rather than registered by a plugin.

1. **Uninstall the plugin and drop the marketplace.**

   ```
   /plugin uninstall phaneslight@phaneslight
   /plugin marketplace remove phaneslight
   ```

   The non-interactive equivalents are `claude plugin uninstall phaneslight@phaneslight -y` and `claude plugin marketplace remove phaneslight`. Confirm with `/plugin list` and `/plugin marketplace list`.

2. **Install the manual command files** with the fetch commands under [How to install](#how-to-install) and [Upgrading an older install](#upgrading-an-older-install). You want both `phaneslight.md` and `PhanesLightUpgrade.md`.

3. **Restart Claude Code.** Plugin-registered hooks are removed with the plugin, but hook configuration is read at session start, so do not judge the state of anything until you have restarted.

4. **Run `/phaneslight`** in the project. This is the step that matters: the plugin removed PhanesLight's hook entries from your `.claude/settings.json` when it took over registration, so nothing is enforcing size and stamp discipline until a manual run puts them back. The run re-merges the settings fragment, reinstalls the script library into `.phaneslight/scripts/`, and regenerates the roster.

5. **Restart once more**, because the hooks you just registered are themselves snapshotted at session start.

**Your project state carries over untouched.** Both lines are at v3.7.1 and both use `.phaneslight/`, the same `phanesLightVersion` key, the same manifest and the same five agents, so neither route is a migration and neither triggers the version gate. Nothing you have accumulated is at risk in either direction.

**One caveat worth knowing.** If you leave the plugin installed *and* install the manual command files, you end up with two live entry points at the same version, and Claude Code does not document which wins on a name collision. Do not run both. Finish whichever route you picked.

---

## Companion tools

PhanesLight stays modular: capabilities beyond bootstrapping ship as **companion tools**. Each is a full standalone tool that works in any repository with no PhanesLight install, and each also cooperates with the structures PhanesLight generates.

- **[Charon](https://github.com/Aloim/charon)** — finds dead code, unused files and dependencies, and duplication, then writes an evidence-backed audit report without touching anything. In a PhanesLight project the report is filed into the documentation tree and dead exported APIs become proposed registry annotations. Worth running before large refactors: stale code is context poison for agents.
- **[Philia](https://github.com/Aloim/philia)** — shares a Windows terminal in the browser for collaborative or remote vibecoding: a password-protected link, shared tabs and a side chat, tunneled from your own PC with nothing for guests to install. The host keeps a kill switch and a live indicator.
- **[Mosyn](https://github.com/Aloim/mosyn)** — a shared, disciplined project memory on decentralized storage (Walrus and SEAL): recall before acting, decision and failure logging, schema-locked session distillation with an append-only audit trail. Alongside PhanesLight it gives the whole team one durable memory across sessions, machines and teammates.
- **[Metis](https://github.com/Aloim/metis)** — reads Claude Code's own run transcripts and reports whether your team actually used the tools and workflows it was told to, harvesting short-lived subagent transcripts before the harness discards them. In a PhanesLight project the census detects it and update runs act on its adherence report.

---

## Recommended third-party enhancements

PhanesLight never installs these. The census discovers them only if you installed them, and wires them into exactly the agents whose duties they serve, under least privilege, never as a hard dependency. **(v3.6.1)** The stack-match gate is now hard: a capability that cannot complete the sentence "granted because this project has ___" is not granted and not listed. All were verified actively maintained on 2026-07-15; re-check before adopting. Code search is absent because PhanesLight installs `semble` itself.

- **Shell-output compressors** (e.g. RTK) — a PreToolUse proxy stripping noise from build, test and git output before it reaches any agent's context, preserving errors and diffs in full. Measured at ~89% noise removal in July 2026. Helps every agent that runs shell commands; needs no wiring.
- **Usage monitors** (e.g. claude-hud, claude-monitor) — live context fill and rate-limit forecasting alongside long runs. Purely observational, zero token cost.
- **CLAUDE.md linters** (e.g. cclint) — validate the instruction files PhanesLight generates on the CI side, catching deprecated model identifiers, broken imports and leaked keys.

---

## Version

**Current: v3.7.1** (2026-09-04). Full accounting in [`Changelog.md`](Changelog.md).

### v3.7.1 release notes

**1. This repository is the manual install, and the plugin has its own home.**

v3.7.0 published the Claude Code plugin into this repository and, in doing so, replaced the manual prompt with a retirement notice. That was a mistake. The plugin was built for the **Claude community marketplace** and belonged in its own repository from the start; nothing about shipping it required closing the manual path. Both halves are corrected here:

- **`Aloim/phaneslight` (this repository) is the manual, single-file PhanesLight.** `phaneslight.md`, `PhanesLightUpgrade.md` and the template library are published here, as they were through v3.6.1. The v3.6.2 retirement notice is withdrawn.
- **`Aloim/phanesplugin` is the plugin.** Its marketplace, skills and hook registration live there. The plugin is still named `phaneslight`, so `/phaneslight:run` and `/phaneslight:upgrade` are unchanged for anyone already using it; only the marketplace source moved.

The two are separate products with separate mechanics for version checking, script delivery and hook registration. Keeping both in one repository is what forced the false choice in the first place.

**Consequence, stated plainly:** a marketplace added from `Aloim/phaneslight` no longer resolves, because the plugin tree is gone from here. See [Coming from the plugin](#coming-from-the-plugin) for both ways out.

**2. The haiku tier never writes code.**

`<slug>-mechanic` may no longer write code of any kind. Its dispatched scope is mechanical **non-code** work only: formatting, documentation indexing, archive condensation, and the fetch-and-digest retrieval it already carried. A task that turns out to need authored code comes back to its spawner unwritten, with a description of what the task needs. It is also no longer named as an agent that may create files under `tests/`, because a test file is code.

**Its escalation threshold drops from MED to LOW**, and that follows from the write restriction rather than from any reassessment of severity. A mechanic that could write was able to fix a LOW in passing and move on. One that cannot has nowhere to put a LOW except upward, and a LOW it keeps to itself is a LOW nobody else will ever see. What travels is a report, not a work item: the spawner applies the ordinary ladder to what arrives, and a LOW from a mechanic still creates no work unless the spawner independently regrades it. INFO never travels, from any agent.

The worker is untouched. It still writes code within its dispatched scope and still escalates at MED.

*Why:* the model rubric had said `Never for authored logic` since v3.6.0, but the write-rights table still granted the mechanic edits within a dispatched scope. The restriction therefore depended on every dispatcher choosing correctly rather than on the lineup refusing. This closes the gap in the table rather than in the guidance.

**3. The reviewer plans first, and writes plan files.**

On a planned launch the orchestrator's **first** act, before the first execution step and before any worker or mechanic dispatch, is to spawn `<slug>-reviewer` against the plan it was handed. The reviewer returns a plan review naming what the repository contradicts, what is sequenced wrong, what acceptance checks are missing, and what work the plan implies without stating. On CRIT or HIGH the orchestrator stops and brings it to you. A run handed no plan skips this entirely.

**The reviewer may write the plan file**, amending it in place or authoring a corrected one under `documentation/plans/`, and naming every file it wrote in its return. That is the only writing it does and it is documentation: it never touches code, and the orchestrator still applies every code change itself.

**The old wording was misleading and is corrected.** Up to v3.6.1 the spec said flatly that the reviewer "never writes" while requiring it to author fix plans, and the generation checklist called any reviewer write grant a defect. The two could not both be honoured. The rule now says what it always meant: the reviewer never writes **code**. A reviewer generated as wholly read-only now fails the generation check just as one granted code writes does, because it cannot perform the duty the lineup assigns it.

**This costs more, deliberately.** The Fable tier now fires once per planned launch, where it previously fired only on HIGH and CRIT. The trade is that a defect caught in the plan costs one review, while the same defect caught at close costs every step built on top of it.

**4. Publication.**

v3.7.1 ships to **both** `Aloim/phaneslight` and the legacy `Aloim/phanes`, exactly as v3.6.1 did, so an installation still polling the old URL sees the release once and is repointed by `/phaneslightupgrade`. Every template stamp, `MANIFEST.json` and the tag-pinned fetch path move to `v3.7.1` together.

---

**Previous: v3.6.1** (2026-09-03) — renaming, repository migration, and a workflow update. See the collapsed v3.6.1 notice at the top of this file for the migration; the rest of the release fixes thirteen defects found in production use, across tooling, orchestration, bootstrap quality and cheap-tier calibration.

**Tooling:** `new-file` selects its header by *destination* rather than by a magic module name, so a Markdown file under `documentation/` gets the DOC discipline header whatever module was named, and says so rather than promoting silently. `doc-index` orders by filename instead of modification time, so the index can answer "which is the latest" and editing an old document stops reordering the whole file. `register-check` renames its completed-entry finding to `COMPLETED-NOT-ARCHIVED` and explains itself, resolving a contradiction where the register legend advertised a marker whose use the checker reported as a finding. `loc-check` always terminates with a count line, so a truncated tail carries the number. Closure's write surface is documented exhaustively, since "output is a flag, never a fix" is a claim about judgment, not about the file system.

**Orchestration:** durable returns, the documented degradation posture, the owner-owned `pinned:project` deviations block that survives regeneration, and a requirement that at least one workflow cover recurring maintenance rather than change-type work alone.

**Bootstrap and calibration:** a bootstrap snapshot may no longer state a bare negative — markers are phrased as unverified negatives with their method named, and the prose is searched before one is written. Mechanic digests are documented as unverified material requiring re-derivation before anything from them is written into a durable document. Serena is granted only where its language servers cover the stack.

Full accounting, and the complete release history from v2.1 onward, in [`Changelog.md`](Changelog.md). The last pre-ladder distribution is kept whole in [`older version/v3.4.1/`](older%20version/v3.4.1/); retired machinery is preserved verbatim in the project's internal records, together with the conditions under which it would be reinstated.

**Immediately beneath: v3.6.0** (2026-09-03) retired the review chain. The Critic pass on every diff, the two mandatory verdicts, the Reflect loop, the separate security gate, the Synthesizer, and the domain roster of six to ten personas were all replaced by a fixed five-agent lineup named by model tier and an escalation ladder in which findings travel **upward by severity** instead of artifacts travelling sideways through gates. This is a deliberate reduction in review coverage traded for token economy; what stands in its place is disclosure plus independent re-derivation at close. The retired machinery is preserved verbatim in the project's internal records.

---

## License

PhanesLight is released under the **Creative Commons Attribution-NonCommercial 4.0 International** license (see [`LICENSE`](LICENSE)).

You are free to use, share and adapt it for any **non-commercial** purpose with attribution. Commercial use is not granted by this license; contact the author directly for commercial terms.

---

## Contributing

Issues and pull requests are welcome at [`github.com/Aloim/phaneslight`](https://github.com/Aloim/phaneslight). A substantive change to `phaneslight.md` should explain which class of failure mode it closes, because PhanesLight is a defensive document and every clause is load-bearing.
