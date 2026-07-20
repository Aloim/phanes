# Phanes

**Phanes** is a bootstrap prompt for [Claude Code](https://claude.com/claude-code). In a single command it turns an empty or chaotic repository into a fully wired, opinionated, multi-agent development environment.

It is not something you install once and forget. Think of it as a living specification that you re-run. Each time you invoke `/phanes`, it surveys the project again, upgrades the existing sub-agents, fills in any missing infrastructure, and bumps a hidden run counter. The result is an agentic team that grows with your codebase instead of rotting beside it.

**The prompt is one file.** You install a single Markdown file, `phanes.md`, as your `/phanes` command. The scripts, hooks, agents, and documents it sets up are created inside your repository during the run. The scripts that do not depend on your project's language are fetched as tested templates from this repository, pinned to the prompt's own version, and everything else is generated. If the fetch cannot happen, the run generates the scripts as well, so an offline install is still complete.

**Modular by design.** The core stays that one file on purpose. Anything beyond bootstrapping ships as a separate [companion tool](#companion-tools). Each companion works on its own in any repository, with no Phanes install at all, and each one snaps into the structures Phanes builds the moment it lands in a Phanes-managed project.

**Which file do you need?**

| Your situation | What to use |
| --- | --- |
| A fresh project, or any project that has no Phanes yet | Use `phanes.md` and run `/phanes` for the full setup. Running it again also keeps a current install up to date. |
| A project that already carries an older Phanes (for example a v1 install) | Use `PhanesUpdateExperimental.md` and run `/phanesupdate` to migrate. ⚠️ It is **experimental, and effectively irreversible once the migration branch is merged, so a full backup is mandatory** (see [Migrating an older install](#migrating-an-older-install-experimental) below). It first refreshes your installed `/phanes` command from this repository so you migrate onto the newest spec, then upgrades the project's entire Phanes structure (agents, scripts, hooks, workflows, and the documentation tree) behind a strict, generated, per-item-verified checklist. Your accumulated knowledge (session summaries, registry annotations, and snapshots) is preserved and indexed, never rewritten. |

**Contents**

- [What it does](#what-it-does)
- [How to use](#how-to-use)
- [Core principles enforced by Phanes](#core-principles-enforced-by-phanes)
- [For inexperienced users: step-by-step from zero](#for-inexperienced-users-step-by-step-from-zero)
- [How to install](#how-to-install)
- [Migrating an older install (⚠️ experimental)](#migrating-an-older-install-experimental)
- [Companion tools](#companion-tools)
- [Recommended third-party enhancements](#recommended-third-party-enhancements)
- [Version](#version) · [License](#license) · [Contributing](#contributing)

---

## What it does

The first time you run `/phanes` in a repository, the prompt walks Claude Code through a strict setup in several phases.

**1. Pre-flight.** Before anything else, the run checks itself. It fetches this repository's `phanes.md`, compares version stamps, refreshes every installed copy when a newer version has shipped, and stops with a re-run notice, so no run ever executes a stale spec.

It then installs the four MCP servers it benefits from:

- `context7` for live library documentation, fetched on demand.
- `deepwiki` for digest answers about external GitHub dependencies, so agents never pull dependency source into their context.
- `semble` for hybrid code search, so an agent finds the exact snippet it needs instead of sweeping a whole module with grep and reading entire files.
- `serena` for symbol-level code navigation, installed on the first run. It runs through `uv`, which the pre-flight also installs if it is missing.

These servers are enhancements, not hard dependencies. If one fails to install, the run records a TODO and continues in a degraded mode rather than halting. There are exactly four of them on purpose. Every MCP tool schema costs context in every session, so each server has to earn its place by removing more context than its schema costs. `semble` is the clearest case: two small tools weighed against the single largest token sink in a run. Every generated agent also carries a usage rubric that says when each server saves tokens and when to make no MCP call at all.

The pre-flight detects your platform first and runs the matching commands: bash on POSIX systems, PowerShell on Windows. It runs a capability census of what you already have installed, including MCP servers, plugins, skills, and slash commands, and it probes each server to see whether it is actually reachable and authenticated rather than merely configured. On a first run it then asks you once, as a single checklist, which of those capabilities Phanes may build policy around: the four servers above plus `frontend-design` come pre-selected as recommended, and every other tool you have is listed by name for you to opt in or leave out. Your choice is saved, so later runs stay silent unless the set actually changes, and then they ask only about what changed. Phanes only ever builds a mandate around a capability you selected and that the census found reachable, which is what keeps a required-tool rule from ever pointing at a tool that is switched off or signed out. Nothing you installed is ever changed or removed. It also ensures the official `frontend-design` skill is present, since skills cost no context until they are invoked, so UI and frontend work runs with deliberate design guidance loaded. Finally, each run keeps a progress ledger on disk at `.phanes/run-progress`, so a session that dies or compacts mid-bootstrap resumes from the last completed phase instead of starting over blind.

**2. Repository comprehension.** Phanes reads the README, the source tree, the configs, and the CI to work out the project's real purpose, its primary language, its build system, and its module boundaries. Directories that are not part of the core product, such as vendored dependencies, example packs, and demo content, are filtered out.

**3. Project memory infrastructure.** Phanes scaffolds the substrate that every sub-agent works against:

- `documentation/` holds session summaries, plans, dated architecture snapshots, and a curated API registry. That registry captures the things code search cannot see, such as deprecations, contracts beyond the type signatures, and anti-patterns. The generated API surface itself lives outside the tree as a machine baseline in `.phanes/registry/`. Every folder carries a **generated `_index.md`**, so agents find knowledge by descending indexes, which costs a few hundred tokens, instead of scanning the whole tree. Files respect a soft ceiling of 500 lines and are split into an indexed folder when they outgrow it.
- `tests/` holds `unit/`, `integration/`, `e2e/`, `fixtures/`, and `helpers/`, with a verbatim README and the same `phanes new-file` header-stamp discipline that `src/` uses.
- `.phanes/scripts/` is a script library that owns every mechanical rule, from creating files with header stamps and checking line counts to auditing the documentation ceiling (`doc-check`), regenerating indexes (`doc-index`), measuring the root files that load every session against their character budget (`register-check`), regenerating the API baseline, diffing the API, and listing modules. The scripts that do not depend on your language are installed from tested templates fetched from this repository (pinned to the running version), and each one finds the project by walking up to `.phanes/config.json` and uses only paths relative to that root, so a hook can never be wired to the wrong tree.
- `.claude/settings.json` holds the hooks that enforce mechanical rules at the harness layer. A blocking PreToolUse guard denies creation of any unstamped new file, and an advisory PostToolUse check runs size and documentation audits on every write. Prompts forget under context pressure. Hooks cannot.
- `.phanes/config.json` records the confirmed module list, language, build system, and hook preferences.

**4. Tiered workflow definition.** Every task is sorted into one of three tiers: T1 for a single-file quick fix, T2 for a feature inside one module, and T3 for anything that cuts across modules. Each tier loads a different amount of context and engages a different chain of agents, but review is universal. Even a T1 fix gets a lightweight Critic pass on its diff. Only the depth of the review and the weight of the documentation scale with the tier. If a task outgrows its tier mid-flight, the agent must stop and ask the orchestrator to promote it.

**5. Sub-agent roster generation.** Phanes writes 6 to 10 deeply scoped, expert personas to `.claude/agents/*.md`. Each one is assigned a model by a dated rubric that is re-validated on every update run:

- **Architect/Designer**, the sole writer of the curated registry and the architecture snapshots.
- **close-verifier**, the independent close-time verifier and sole writer of the generated API baseline in `.phanes/registry/`. After every structural change it re-derives the baseline, re-runs the build check itself rather than trusting the coder's report, and confirms that what was applied matches what was approved. It stays a separate agent from the Architect on purpose, since a verifier that also authored the work is not an independent check.
- **Critic agents**, which produce numbered, ID-tagged audit reports.
- **Patch-Author**, which turns the approved plan into sequenced patch files but never applies them.
- **Executor**, which applies approved diffs only and uses `phanes new-file` for every new file.
- **Synthesizer/Arbiter**, which consolidates parallel perspectives into one unified plan.
- Plus Analyzer, Planner, Validator, Optimizer, Integrator, Monitor, and Cleaner variants tuned to your specific stack.
- **Scouts** are not part of the roster. Specialists spawn them on the fly as read-only subagents that fetch and digest bulky one-time context such as module surveys, test logs, and registry sweeps. A strict cost guard makes sure every spawn pays for itself in the specialist context it preserves.

**6. Workflow codification.** The YAML files in `.claude/workflows/` are the single source of truth for how agents chain together. Every chain ends the same way: the Synthesizer runs for parallel work only, then the Critic, then `close-verifier` on T2 and T3 changes, then the primary agent. Because of that ordering, the artifact that gets applied is always the one that was audited. Phanes also updates `CLAUDE.md`, at the project root and at module roots only, so the primary agent knows how to triage, delegate, navigate the documentation by index, and review.

Visualized, that chain looks like this. A task's tier changes only how deep the review goes and how much documentation it produces, never whether the review happens:

```text
                             task
                              │
                              ▼   triaged into a tier
        ╭─────────────────────────────────────────╮
        │ T1  one file      lightweight review    │
        │ T2  one module    full review           │
        │ T3  cross-module  full review + snapshot│
        ╰─────────────────────┬───────────────────╯
                              │
                              ▼   specialists: bounded fan-out, ≤ 5 parallel
              Analyzer · Planner · Patch-Author · …   (tuned to your stack)
                              │   each emits a report + proposed diff, never applies
                              ▼
                        Synthesizer    consolidate parallel perspectives  *
                              │
                              ▼
                        Critic         two verdicts: spec compliance + quality
                              │
                              ▼
                        close-verifier regenerate API baseline  (T2 / T3 only)
                              │
                              ▼
                        Executor       apply the audited diff, and only that

        * Synthesizer runs for parallel work only. Because the chain always
          ends review-then-apply, the artifact applied is always the one audited.
```

**7. Bootstrap session summary.** Phanes writes `documentation/session-summaries/SS00001_phanes-bootstrap_<date>.md`, which records the install, the confirmed module list, the agent roster, and any TODOs that were deferred.

> **After the first run, restart your Claude Code session.** Hook configuration is snapshotted when a session starts, so the enforcement hooks arm on the next session. Phanes reminds you of this verbatim at the end of the run.

When you run `/phanes` again, it detects the existing install through the `.claude/.phanes` marker and upgrades in place. Agents, workflows, scripts, hooks, and READMEs are all measured against the latest `phanes.md` and refreshed wherever they have drifted. An install created by v1 is detected and routed to the experimental updater (see [Migrating an older install](#migrating-an-older-install-experimental)).

## How to use

### First run

Type `/phanes` in your project. It scans the repository and builds the whole agentic team and documentation structure around it. Two things make the first run land well.

- **Give it something to read.** On an empty or brand-new repository, create at least a `plan.md` that describes what you want to build. Phanes reads it to understand the project's purpose and shapes the entire setup, including the agents, the workflows, and the module layout, around the project you actually intend to build rather than around an empty folder.
- **Steer it if you like.** Anything you type right after the command is treated as a directive and takes priority over the defaults, so you can inject your own needs into the setup. For example: `/phanes focus on the api/ module; skip pre-commit hook install`.

When the run finishes, restart your Claude Code session so the enforcement hooks arm. Phanes reminds you to.

### Re-running `/phanes`: when, and how often

Think of `/phanes` as refreshing Claude's knowledge of your project. Every run surveys the codebase again and brings the agent team, the workflows, and the registries back in line with reality.

- **Early, small project: run it freely.** Several times a day is fine. While the codebase is small a run costs little in tokens and context, and keeping the agent team current pays off constantly.
- **Before an implementation plan.** This is a good habit rather than a hard rule. Write your plan, say for a new module, then run `/phanes` and inject it. Injecting simply means pasting the plan's contents, or its path, right after the command. Phanes updates the agents and workflows, and creates new ones where needed, so the team is tuned to execute exactly that plan when you start.
- **Session bookends.** Running it at the end of a workday, or first thing when you sit down, keeps the project context fresh before real work begins.
- **Grown project: throttle down.** Once the codebase is large, once or twice a day is plenty. Add a run right before a large plan. Smaller ones usually do not need one.

## Core principles enforced by Phanes

- **Procedure in scripts, judgment in prompts, and hooks at the harness layer.** Any rule a script can enforce, such as line-count limits, header stamps, registry edits, API diffs, and documentation ceilings, lives in `.phanes/scripts/`. The two hooks in settings.json make the critical ones impossible to skip. Mechanical rules written into prompts get forgotten under context pressure. Scripts do not forget, and hooks cannot be skipped.
- **Single writer per artifact.** Every registry file, snapshot, and summary has exactly one writing agent, and so does every generated `_index.md`, whose sole writer is `phanes doc-index`. Many readers, one writer.
- **No direct code changes by sub-agents, at any tier.** A coding agent emits a report that contains a proposed diff, a Critic reviews it, and the Executor applies it. The depth of the review scales with the tier, but the review itself is never skipped. The primary Claude Code agent does not edit code directly either. It orchestrates. Every Critic review closes with two mandatory verdicts, one for spec compliance and one for quality, and a report that is missing either verdict is returned unread.
- **No UI approval by prose.** A UI proposal has to declare its target viewports and reference designs up front. After the change is applied, a designated visual verifier captures before and after screenshots and runs an explicit pass or fail checklist. "Looks good" is not evidence. When the capture tooling is missing or broken, the failure is diagnosed, remembered for later sessions, and the result is marked as visually unverified rather than passed silently.
- **Context injection over context inheritance.** A sub-agent receives only the slice of context that its tier allows, and it pulls bulky material through read-only scout digests instead of loading it raw. Pollution from a sibling task is structurally impossible.
- **Bounded fan-out.** No more than 5 sub-agents run at once, whatever the harness would allow. A genuinely wider sweep is handed to the harness's own large-scale orchestration by recommending it to you, never by an orchestrator quietly multiplying its own fan-out. Every session summary records the run's fan-out ledger.
- **Compaction survival.** Long sessions compact, and a summarized mandate is a forgotten mandate. A run keeps a phase-by-phase progress ledger on disk and resumes from it after a mid-flight death. A run that can no longer see the spec's exact text re-reads it from disk instead of executing a lossy summary of itself.
- **Index-first documentation navigation.** No agent ever bulk-reads `documentation/`. It descends the indexes, loads the target, and reads nothing else.

---

## For inexperienced users: step-by-step from zero

Never used Claude before? This takes you from no account at all to a running Phanes install. Experienced Claude Code users can skip straight to [How to install](#how-to-install) below.

### Step 1: Create a Claude account

Go to [claude.ai](https://claude.ai) and sign up with an email or a Google account.

### Step 2: Get a plan that can carry Phanes

Phanes is a multi-agent system. A single task can run chains of several Claude instances, such as a planner, a coder, a critic, an executor, and a monitor, and each of them uses part of your allowance. **The Pro plan is not enough**, since its limits run out after a few chains. You need one of these:

- **Claude Max 5x**, the workable entry point for lighter projects.
- **Claude Max 20x**, recommended, with comfortable headroom for real multi-agent work. Subscribe under Settings, then Plan, at claude.ai.
- **Claude API, pay per token.** Create an account at [console.anthropic.com](https://console.anthropic.com) and add credits. Be aware that multi-agent orchestration uses far more tokens than ordinary chat, and the cost scales with how hard you drive it.

Check current pricing on the official pages, since plans and limits change.

### Step 3: Install Claude Code

**macOS / Linux:**

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

**Windows (PowerShell):**

```powershell
irm https://claude.ai/install.ps1 | iex
```

If you already use Node.js 18 or newer, you can instead run `npm install -g @anthropic-ai/claude-code`. Make sure `git` is installed too ([git-scm.com](https://git-scm.com)), because Phanes requires it.

Verify the install with:

```
claude --version
```

### Step 4: Sign in

Open a terminal in any project folder, run `claude`, and follow the login prompt, or type `/login`. Choose **Claude account** if you subscribed to Max, or **Anthropic Console** if you are paying per token through the API.

### Step 5: Install Phanes

Continue with [How to install](#how-to-install) directly below. It is two commands.

---

## How to install

Phanes is a single Markdown file, `phanes.md`, so installing it just means putting it where Claude Code can run it as a slash command.

### Prerequisites

- [Claude Code](https://claude.com/claude-code), installed and authenticated.
- `git`, plus whichever language toolchain your project actually uses.
- On **Windows, PowerShell** (5.1 or newer, which ships with Windows). The Phase 0 pre-flight runs its install commands through PowerShell there. POSIX systems use any standard shell.
- Optional but strongly recommended: `uv`, which runs both the `serena` and `semble` MCP servers. The Phase 0 pre-flight installs it for you if it is missing.

### Install as a user-level slash command (recommended)

This makes `/phanes` available in every repository you open.

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

### Install per project (alternative)

If you only want Phanes inside one repository and want it tracked in version control:

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

Anything you add after the command is forwarded through `$ARGUMENTS` and takes priority over the default plan, so you can steer the run:

```
/phanes focus on the api/ module; skip pre-commit hook install
```

The first run takes several minutes. It pauses to confirm a few choices, such as module boundaries and hook install, and ends by asking you to restart the session so the enforcement hooks arm. Later runs are faster, since only the differences are written.

### What gets created on the first run

```
your-repo/
├─ documentation/        # project memory, navigated by index, never bulk-read
│  ├─ _index.md          #   generated index (sole writer: phanes doc-index)
│  ├─ session-summaries/ #   SS0000N run records
│  ├─ plans/             #   dated implementation plans
│  ├─ snapshots/         #   dated architecture snapshots
│  └─ registry/          #   curated API registry (sole writer: Architect)
├─ tests/                # unit · integration · e2e · fixtures · helpers
├─ .phanes/              # scripts, config, and machine-owned state
│  ├─ scripts/           #   cli.js (cross-shell entry) · new-file · doc-index · loc/doc/register-check · hook-*
│  ├─ registry/          #   generated API baseline (sole writer: close-verifier)
│  ├─ config.json        #   confirmed modules · language · build system
│  └─ run-progress       #   phase ledger for crash / compaction resume
├─ .claude/              # harness wiring
│  ├─ agents/            #   6-10 deeply scoped expert personas
│  ├─ workflows/         #   YAML agent chains: the single source of truth
│  ├─ settings.json      #   stamp-guard (blocking) + size-check (advisory) hooks
│  ├─ template/          #   report.md used by every sub-agent
│  └─ .phanes            #   run counter + install-state marker (hidden)
├─ CLAUDE.md             # root: orchestration mandates; modules: local guidance
└─ CLAUDE.local.md       # live register of work in motion (35k/40k char budget)
```

The default `.gitignore` shipped with this repository excludes `.claude/`, `.phanes/`, and other runtime artifacts. Adjust it to taste in your own project.

---

## Migrating an older install (EXPERIMENTAL)

> ⚠️ **PhanesUpdate is experimental. It has not been validated against real-world installations, so treat a migration as effectively irreversible once the migration branch is merged.** Before you run it, commit or stash everything, push your repository to a remote or take a full copy of the project folder, and proceed only on a project you can restore from that backup. The prompt refuses to start until you acknowledge this.

If a project already carries a pre-v2.0 Phanes installation, install the updater alongside `/phanes`:

**Linux / macOS:**

```bash
curl -L https://raw.githubusercontent.com/Aloim/phanes/main/PhanesUpdateExperimental.md \
  -o ~/.claude/commands/phanesupdate.md
```

**Windows (PowerShell):**

```powershell
Invoke-WebRequest `
  -Uri https://raw.githubusercontent.com/Aloim/phanes/main/PhanesUpdateExperimental.md `
  -OutFile "$env:USERPROFILE\.claude\commands\phanesupdate.md"
```

Then back up your project, open it, and run `/phanesupdate`. It refreshes your `/phanes` command from this repository, fingerprints the installed version, and migrates the structure on a dedicated branch behind a generated, evidence-verified checklist. Your accumulated knowledge, including registry annotations, session summaries, and snapshots, is preserved byte for byte. Superseded artifacts are archived, never deleted. You review and merge the branch yourself, so **verify it thoroughly before merging, because the merge is the point of no return**.

---

## Companion tools

Phanes is built to stay modular. Rather than growing the core file, capabilities beyond bootstrapping ship as **companion tools**. Every companion is a full standalone tool that works on its own, in any repository, with no Phanes install. Each one is also built to cooperate with the structures Phanes generates, so together they form one ecosystem.

- **[Charon](https://github.com/Aloim/charon)** finds dead code, unused files, unused dependencies, and duplicated code, then writes an evidence-backed audit report without touching anything. It is a standalone `/charon` command that works in any repository. In a Phanes-managed project it goes further and cooperates with the structures Phanes builds: the report is filed into the documentation tree, open items land in the session summary, and dead exported APIs are proposed as registry annotations so the agent team stops routing new work onto them. It is worth running before large refactors and after big migrations, because stale code is context poison for agents.
- **[Philia](https://github.com/Aloim/philia)** shares a Windows terminal in the browser for collaborative or remote vibecoding sessions. You get a password-protected public link, shared terminal tabs, and a side chat, all tunneled from your own PC with nothing for your guests to install. It is fully standalone, but it pairs naturally with Phanes. Share a Phanes-managed project and everyone on the link watches and drives the same fully wired agent team together, coordinating in the chat, while the host keeps a kill switch and a live on-screen indicator.
- **[Mosyn](https://github.com/Aloim/mosyn)** gives Claude Code agents a shared, disciplined project memory on decentralized storage (Walrus and SEAL). Agents recall relevant facts before acting, log every decision and failure as it happens, and distill each session into schema-locked facts with an append-only audit trail. It works on its own as a protocol prompt plus a command pack in any project. Alongside Phanes it hands the whole generated agent team one durable memory that persists across sessions, machines, and teammates.
- **[Metis](https://github.com/Aloim/metis)** is a session-audit companion that reads Claude Code's own run transcripts and reports whether your agent team actually used the tools and workflows it was told to. It harvests the short-lived subagent transcripts before the harness discards them, then diffs the mandated behavior against what really happened, such as a tool that was required but never called, a server that was configured but never used, or an agent that was never spawned. It runs on its own as a `/metis` command in any Claude Code project. In a Phanes-managed project it does more: Phanes detects it during the capability census and, on an update run, has it harvest the transcripts, verify its own past suggestions against the new sessions, and file an adherence report the run then acts on. It ships alongside this release at [github.com/Aloim/metis](https://github.com/Aloim/metis).

---

## Recommended third-party enhancements

Phanes never installs these. The Phase 0 capability inventory discovers them only if you have installed them yourself, and the Phase 3 matching rubric wires them into exactly the agents whose duties they serve, under least privilege, with a named fallback, and never as a hard dependency. All of them were verified as actively maintained on 2026-07-15, so re-check before you adopt one. Code search is not on this list, because Phanes now installs `semble` itself in the pre-flight. If you already run a rival code-index server, it is granted only where it beats `semble` for your stack, and in that case `semble` is not granted alongside it, since one job should carry one schema tax.

- **Shell-output compressors** (for example RTK) run as a PreToolUse proxy that strips noise from build, test, and git output before it reaches any agent's context, while preserving errors and diffs in full. In measurements from July 2026 this removed about 89 percent of the noise on average. It helps every agent that runs shell commands and needs no Phanes wiring at all.
- **Usage monitors** (for example claude-hud and claude-monitor) show live context fill and rate-limit forecasting alongside long multi-agent runs. They are purely observational and cost no tokens, which makes them useful company for any Phanes bootstrap on a subscription plan.
- **CLAUDE.md linters** (for example cclint) validate the instruction files Phanes generates on the CI side, catching things like deprecated model identifiers, broken imports, and leaked keys.

---

## Version

Current: **v3.0** (2026-07-20). This major release adds a consent layer over capability discovery, renames the close-time verifier, and makes the command line reachable from any shell. On a first run Phanes now takes a census of the tools you already have, checks whether each one is actually reachable, and asks you once, as a single checklist, which of them it may build policy around, so a required-tool rule can never point at a tool you did not choose or that is not signed in. The old `api-monitor` agent becomes `close-verifier`, with a duty list that matches what it really does at a close: it re-derives the API baseline, re-runs the build check itself instead of trusting the coder's report, and confirms that what was applied is what was approved. A small `cli.js` launcher, installed on every platform, gives agents one command, `node .phanes/scripts/cli.js`, that behaves the same in PowerShell, cmd, and Git Bash, which fixes a real case where a bare `phanes` was not found inside a sub-agent shell. The model rubric is re-grounded on a tier-first policy, with a forward-compatible `effort` setting that activates once the harness honors it on in-session agents. See the version stamp at the top of `phanes.md` for the exact version. The full release history is in [`Changelog.md`](Changelog.md), and every superseded version is archived verbatim in [`older version/`](older%20version/).

---

## License

Phanes is released under the **Creative Commons Attribution-NonCommercial 4.0 International** license (see [`LICENSE`](LICENSE)).

You are free to use, share, and adapt Phanes for any **non-commercial** purpose with attribution. Commercial use is not granted by this license. For commercial licensing terms, contact the author directly.

---

## Contributing

Issues and pull requests are welcome. A substantive change to `phanes.md` should explain which class of failure mode it closes, because Phanes is a defensive document and every clause is load-bearing.
