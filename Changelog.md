# Changelog

All notable changes to **Phanes**. The authoritative version marker is the stamp on the first line of `phanes.md` — diff it against this repository before assuming your installed copy is current.

---

## v2.3 — 2026-07-15

### Added
- **Bounded Fan-Out (new §II principle):** a hard width budget of 5 sub-agents in flight at once, tier-independent — scouts count against their spawner, parallel perspectives keep their 2–5 band. Wider sweeps are never hand-rolled: the harness's native large-scale orchestration (where one exists) is the sanctioned escalation path, recommended to the user and never invoked silently. Every session summary now records a fan-out ledger (sub-agents spawned per phase, peak in flight) so budget breaches are visible across runs.
- **Compaction Survival (new §II principle):** every run keeps a run-progress ledger at `.phanes/run-progress` — one line per completed phase, opened in Phase 0, closed at the Phase 5 sign-off. An unclosed ledger at run start means a prior run died mid-flight; the new run resumes from the recorded phase instead of blindly restarting. And because long sessions compact lossily, a run that can no longer see a later phase's verbatim text re-reads the installed prompt from disk before proceeding — re-read, never recall.
- **Dual-verdict Critic (R.A.C.R.S. amendment):** every Critic audit closes with two mandatory verdicts — spec compliance and quality, each an explicit pass or fix_required. A report missing either verdict is returned fix_required without content review, and the orchestrator never pre-judges findings on the Critic's behalf. Enforced in the chain design rules, the agent template's JSON contract, and the report template.
- **Reference, don't paste (Context Injection Protocol, item 4):** injected material past ~2,000 tokens travels as a file path plus a structured brief, never as pasted content — handoff boundaries are where multi-agent chains silently lose context, and a reference read at the destination cannot be truncated by the sender's summarizing hand.
- **`semble` is now a pre-flight install (fourth MCP server):** hybrid code search (BM25 + static embeddings, tree-sitter-aware chunking) so agents find the exact snippet instead of sweeping a module with grep and reading whole files — the largest single token sink in a run. Two tools of schema (`search`, `find_related`), CPU-only, no API key, no GPU, no external service, and it rides the `uv` the pre-flight already installs for Serena, so it adds no prerequisite. Indexes build on demand and re-index on file changes; there is no separate index step and no bootstrap-time cost. `semble` finds the code, Serena navigates it — the Phase 4 rubric keeps them distinct, and index-first is now the first rung of every agent's analysis ladder. It is the one MCP call a T1 task may make, and only to locate a genuinely unknown file. Failure degrades to Grep/Glob sweeps: costlier, never incorrect.
- **Code-index slot discipline:** the Phase 3 matching rubric now treats the code-index slot as filled. A discovered code-index server (symbol-graph, repo-map, rival hybrid search) is granted only where it demonstrably beats `semble` for the project's stack, and where granted, `semble` is not granted to that agent — two servers doing one job is two schema taxes for one capability.

### Changed
- Model & Effort rubric re-reviewed 2026-07-15 (Haiku 4.5 / Sonnet 5 / Opus 4.8, unchanged assignments) and now records that per-sub-agent reasoning-effort control is not exposed by the harness — thinking directives remain the depth lever.

---

## v2.2.1 — 2026-07-15

### Added
- **Frontend design skill in the pre-flight:** every run now ensures the official `frontend-design` plugin (`claude-plugins-official` marketplace) is installed — deliberate, non-templated visual design guidance that costs zero context until invoked, so the install carries no schema tax. Every generated agent carries the rule that UI- and frontend-related tasks begin by loading the skill via the Skill tool. Not mandatory: if the marketplace is unreachable or the install fails, the run records a TODO and continues, and agents treat the skill as a conditional enhancement ("if available") like every discovered capability. A fresh install arms on the next session, like the enforcement hooks.

---

## v2.2 — 2026-07-15

### Added
- **Self-version check (Phase 0, Step 0):** every run fetches the distribution repository's `phanes.md`, compares version stamps numerically, and refreshes every installed copy when upstream is newer — then stops with a verbatim re-run notice so no run ever executes a stale spec. The download is sanity-checked (a 404 page never clobbers a working install), a newer local copy is never downgraded, and an offline fetch degrades gracefully to a session-summary TODO.
- **Installed-Capability Leverage (new §II principle):** every run inventories user-installed MCP servers, plugins, skills, slash commands, and non-Phanes agents, then wires *matched* capabilities three layers deep — per-agent least-privilege grants via a Phase 3 matching rubric, generated "Discovered servers" entries in each agent's MCP Usage Rubric, and a regenerated Installed Capability Register in the root CLAUDE.md. Everything discovered is a conditional enhancement ("if available" phrasing; no chain ever blocks on it); failures are diagnosed and remembered in `.phanes/config.json` for later runs. Phanes never installs, uninstalls, or reconfigures what the user set up.
- **Visual Evidence Mandate (new §II principle):** UI changes can no longer be approved by prose. Proposals must declare target viewports, affected screens/states, and the reference design (the Critic returns `fix_required` without the declaration); after apply, a designated visual verifier — a duty carried by an existing roster agent, preferring the frontend specialist, never new headcount — captures before/after evidence at the declared viewports and runs a mechanical pass/fail checklist (hierarchy, clipping, focus/hover states, contrast, per-viewport layout, reference match, adjacent-UI regression). Output is a flag, not a fix. Soft gate: absent or failing capture tooling is diagnosed, remembered across sessions, and surfaces as `VISUAL: UNVERIFIED` plus a user-eyeball request — never a silent pass.

---

## v2.1.2 — 2026-07-11

### Added
- **Termination discipline for generated scripts** (Phase 2.5, Step 4, hard rule): every script in the generated library must be one-shot, non-interactive, and self-terminating. No input prompts (`input()`, `Read-Host`, readline), no watch/poll/serve loops, no detached or background child processes; any child process is invoked synchronously and awaited. Sub-agents and harness hooks run these scripts headlessly, so a script that waits or lingers hangs the tool call and leaves orphaned interpreter processes accumulating on the user's machine. An audit of existing bootstrapped projects (Python, Node, PowerShell libraries) found all generated scripts already conform; the rule makes it mechanical instead of lucky.

---

## Docs — 2026-07-11

### Added
- README: **Companion tools** section expanded with [Philia](https://github.com/Aloim/philia), a collaborative browser-shared terminal for watching and driving a Phanes-managed agent team together over a password-protected link, and [Mosyn](https://github.com/Aloim/mosyn), shared decentralized project memory for Claude Code agents. The section now opens with the modularity stance: Phanes keeps its core to one file, and every companion is a standalone tool that also cooperates with the structures Phanes generates. A matching note sits in the README intro.

---

## v2.1.1 — 2026-07-10

### Changed
- **Model rubric: every Critic now runs on Opus** (was: Sonnet for standard Critics, Opus only for the final T3 Critic). The Critic is the terminal quality gate on every chain — a missed defect costs more than the review.

---

## v2.1 — 2026-07-10

### Added
- **DeepWiki MCP** joins the pre-flight (hosted service, HTTP transport, three tools): agents ask focused questions about external GitHub dependencies and consume digest answers instead of pulling dependency source into context. Graceful degradation like the other servers.
- **MCP Usage Rubric** embedded in every generated agent: when Serena, context7, and DeepWiki actually save tokens, and when to make no MCP call at all (default: a targeted read under ~2,000 tokens beats any MCP call). DeepWiki is never used for the project's own code — the registry and documentation tree own that.
- **Pre-flight token-discipline note**: MCP tool schemas cost context every session (~1,000 tokens per tool); Phanes installs exactly three small-schema, high-leverage servers and warns against large tool-count servers (use the `gh` CLI, not the ~90-tool GitHub MCP).
- Tool assignment tightened: `context7`/`deepwiki` granted only to Planner/Architect, Analyzer, and scout-eligible agents; Executor and Patch-Author carry no MCP tools — unlisted tools cost their invocations nothing.

---

## v2.0.2 — 2026-07-10

### Changed
- `PhanesUpdate.md` renamed **`PhanesUpdateExperimental.md`** — the migration prompt has not been validated against real-world installations. Warnings added throughout: the prompt itself now refuses to run until the user confirms an external backup (remote push or full project copy) and explicitly acknowledges the risk; the README and `phanes.md`'s migration pointer carry the same warning. Treat a migration as **effectively irreversible** once the migration branch is merged.

### Changed (branding)
- Unified to plain **Phanes** across all published files; edition naming removed from the version stamps, README, and this changelog's header.

### Added
- README: **Companion tools** section referencing [Charon](https://github.com/Aloim/charon), the standalone dead-code and duplicate-code audit prompt that cooperates with Phanes-managed projects.
- README: table of contents with section links, and a **How to use** section covering first-run guidance (seed an empty repo with a `plan.md`; steer the setup with directives after the command; restart afterward) and re-run cadence (small project: freely, several times a day; before implementation plans: run and inject the plan; session bookends; large project: once or twice a day). Plus a full copyediting pass for plain readability.

---

## v2.0.1 — 2026-07-10

### Added
- **`PhanesUpdate.md` v1.0** — the migration prompt for projects carrying a pre-v2.0 Phanes install. Self-updates your `/phanes` command from this repository, fingerprints the installed version, then migrates on a dedicated branch behind a generated, evidence-verified checklist. Accumulated knowledge (tier 2 annotations, session summaries, architecture snapshots) is preserved byte-for-byte; superseded artifacts are archived, never deleted; you review and merge the branch yourself.
- README: "Migrating an older install" section, step-by-step setup guide for first-time users, and this changelog.

### Changed
- `phanes.md`: on detecting a pre-v2.0 install, an update run now stops and directs to `/phanesupdate` instead of improvising a partial migration (with an exception for PhanesUpdate's own regeneration hand-off).
- Internal session summaries removed from the distribution repository — this changelog is the public release history.

---

## v2.0 — 2026-07-09

### Added
- **Harness hook enforcement** — `.claude/settings.json` hooks generated at bootstrap: a blocking PreToolUse guard denies creation of unstamped new files; an advisory PostToolUse check runs size and documentation audits on every write. Mechanical rules can no longer be forgotten under context pressure. (Hooks arm on the next session — the run ends with a restart notice.)
- **Scout pattern** — specialists spawn ad-hoc, read-only subagents to fetch and digest bulky one-time context (module surveys, test logs, registry sweeps), governed by a strict cost guard so a spawn always pays for itself in preserved specialist context. Depth-capped, digest-only, never delegated judgment.
- **Documentation anti-bloat & index-first navigation** — 500-line soft ceiling on living docs; every `documentation/` folder carries a generated `_index.md` (new `phanes doc-index` script is their sole writer); agents locate knowledge by descending indexes instead of scanning trees; tolerant extraction indexes pre-existing files without editing them; frozen history (session summaries, dated snapshots) is never edited to conform.
- **Tiered documentation weights** — T1: one-line session-summary entry; T2: report; T3: plan + reports.
- **Dated model rubric** (reviewed against Haiku 4.5 / Sonnet 5 / Opus 4.8; re-validated on every update run) — Sonnet default for coding and review, Haiku for scouts and mechanical work, Opus for architecture and synthesis.
- Windows PowerShell pre-flight variant; version stamp; roster ceiling (6–10 agents, 50-word descriptions).

### Changed
- **Review is universal** — T1 quick fixes are no longer exempt from the Critic; review depth and paperwork scale with tier, review presence never does.
- Chain termination order fixed and made explicit: Synthesizer (parallel work only) → Critic → api-monitor (T2/T3) → primary — the artifact applied is always the artifact audited.
- Run-type detection keyed solely on the `.claude/.phanes` marker (a bare `.claude/` directory no longer misreads as an existing install).
- CLAUDE.md placement: project root + module roots only, replacing per-subfolder sprawl.
- The change-set-generating Executor renamed **Patch-Author**, resolving the duplicate-Executor ambiguity.
- Serena: installed on first run, conditional everywhere after — generated agents degrade gracefully without it.

### Removed
- `sequential-thinking` MCP server — native extended thinking (`think` / `think hard` / `ultrathink`) replaces it; drops the Node/`npx` dependency.
- MCP `memory` server — the documentation tree is the single memory substrate; two substrates drift.
- The MCP pre-flight STOP gate — failed installs degrade gracefully and are logged as TODOs.

### Fixed
- Typos inside verbatim payload blocks that were stamped into every bootstrapped project ("treat them as guidance").
- The root-CLAUDE.md exclusion contradiction and the T1 review-exemption contradiction.

---

## v1 — initial release

The original single-file bootstrap prompt: repository comprehension, two-tier API registry, script library, R.A.C.R.S. review cycle, tiered workflows, and the generated sub-agent roster. Preserved verbatim in [`older version/phanes.md`](older%20version/phanes.md).
