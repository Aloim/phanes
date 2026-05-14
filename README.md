# Phanes

**Phanes** is an autonomous synthesis architect prompt for Claude Code — a bootstrap workflow that turns an empty (or messy) repository into an elite, opinionated, self-improving agentic ecosystem.

Run it once and Phanes will:

- Survey the repo and infer its true purpose, language, and module boundaries.
- Scaffold a documentation tree, registry system, script library, and tiered workflow under `documentation/`, `.phanes/`, and `.claude/`.
- Scaffold a dedicated `tests/` tree (unit / integration / e2e / fixtures / helpers).
- Generate a roster of deeply-scoped, world-class sub-agents (architect, critic, executor, api-monitor, etc.) wired together with deterministic handoff chains.
- Codify reusable workflows in `.claude/workflows/`.
- Update `CLAUDE.md` so the primary Claude Code agent knows how to triage, delegate, and review.

Re-run it any time. Phanes detects an existing install and upgrades agents and infrastructure in place.

## Usage

Inside Claude Code, invoke the prompt as a slash command (drop `phanes.md` into your `.claude/commands/` directory or run it directly via the orchestrator):

```
/phanes
```

Optional arguments are forwarded through `$ARGUMENTS`.

## Core principles

- **Procedure in scripts, judgment in prompts** — mechanical rules live in `.phanes/scripts/`, never in agent prompts.
- **Single-writer per artifact** — each registry tier, snapshot, and summary has exactly one owning agent.
- **No direct code modification by sub-agents** — coding agents produce reports; an Executor applies approved diffs after Critic review.
- **Tiered workflow (T1 / T2 / T3)** — context loaded matches the task scope; promotion required to escalate.

See `phanes.md` for the full specification.

## Layout produced on first run

```
documentation/        # session summaries, plans, architecture snapshots, registries
tests/                # unit, integration, e2e, fixtures, helpers
.phanes/              # scripts (new-file, regen-registry, api-diff, loc-check, ...)
.claude/agents/       # generated sub-agent definitions
.claude/workflows/    # codified multi-agent workflows
.claude/template/     # report.md template for sub-agent outputs
CLAUDE.md             # primary-agent operating instructions
CLAUDE.local.md       # live register of projects in motion
```

## License

MIT — see `LICENSE` if present, otherwise treat as unencumbered.
