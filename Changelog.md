# Changelog

All notable changes to **Phanes**. The authoritative version marker is the stamp on the first line of `phanes.md`. Diff it against this repository before assuming your installed copy is current.

---

## v3.0.1 (2026-07-21)

Patch. Corrects how reasoning-effort control is described, and adds a temporary bridge that gives the few deepest agents true per-agent effort until the harness supports it natively. The template library is re-stamped to v3.0.1 with no change to script behavior, so the fetch-time version check stays satisfied; deployed projects adopt the prose on their next update run.

### Fixed
- **Effort-control rubric corrected.** v3.0 claimed the agent template's `effort:` frontmatter was "honored on CLI dispatch, ignored on in-session Task spawns until #43083 lands." Verified against the current harness and the primary issues, effort frontmatter is honored on **no** native spawn path: the in-session Task/Agent tool has no effort input (anthropics/claude-code #43083, open), and the headless-frontmatter and Workflow `agent()` effort requests (#65598, #64033) are closed as duplicates of it. The only working lever is session-level effort, set at launch with `--effort` or `CLAUDE_CODE_EFFORT_LEVEL`, never `/effort` or `/model` mid-run, since both persist to the global settings file and leak into other projects and parallel sessions (#57618, #49076). The rubric now states this and drops the overclaim.

### Added
- **Per-Agent Effort Delivery, a temporary CLI-spawn bridge.** Session effort is the orchestrator's own dial and cannot be raised cleanly mid-run, so the session launches at the orchestrator's peak need (`high` by default, `xhigh` for design-heavy runs) and in-session Task agents ride that baseline. To lift a specific heavy archetype above the baseline (architect/designer, synthesizer/arbiter, security- or money-critical critics, 2 to 4 per run), the orchestrator spawns it as its own process, `claude --bg "<prompt>" --agent <name> --effort <level> --permission-mode <mode>`, monitors it with `claude agents --json`, and collects its output with `claude logs <id>` or its report artifact. The bridge is upward only: never spawn an agent to run it cheaper, since the fixed per-process entry tax exceeds the effort saving. The effort band is narrowed to `medium | high | xhigh`. The subsection carries a removal marker: when #43083 ships, it is deleted and the `effort:` frontmatter goes native.

### Changed
- **Template library re-stamped to `v3.0.1`** with no change to script behavior, so the manifest version, the sanity stamp, and every template stamp stay equal to the prompt stamp, as the acquire step's version check requires.

---

## v3.0 (2026-07-20)

Major version. It adds a consent layer over capability discovery, renames the close-time verifier to match its real duties, makes the CLI reachable from any shell, and re-grounds the model rubric on a tier-first policy with forward-compatible effort control. All changes are to `phanes.md` and the template library; deployed projects adopt them on their next update run.

### Added
- **Capability Census & Consent Gate (Phase 0).** The installed-capability pre-flight is now a census that additionally probes each MCP server's auth/health, and a mandate may exist **only** for a capability the census verified reachable, closing the failure mode where a "use `semble` first" mandate coexisted with an unauthenticated `semble` for a whole session. On a setup run it asks one per-item `AskUserQuestion` (multiSelect) listing every detected capability by name: the Phanes-standard set (`context7`, `deepwiki`, `serena`, `semble`, `frontend-design`) pre-selected and marked recommended, every other detected capability listed unchecked by its detected name only. The selection persists to `.phanes/config.json` (`capabilities.selection[]`). Update runs re-census and diff: no change is silent, a delta asks only about the delta, a removed-but-mandated capability has its mandates stripped and recorded. Non-interactive runs default to the standard set and never block.
- **Cross-shell CLI entry point (`cli.js`).** A small Node launcher installed on every platform; agents invoke `node .phanes/scripts/cli.js <cmd>`, which resolves identically in PowerShell, cmd, and Git Bash and forwards to the platform dispatcher. This fixes the failure where a bare `phanes` was "command not found" in a sub-agent shell. A generated project cannot know which of the three shells Claude Code will use on Windows, and each rejects a different platform launcher. `phanes <cmd>` stays shorthand in the document; the invocation is stated once and carried in the agent template.
- **`effort:` frontmatter in the generated agent template.** Forward-compatible: honored on CLI dispatch, ignored on the in-session Task-tool spawn path until anthropics/claude-code #43083 lands (thinking directives remain the in-session depth lever). Omitted for haiku, which exposes no effort dial.
- **`mcpServers:` per-agent allowlist in the agent template**, gated by the consent selection and Phase 3 matching. When an agent is granted more than ~3 non-standard capabilities, their usage rules move into one generated `capability-map` skill (progressive disclosure) instead of bloating the always-loaded persona.
- **No Inline Secrets (§III).** Agents never inline a connection string, key, or token on a command line; command lines are logged verbatim by transcripts, OTel, and console captures, and credentials are read instead from the environment or a gitignored file. Carried in the operating-protocol template.
- **Companion Tool Detection.** The census recognizes a `/metis` command; when present, update runs invoke the Metis session-audit companion (harvest, ledger verification, adherence audit) and consume its report. No hard dependency in either direction.

### Changed
- **`api-monitor` renamed to `close-verifier`** across the chain rules, archetype table, roster requirement, tier tables, and report template, with a rewritten duty list reflecting its real role: the independent close-time verifier that re-derives the API baseline, independently re-runs the build/typecheck (never trusting a producer's self-report), reconciles applied-vs-approved, and observes the hot-file budget. Its independence from the architect/designer is now a stated non-merge invariant. Deployed projects keep the old agent name until their next update run regenerates the roster.
- **Model & Effort rubric re-grounded, re-stamped 2026-07-20.** Selection is tier-first, effort-second: a stronger model at moderate effort beats a weaker model at its ceiling, and past ~4 to 8 agent steps does so for fewer tokens. The anti-pattern is recorded explicitly: maxing effort on a smaller model is not a substitute for a tier bump.
- **Living-document budget discipline generalized.** The register's demote-on-close rule now extends to any living document carrying a running log/status/amendment section: closed entries collapse to one-line pointers in the same change set, running lists are capped, `doc-check` flags growth. A Single-Writer corollary keeps close-time summaries with the agent that already holds the content, rather than paying to re-inject context into a fresh writer.
- **T1/MCP boundary clarified.** A task whose verification inherently requires a service MCP (querying live external state) is not a T1; it promotes to T2, removing the contradiction of a T1-labelled agent making heavy MCP calls.
- **Template library re-stamped to `v3.0`** (manifest version, sanity stamp, every template stamp, CHECKLIST), and `cli.js` registered in the manifest, so the fetch-time version check stays satisfied.

---

## v2.6.1 (2026-07-17)

### Fixed
- **Update runs reconcile an existing script library instead of overwriting it.** v2.6's "acquire, do not author" step (Phase 2.5 Step 4) was written for a fresh install: an absent script library is filled from tested templates. On an update run a working library already exists, and it is not always a stale copy of the shipped templates. It may have been generated in the project's own language by an earlier version, kept as a recorded per project edit, or deliberately rewritten with a project specific safety behavior. Fetching over such a library traded a known good, project shaped set of scripts for a generic one and replaced the `phanes` dispatcher with a different runtime, orphaning the scripts it routes to. Step 4 now branches on `.phanes/config.json` and the files on disk: an absent library is fetched, a library already in the shipped runtime is re-fetched so upstream fixes propagate, and a library authored in another runtime or carrying a project specific guard is preserved and verified against the in document specifications rather than replaced. A real update run hit exactly this: a project with a script library authored in its own language, and a guard on its registry regeneration, would have had that library swapped for generic shell templates. The reconcile path makes preservation the defined behavior instead of a hand judged exception.

### Added
- **`templates.source` gains a `"preserved"` value.** `.phanes/config.json` now records `"preserved"` alongside `"fetched"` and `"generated"`, so an update run that keeps a project shaped library instead of fetching over it stays legible to later runs, and swapping a preserved library for the shipped templates becomes an explicit user decision rather than a silent side effect.

### Changed
- Template library re-stamped to `v2.6.1` with no change to script behavior, so the manifest version, the sanity stamp, and every template stamp stay equal to the prompt stamp, as the acquire step's version check requires.

---

## v2.6 (2026-07-17)

### Added
- **Script template library, fetched instead of regenerated.** The ten scripts that do not depend on the project's language (`new-file`, `loc-check`, `doc-check`, `register-check`, `doc-index`, `module-list`, `list-apis`, the `phanes` dispatcher, and the two hooks `hook-stamp-guard` and `hook-size-check`) now ship as tested reference implementations under `templates/` in the distribution repository, in both a Windows variant (`.ps1` plus a `.cmd` shim) and a POSIX shell variant. Phase 2.5 Step 4 fetches them pinned to the run's own version tag, sanity checks every file, installs them into `.phanes/scripts/`, and works through a shipped `CHECKLIST.md`. A bug fixed once in a template is fixed for every future install, which removes the largest source of variance between installs.
- **No path substitution.** The fetched scripts take no per project editing. Each one finds the project by walking up from the working directory to `.phanes/config.json` and uses only paths relative to that root, so there is nothing to adapt and nothing to get wrong. Project values (module list, comment syntax, documentation root, stamped trees) are read from `config.json` at run time; the size numbers stay baked constants. `config.json` gains `commentSyntax`, `docRoot`, `stampedTrees`, and a `templates` provenance block that records the version installed and whether it was fetched or generated.
- **Graceful fallback, no new dependency.** If the fetch fails (offline, rate limited, tag missing) or the manifest version does not match the running prompt, the install generates the scripts from the Step 4 specifications exactly as earlier versions did, and records the failure. Those specifications stay in `phanes.md` in full: they are both the contract the shipped templates are audited against and the offline definition. `regen-registry` and `api-diff` stay generated per project, since their extractors are specific to each language.

### Fixed
- **Enforcement hooks no longer block when run by hand.** Both hooks read the tool-call JSON from stdin, which the harness always pipes in. Invoked directly in a terminal with nothing piped, they used to wait on that read until interrupted; they now detect a terminal on stdin and exit 0 immediately, so a manual run can never leave an interpreter waiting.
- **Hook commands can no longer be anchored at the wrong project.** A real install wrote its Step 4b hook commands as an absolute path into the Phanes repository instead of the target project, so the enforcement hooks policed the wrong tree and never fired where they were meant to. Step 4b now binds hook commands to their project relative form, copied verbatim, and adds a mechanical read back of the merged `.claude/settings.json`: every Phanes hook command must contain `.phanes/scripts/` and must not contain a drive letter or a leading slash. Update runs rewrite any absolutized hook command back to its relative form and report the repair. The template scripts make the failure structurally impossible on the fetch path, since they carry no absolute paths at all.

---

## v2.5 (2026-07-17)

### Added
- **Hot-file budget: the always-loaded root files get a size discipline.** A real v2.3 install's `CLAUDE.local.md` register reached 149 KB (~38k tokens) of auto-loaded context, mostly completed-project narrative duplicating session summaries, written there because the register is the one file the next session is guaranteed to see. Storage is now classified by **context temperature** (§II Documentation Anti-Bloat): hot (auto-loaded, character budget), warm (tier-loaded, the 500-line ceiling), cold (deliberately navigated, bounded per file at birth). Growth is permitted only where context is not paid.
- **The register mandate gains mechanics** (Phase 2): ≤10-line entries (status marker + pointer lines), a binding routing rule (narrative → session summary; procedure → plans; durable facts → registry/architecture; the register gets the pointer), close-out archival in the same change set, and standing blockers (🛑) as a measured crop-exemption class written as trigger + rule + pointer in ≤3 lines.
- **`phanes register-check` (new script) + `hook-size-check` extension:** both hot files measured in characters on every edit, `OK` below 35,000, `SOFT-BREACH` to 40,000, `CROP-REQUIRED` above; completed-but-unarchived entries and the 🛑 section's size are reported too. api-monitor's report carries the status line as an end-of-chain observation; the register's single writer stays the primary.
- **The Cropping Operation:** a T1 documentation task, archive every ✅ entry, then compress the oldest low-activity 🟡 entries to pointer form (displaced facts written to their plan or session summary first, so the crop deletes copies, never knowledge), re-measure until below the soft limit. 🛑 entries and the active project's current step are never cropped. Update runs execute it as the first post-run task when they find a CROP-REQUIRED register.
- **Archive digests, condensed at the boundary:** closed register entries land in `documentation/archive/projects/<slug>.md` as ≤15-line template digests written by the Cleaner archetype's new `archivist` duty (sole writer, `haiku`-eligible, mechanical condensation). Plan paths and SS references are copied verbatim: they are the recovery paths, and the register is conventionally gitignored so git history cannot be assumed to hold the original.
- **Index rotation:** an `_index.md` grows one line per child forever, the one cold-storage read that accumulates. Indexes now respect the 500-line ceiling; `phanes doc-index` rotates a crossing index mechanically (newest ~100 entries inline, older entries collapsed into range lines pointing to a frozen `_index_archive.md`). Content files never move; pointer stability is why rotation happens at the index layer only.

---

## v2.4 (2026-07-16)

### Changed
- **Registry flattening: the two-tier registry becomes one curated registry plus a machine baseline.** With `semble` (hybrid code search) and Serena (symbol navigation) in the pre-flight, the generated tier 1 registry lost its read role, a live index query answers "does an API already exist?" fresher than a generated listing ever can, with zero staleness window. What survives of tier 1 is its diff role, and a diff baseline is data, not documentation. Tier 2, deprecations, contracts beyond signatures, anti-patterns; the knowledge code search cannot see, now IS the registry.
  - **`documentation/registry/` is the curated registry** (formerly tier 2): one annotation file per module, 30-entry target ceiling, architect/designer remains sole writer. The `tier1/`/`tier2/` subfolders are gone.
  - **The generated API surface is demoted to a machine baseline** at `.phanes/registry/<module>.json`: api-monitor's diff substrate and `list-apis`' data source, written only by `phanes regen-registry`, read directly by no agent. It lives outside `documentation/` entirely, outside the doc ceiling, outside indexing, outside agent reading lists.
  - **Duplicate-API prevention is search-first:** the architect's mandate is now `semble search` for an existing API where installed, `phanes list-apis <module>` as the always-available fallback, plus the registry annotations for affected modules.
  - **T2/T3 no longer preload API slices:** the tier table queries the API surface on demand instead of front-loading generated listings into context.
  - **Terminology collision removed:** "tier" now means exactly one thing in the document, the T1/T2/T3 workflow tiers.
  - Scripts keep their names (`regen-registry`, `api-diff`, `list-apis`); only output and read paths change. `api-diff` against a git ref now extracts the old surface from that ref's source rather than reading historical baseline files.
- **API-contract awareness in the baseline:** for a project that exposes a network-facing API (HTTP/REST, GraphQL, gRPC), the baseline is extracted from the declared public contract, an OpenAPI/Swagger document, a GraphQL SDL, or `.proto` files, not from internal exported symbols, because the contract is what must not drift silently. Phase 1 detects the API surface (mirroring the UI-surface detection); `regen-registry` extracts it as its own baseline slice so `api-diff` flags a removed field or a changed response shape. Symbol extraction stays the default where no network API exists; a project that merely calls external APIs generates no slice.
- **In-run migration for v2.0, v2.3 installs:** the next update run moves `tier2/*.md` up to `documentation/registry/` byte-identical (verified by git diff), regenerates the baseline into `.phanes/registry/`, deletes the generated `tier1/` folder (regenerate-class; nothing lost), and reindexes. No `/phanesupdate` required.

---

## v2.3 (2026-07-15)

### Added
- **Bounded Fan-Out (new §II principle):** a hard width budget of 5 sub-agents in flight at once, tier-independent, scouts count against their spawner, parallel perspectives keep their 2 to 5 band. Wider sweeps are never hand-rolled: the harness's native large-scale orchestration (where one exists) is the sanctioned escalation path, recommended to the user and never invoked silently. Every session summary now records a fan-out ledger (sub-agents spawned per phase, peak in flight) so budget breaches are visible across runs.
- **Compaction Survival (new §II principle):** every run keeps a run-progress ledger at `.phanes/run-progress`, one line per completed phase, opened in Phase 0, closed at the Phase 5 sign-off. An unclosed ledger at run start means a prior run died mid-flight; the new run resumes from the recorded phase instead of blindly restarting. And because long sessions compact lossily, a run that can no longer see a later phase's verbatim text re-reads the installed prompt from disk before proceeding, re-read, never recall.
- **Dual-verdict Critic (R.A.C.R.S. amendment):** every Critic audit closes with two mandatory verdicts, spec compliance and quality, each an explicit pass or fix_required. A report missing either verdict is returned fix_required without content review, and the orchestrator never pre-judges findings on the Critic's behalf. Enforced in the chain design rules, the agent template's JSON contract, and the report template.
- **Reference, don't paste (Context Injection Protocol, item 4):** injected material past ~2,000 tokens travels as a file path plus a structured brief, never as pasted content, handoff boundaries are where multi-agent chains silently lose context, and a reference read at the destination cannot be truncated by the sender's summarizing hand.
- **`semble` is now a pre-flight install (fourth MCP server):** hybrid code search (BM25 + static embeddings, tree-sitter-aware chunking) so agents find the exact snippet instead of sweeping a module with grep and reading whole files, the largest single token sink in a run. Two tools of schema (`search`, `find_related`), CPU-only, no API key, no GPU, no external service, and it rides the `uv` the pre-flight already installs for Serena, so it adds no prerequisite. Indexes build on demand and re-index on file changes; there is no separate index step and no bootstrap-time cost. `semble` finds the code, Serena navigates it, the Phase 4 rubric keeps them distinct, and index-first is now the first rung of every agent's analysis ladder. It is the one MCP call a T1 task may make, and only to locate a genuinely unknown file. Failure degrades to Grep/Glob sweeps: costlier, never incorrect.
- **Code-index slot discipline:** the Phase 3 matching rubric now treats the code-index slot as filled. A discovered code-index server (symbol-graph, repo-map, rival hybrid search) is granted only where it demonstrably beats `semble` for the project's stack, and where granted, `semble` is not granted to that agent, two servers doing one job is two schema taxes for one capability.

### Changed
- Model & Effort rubric re-reviewed 2026-07-15 (Haiku 4.5 / Sonnet 5 / Opus 4.8, unchanged assignments) and now records that per-sub-agent reasoning-effort control is not exposed by the harness, thinking directives remain the depth lever.

---

## v2.2.1 (2026-07-15)

### Added
- **Frontend design skill in the pre-flight:** every run now ensures the official `frontend-design` plugin (`claude-plugins-official` marketplace) is installed, deliberate, non-templated visual design guidance that costs zero context until invoked, so the install carries no schema tax. Every generated agent carries the rule that UI- and frontend-related tasks begin by loading the skill via the Skill tool. Not mandatory: if the marketplace is unreachable or the install fails, the run records a TODO and continues, and agents treat the skill as a conditional enhancement ("if available") like every discovered capability. A fresh install arms on the next session, like the enforcement hooks.

---

## v2.2 (2026-07-15)

### Added
- **Self-version check (Phase 0, Step 0):** every run fetches the distribution repository's `phanes.md`, compares version stamps numerically, and refreshes every installed copy when upstream is newer, then stops with a verbatim re-run notice so no run ever executes a stale spec. The download is sanity-checked (a 404 page never clobbers a working install), a newer local copy is never downgraded, and an offline fetch degrades gracefully to a session-summary TODO.
- **Installed-Capability Leverage (new §II principle):** every run inventories user-installed MCP servers, plugins, skills, slash commands, and non-Phanes agents, then wires *matched* capabilities three layers deep, per-agent least-privilege grants via a Phase 3 matching rubric, generated "Discovered servers" entries in each agent's MCP Usage Rubric, and a regenerated Installed Capability Register in the root CLAUDE.md. Everything discovered is a conditional enhancement ("if available" phrasing; no chain ever blocks on it); failures are diagnosed and remembered in `.phanes/config.json` for later runs. Phanes never installs, uninstalls, or reconfigures what the user set up.
- **Visual Evidence Mandate (new §II principle):** UI changes can no longer be approved by prose. Proposals must declare target viewports, affected screens/states, and the reference design (the Critic returns `fix_required` without the declaration); after apply, a designated visual verifier, a duty carried by an existing roster agent, preferring the frontend specialist, never new headcount, captures before/after evidence at the declared viewports and runs a mechanical pass/fail checklist (hierarchy, clipping, focus/hover states, contrast, per-viewport layout, reference match, adjacent-UI regression). Output is a flag, not a fix. Soft gate: absent or failing capture tooling is diagnosed, remembered across sessions, and surfaces as `VISUAL: UNVERIFIED` plus a user-eyeball request, never a silent pass.

---

## v2.1.2 (2026-07-11)

### Added
- **Termination discipline for generated scripts** (Phase 2.5, Step 4, hard rule): every script in the generated library must be one-shot, non-interactive, and self-terminating. No input prompts (`input()`, `Read-Host`, readline), no watch/poll/serve loops, no detached or background child processes; any child process is invoked synchronously and awaited. Sub-agents and harness hooks run these scripts headlessly, so a script that waits or lingers hangs the tool call and leaves orphaned interpreter processes accumulating on the user's machine. An audit of existing bootstrapped projects (Python, Node, PowerShell libraries) found all generated scripts already conform; the rule makes it mechanical instead of lucky.

---

## Docs, 2026-07-11

### Added
- README: **Companion tools** section expanded with [Philia](https://github.com/Aloim/philia), a collaborative browser-shared terminal for watching and driving a Phanes-managed agent team together over a password-protected link, and [Mosyn](https://github.com/Aloim/mosyn), shared decentralized project memory for Claude Code agents. The section now opens with the modularity stance: Phanes keeps its core to one file, and every companion is a standalone tool that also cooperates with the structures Phanes generates. A matching note sits in the README intro.

---

## v2.1.1 (2026-07-10)

### Changed
- **Model rubric: every Critic now runs on Opus** (was: Sonnet for standard Critics, Opus only for the final T3 Critic). The Critic is the terminal quality gate on every chain, a missed defect costs more than the review.

---

## v2.1 (2026-07-10)

### Added
- **DeepWiki MCP** joins the pre-flight (hosted service, HTTP transport, three tools): agents ask focused questions about external GitHub dependencies and consume digest answers instead of pulling dependency source into context. Graceful degradation like the other servers.
- **MCP Usage Rubric** embedded in every generated agent: when Serena, context7, and DeepWiki actually save tokens, and when to make no MCP call at all (default: a targeted read under ~2,000 tokens beats any MCP call). DeepWiki is never used for the project's own code, the registry and documentation tree own that.
- **Pre-flight token-discipline note**: MCP tool schemas cost context every session (~1,000 tokens per tool); Phanes installs exactly three small-schema, high-leverage servers and warns against large tool-count servers (use the `gh` CLI, not the ~90-tool GitHub MCP).
- Tool assignment tightened: `context7`/`deepwiki` granted only to Planner/Architect, Analyzer, and scout-eligible agents; Executor and Patch-Author carry no MCP tools, unlisted tools cost their invocations nothing.

---

## v2.0.2 (2026-07-10)

### Changed
- `PhanesUpdate.md` renamed **`PhanesUpdateExperimental.md`**, the migration prompt has not been validated against real-world installations. Warnings added throughout: the prompt itself now refuses to run until the user confirms an external backup (remote push or full project copy) and explicitly acknowledges the risk; the README and `phanes.md`'s migration pointer carry the same warning. Treat a migration as **effectively irreversible** once the migration branch is merged.

### Changed (branding)
- Unified to plain **Phanes** across all published files; edition naming removed from the version stamps, README, and this changelog's header.

### Added
- README: **Companion tools** section referencing [Charon](https://github.com/Aloim/charon), the standalone dead-code and duplicate-code audit prompt that cooperates with Phanes-managed projects.
- README: table of contents with section links, and a **How to use** section covering first-run guidance (seed an empty repo with a `plan.md`; steer the setup with directives after the command; restart afterward) and re-run cadence (small project: freely, several times a day; before implementation plans: run and inject the plan; session bookends; large project: once or twice a day). Plus a full copyediting pass for plain readability.

---

## v2.0.1 (2026-07-10)

### Added
- **`PhanesUpdate.md` v1.0**, the migration prompt for projects carrying a pre-v2.0 Phanes install. Self-updates your `/phanes` command from this repository, fingerprints the installed version, then migrates on a dedicated branch behind a generated, evidence-verified checklist. Accumulated knowledge (tier 2 annotations, session summaries, architecture snapshots) is preserved byte-for-byte; superseded artifacts are archived, never deleted; you review and merge the branch yourself.
- README: "Migrating an older install" section, step-by-step setup guide for first-time users, and this changelog.

### Changed
- `phanes.md`: on detecting a pre-v2.0 install, an update run now stops and directs to `/phanesupdate` instead of improvising a partial migration (with an exception for PhanesUpdate's own regeneration hand-off).
- Internal session summaries removed from the distribution repository, this changelog is the public release history.

---

## v2.0 (2026-07-09)

### Added
- **Harness hook enforcement**, `.claude/settings.json` hooks generated at bootstrap: a blocking PreToolUse guard denies creation of unstamped new files; an advisory PostToolUse check runs size and documentation audits on every write. Mechanical rules can no longer be forgotten under context pressure. (Hooks arm on the next session, the run ends with a restart notice.)
- **Scout pattern**, specialists spawn ad-hoc, read-only subagents to fetch and digest bulky one-time context (module surveys, test logs, registry sweeps), governed by a strict cost guard so a spawn always pays for itself in preserved specialist context. Depth-capped, digest-only, never delegated judgment.
- **Documentation anti-bloat & index-first navigation**, 500-line soft ceiling on living docs; every `documentation/` folder carries a generated `_index.md` (new `phanes doc-index` script is their sole writer); agents locate knowledge by descending indexes instead of scanning trees; tolerant extraction indexes pre-existing files without editing them; frozen history (session summaries, dated snapshots) is never edited to conform.
- **Tiered documentation weights**, T1: one-line session-summary entry; T2: report; T3: plan + reports.
- **Dated model rubric** (reviewed against Haiku 4.5 / Sonnet 5 / Opus 4.8; re-validated on every update run), Sonnet default for coding and review, Haiku for scouts and mechanical work, Opus for architecture and synthesis.
- Windows PowerShell pre-flight variant; version stamp; roster ceiling (6 to 10 agents, 50-word descriptions).

### Changed
- **Review is universal**, T1 quick fixes are no longer exempt from the Critic; review depth and paperwork scale with tier, review presence never does.
- Chain termination order fixed and made explicit: Synthesizer (parallel work only) → Critic → api-monitor (T2/T3) → primary, the artifact applied is always the artifact audited.
- Run-type detection keyed solely on the `.claude/.phanes` marker (a bare `.claude/` directory no longer misreads as an existing install).
- CLAUDE.md placement: project root + module roots only, replacing per-subfolder sprawl.
- The change-set-generating Executor renamed **Patch-Author**, resolving the duplicate-Executor ambiguity.
- Serena: installed on first run, conditional everywhere after, generated agents degrade gracefully without it.

### Removed
- `sequential-thinking` MCP server, native extended thinking (`think` / `think hard` / `ultrathink`) replaces it; drops the Node/`npx` dependency.
- MCP `memory` server, the documentation tree is the single memory substrate; two substrates drift.
- The MCP pre-flight STOP gate, failed installs degrade gracefully and are logged as TODOs.

### Fixed
- Typos inside verbatim payload blocks that were stamped into every bootstrapped project ("treat them as guidance").
- The root-CLAUDE.md exclusion contradiction and the T1 review-exemption contradiction.

---

## v1, initial release

The original single-file bootstrap prompt: repository comprehension, two-tier API registry, script library, R.A.C.R.S. review cycle, tiered workflows, and the generated sub-agent roster. Preserved verbatim in [`older version/phanes.md`](older%20version/phanes.md).
