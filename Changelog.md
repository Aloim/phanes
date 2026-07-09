# Changelog

All notable changes to **Phanes**. The authoritative version marker is the stamp on the first line of `phanes.md` — diff it against this repository before assuming your installed copy is current.

---

## v2.0.2 — 2026-07-10

### Changed
- `PhanesUpdate.md` renamed **`PhanesUpdateExperimental.md`** — the migration prompt has not been validated against real-world installations. Warnings added throughout: the prompt itself now refuses to run until the user confirms an external backup (remote push or full project copy) and explicitly acknowledges the risk; the README and `phanes.md`'s migration pointer carry the same warning. Treat a migration as **effectively irreversible** once the migration branch is merged.

### Changed (branding)
- Unified to plain **Phanes** across all published files; edition naming removed from the version stamps, README, and this changelog's header.

### Added
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
