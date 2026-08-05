<!-- DOC | Verbatim archive of the v3.3.2-retired CLI-spawn effort bridge (effort_class rungs, the claude -p bridge, bridge-transport persistence clauses), kept so per-agent effort can be reinstated rather than reinvented -->
<!-- DOC DISCIPLINE | Soft ceiling: 500 lines. One topic per file; structure under ## headings.
     The DOC line above feeds `phanes doc-index`, keep it accurate; it is this file's line in _index.md.
     If this file exceeds the ceiling: split it into a same-named folder of focused topic files;
     carry both header lines into every part; update every inbound reference in the same change set;
     finish by running `phanes doc-index`.
     Consumers: NEVER bulk-read documentation folders, read _index.md first, load only what you need.
     Audit: `phanes doc-check`. -->

# Retired Effort Bridge (v3.3.2 archive)

Deleted from `phanes.md` by Task 11 of the v3.3.2 release (2026-07-28). This document is the sole surviving record of the deleted text and exists so the mechanism can be reinstated by copying it back, not by reinventing it.

## 1. What this is

A verbatim archive of the per-agent effort-delivery machinery removed from `phanes.md` in Phanes v3.3.2. It is kept so the mechanism can be reinstated later by copy and paste rather than reinvented from scratch, should either precondition in Section 4 occur.

Nothing in Section 3 is paraphrased. Every quoted block is reproduced character for character from its source (the pre-deletion v3.3.1 text of `phanes.md` for every block except Section 3.8, which is sourced from `templates/prompts/agent-definition.md`, named at that block), inside a fenced code block so its own markdown syntax (bold, backticks, tables, the nested command fence, and the HTML comment marker) is preserved as literal text rather than rendered or silently swallowed. Where a block is an excerpt rather than a whole passage (Sections 3.3, 3.6, and 3.7), the surrounding prose says so and the excerpt boundary is exact, never a paraphrase of the trimmed material. Only the material outside the fenced blocks is fresh prose written for this archive.

## 2. Why it was retired

Phanes v3.3.2 flattens the effort dial: every non-haiku agent, across every tier and archetype, now runs at a single reasoning-effort level, `high`. Earlier versions (v3.3 and v3.3.1) authored each agent's effort as a relative rung, `effort_class: baseline | elevated`, resolved against a session baseline that could itself be `medium`, `high`, or `xhigh` (the resolution table in Section 3.1). With `high` fixed as both the floor and the ceiling for every such agent, that resolution table has nothing left to resolve: there is no lower baseline to escalate from and no higher rung to escalate to. The rung scheme, and everything built to deliver a resolved level above the session baseline, became dead code in the same change.

The bridge itself existed for one reason only: the in-session Task/Agent tool does not read the `effort:` frontmatter field on any spawn path (anthropics/claude-code #43083, open as of this writing). The only lever that actually moves an agent's reasoning effort is the SESSION's own effort dial, set once at launch and shared by the orchestrator and every in-session Task agent. To run a single agent hotter than that session dial for one step, v3.3 and v3.3.1 had no choice but to launch that agent as its own separate `claude -p` CLI process at the desired `--effort` level, then keep resuming that same process (`claude --resume <session_id>`) for the rest of the batch rather than pay the cost twice. That cost was real and measured: roughly 80,000 tokens per fresh CLI spawn before any work happens at all, a cold cache plus a full reload of the system prompt, tool and MCP schemas, and the hot project files. The bridge existed only because that entry tax was cheaper than running the whole session hot.

Flattening effort to a single `high` level removes the need for that lever entirely: every non-haiku agent already runs at the level the bridge used to exist to reach, riding the warm in-session cache instead of paying the entry tax. A separate point worth stating plainly: `model:` frontmatter is a different mechanism from `effort:` and is honored natively by the in-session spawn path today; it was never affected by issue #43083 and never needed this bridge.

Correction: an earlier draft of this section said the roles that stay Opus in v3.3.2 are "the Critic archetypes and the Orchestrator/Architect roles", two roles. That was wrong on the roster itself, not just on the count. Per Task 11 Step 1's replacement table and Step 2's scope note, Opus is kept in exactly two PLACES, and both are scope-limited to a pass, not granted to a role generally: (1) the initial plan-authoring pass together with the Critic pass that reviews that plan, through plan close and any Reflect re-reviews within it, and (2) the security-review specialization, always. Nothing else runs Opus. The Orchestrator role runs Sonnet 5 at `high`, the same as every other default agent, not Opus. The architect/designer is Opus only for the single initial plan-authoring pass; every later in-batch invocation of it (a renegotiation follow-through, a mid-plan amendment, resuming for a later step) runs Sonnet 5 at `high`, and so does every in-batch Critic pass, only the plan-review Critic pass itself is Opus. Both surviving Opus contexts get their strength from the `model:` field the harness already reads correctly, not from any effort escalation, so neither needs a bridge.

One distinction matters most for anyone reading this later: deleting the bridge removes a TRANSPORT, never the persistence FEATURE. The bridge was one of two transports Agent Persistence (v3.3) could resume a worker over: in-session (the harness's own agent-continuation affordance) and bridge (`claude --resume`). In-session resume is untouched by this retirement and continues to carry the persistence feature for every worker; only the CLI-spawn transport, and the effort-resolution machinery that decided when to reach for it, is gone.

## 3. What was removed

Source for every block below: `phanes.md` as it stood at v3.3.1, immediately before the Task 11 deletion in this same v3.3.2 release. No em dashes or en dashes were found in any of the captured text below; nothing needed to be preserved under that exemption.

### 3.1 Rubric: Model & Effort Selection, the parts removed or rewritten

Correction: an earlier draft of this archive claimed the five-row model-tier table survived untouched. That was wrong. Task 11 Step 1 replaces it wholesale with a new four-row table (`haiku`, `sonnet` at `high`, `opus` for the plan-authoring chain, `opus` for the security-review specialization). The old table's third column carried the only recorded mapping from archetype to elevation eligibility (which roles were allowed to be lifted above baseline, and under which trigger), so it is captured verbatim below, not skipped.

Update: the anti-pattern paragraph on maxing effort on a smaller model, immediately below this material in `phanes.md`, WAS edited after this archive's first pass. Task 11 Step 11b(a), added to the plan after that pass, keeps the paragraph's tier-first substance (maxing effort on a smaller model is not a cheap substitute for a tier bump, the token-cost argument, "escalate the tier first, only then trim effort") but removes its closing sentence outright, since that sentence presupposes the now-deleted variable baseline and discretionary escalation lever. The closing sentence is captured verbatim below, immediately after the harness-reality blockquote and the resolution table, which were deleted outright with no replacement text.

**The five-row model-tier table (rewritten by Task 11 Step 1; this is the table itself, replaced wholesale):**

```markdown
| Model (tier) | Effort class | Assign to |
|--------------|--------------|-----------|
| `haiku` (Haiku 4.5) | (no effort dial, omit the field) | Scouts, retrieval, formatting, indexing, archive-digest condensation (Phase 2 register mandate), mechanical transforms a script or test suite guards. **Not** the default for authored code, its higher defect rate turns the Critic into an iteration engine, and each Reflect loop (re-work + re-review) costs more than writing it right once. |
| `sonnet` (Sonnet 5) | `baseline` | **DEFAULT** for coding agents, Analyzers, Validators, Optimizers, and frontend/UI specialists. Best accuracy-per-token for implementation and analysis. |
| `opus` (Opus 5) | `baseline` | **All Critics (every tier).** The terminal quality gate on every chain, a missed defect costs more than the review. **Elevate per step** when the review is security- or money-critical (elevation trigger 1, The Orchestrator Role). |
| `opus` (Opus 5) | `baseline` | **The Orchestrator role** (engaged plan runs, v3.2): per-step tier triage, chain composition, effort resolution and elevation, batch SS authorship. One wrong routing decision wastes an entire worker chain, which dwarfs the tier premium. Rides the session baseline in-session; never routinely CLI-spawned. |
| `opus` (Opus 5) | `baseline` | Architect/designer, Synthesizer/Arbiter. **Elevate per step** for high-ambiguity or cross-module design, or security- or monetary-system design (elevation triggers 1 and 2, The Orchestrator Role). Reserve the deepest reasoning for judgments that earn it, per step, never as a standing property. |
```

**The harness-reality blockquote and the resolution table (deleted outright, no replacement text):**

```markdown
> **Effort control, the harness reality (verified 2026-07-21).** The `effort:` frontmatter is **not read natively on any in-session spawn path** today: the Task/Agent tool has no effort input and ignores the field (anthropics/claude-code #43083, **open**; the related #64033 Workflow `agent()` effort and #65598 frontmatter-effort requests are **closed as duplicates** of it). The **only** working lever is **session-level effort**, shared by the orchestrator and every in-session Task agent. Set it **at launch** with `--effort <level>` or `CLAUDE_CODE_EFFORT_LEVEL=<level>`; **never** `/effort` or `/model` mid-run, both persist to the **global** `~/.claude/settings.json` and leak into other projects and parallel sessions (#57618, #49076). Because that dial **is the orchestrator's own effort** and cannot be raised cleanly mid-run (project `settings.json` is read once at startup, not hot-reloaded), **launch at `medium`, the recommended baseline; choose `high` or `xhigh` only when you want the entire run hotter.** Effort is authored as a RUNG relative to that dial (`effort_class`, v3.3), not as an absolute level; the orchestrator resolves it at dispatch per the resolution table below. Haiku has **no** effort dial; the baseline never touches haiku agents, so omit the field for them. To lift a specific agent **above** the baseline for one step, use the temporary CLI-spawn bridge in "Per-Agent Effort Delivery" below. When #43083 lands, the resolved level is passed natively on the Task tool and that bridge is deleted.
```

```markdown
**The resolution table (v3.3).** `effort_class` is relative; the orchestrator resolves it to an absolute level at dispatch, against the session baseline:

| Session baseline | `baseline` resolves to | `elevated` resolves to |
| --- | --- | --- |
| `medium` (recommended default) | `medium` | `high` |
| `high` | `high` | `xhigh` |
| `xhigh` | `xhigh` | `xhigh` (ceiling, no escalation possible) |

Escalation is `+1` only, upward only, never `+2` (a user who wants `xhigh` anywhere launches at `high`), never downward, and never sticky. The resolved level is clamped to the `medium`..`xhigh` band AFTER resolution, so no baseline value, corrupted or hand-edited, can escape the band. Every shipped archetype is `baseline` class; `elevated` exists as a user lever for pinning an archetype hot in their own project, nothing ships with it set.
```

**The anti-pattern paragraph's closing sentence (removed by Step 11b(a); the paragraph's first four sentences, the tier-first substance, are NOT reproduced here since they survive unedited in `phanes.md`):**

```markdown
A `medium` baseline makes "just escalate it" a more tempting reflex than it was; the ordering is unchanged, tier first, effort second, and discretionary elevation is never a substitute for a warranted tier bump.
```

### 3.2 Per-Agent Effort Delivery, the entire subsection

This was a complete `####` subsection of `phanes.md`, immediately following the material in 3.1 above. Reproduced whole, including the HTML comment marker that preceded it (that marker states its own intended retirement path and is part of the record) and the fenced spawn/resume command block it contained.

````markdown
<!-- TEMPORARY (added 2026-07-21, remove when anthropics/claude-code #43083 ships): the entire "Per-Agent Effort Delivery" subsection below exists ONLY to work around the harness having no in-session per-subagent effort. When #43083 lands, DELETE this subsection and this marker: per-agent effort becomes native on the Task/Agent tool, the orchestrator passes the level it resolved from effort_class directly at spawn, and no CLI process is needed. Deleting the bridge removes a transport, never the persistence feature: in-session resume carries it. -->

#### Per-Agent Effort Delivery (TEMPORARY bridge, retire when #43083 lands)

**The effort band.** Legal effort values are `medium | high | xhigh`. `low` is banned (untrusted floor), `max` is banned (ceiling). The clamp applies to the RESOLVED level, after rung resolution (v3.3), never to the authored `effort_class`, which has no absolute value to clamp; a malformed or hand-edited baseline can never drop a resolved level below medium or lift it above xhigh.

**The baseline is the orchestrator's own dial, and it is DECLARED, not sensed (v3.3).** Session effort governs the primary (orchestrator) agent AND every agent spawned in-session via the Task tool, and it cannot be changed cleanly mid-run. Launch the session at **`medium`**, the recommended default, with `--effort` or `CLAUDE_CODE_EFFORT_LEVEL`; the orchestrator delegates its deepest reasoning to per-step elevation rather than carrying it inline. The primary session states the session's effort level in the Orchestrator's spawn prompt (§III rule 11). The Orchestrator MAY cross-check it against the `CLAUDE_EFFORT` environment variable (present on current builds, verified 2026-07-26 on v2.1.220, but undocumented, so never the sole source); a mismatch is recorded in the batch SS, never silently reconciled. Declaration absent and variable empty: assume `medium`, the under-spending direction. Non-haiku Task agents ride this baseline (running a touch hot is the safe direction); haiku agents ignore it.

**The bridge, upward only.** The in-session Task tool cannot lift an agent above the baseline. To run an agent the Orchestrator has ELEVATED for a step (see The Orchestrator Role, hard budget 2 per batch), spawn it as its own CLI process, detached, in print mode:

```text
spawn:   claude -p "<full injected-context prompt>" --agent <name> --effort <resolved level> \
           --permission-mode <non-interactive mode> --output-format json \
           --exclude-dynamic-system-prompt-sections > reports/bridge/<agent>-<n>.json
resume:  claude --resume <session_id> -p "<next instruction>" --effort <same resolved level> \
           --permission-mode <non-interactive mode> --output-format json > reports/bridge/<agent>-<n+1>.json
```

Launch detached via your shell's background mechanism (the Bash tool's background mode); print mode writes one JSON object on process exit, and that artifact is the collection channel. `--bg` is **NOT** used: it conflicts with `-p`, and headless resume requires `-p`, so a `--bg` spawn is the one form that cannot resume.

* **Session capture and reuse:** read `session_id` and the `usage` block from the spawn JSON and record both in the handle table (Agent Persistence, The Orchestrator Role). Every later need for the same agent this batch RESUMES that handle instead of respawning, so the entry tax is paid once per elevated agent per batch, not once per invocation.
* **`--effort` MUST be re-passed on every resume.** It is silently dropped otherwise (anthropics/claude-code #66005, open): the resumed session falls back to default effort resolution, and the re-pass also restores prompt-cache reuse. Do not simplify it away.
* **Which agents:** whatever the Orchestrator elevated on this step, 0 to 2 spawns per batch. With an `xhigh` baseline the resolution table gives elevation nowhere to go: run everything in-session and skip the bridge entirely.
* **Effort source:** the resolution table applied to the declared baseline, never a raw frontmatter read.
* **Never spawn downward.** Do **NOT** CLI-spawn an agent merely to run it *cheaper* than the baseline. Each fresh process pays a measured entry tax of roughly 80,000 tokens before any work (cold cache plus a full reload of the system prompt, tool and MCP schemas, and the hot files), which exceeds the reasoning tokens a lower effort would save. Let lighter agents ride the baseline in-session, and send genuinely cheap work to haiku (no dial) by tier.
* **Permissions:** a detached process cannot answer permission prompts (it would hang), so it must run in a non-interactive mode. Keep each agent's `tools:` scoped to least privilege (already mandated) so a non-interactive mode grants only the authority that agent needs.
* **Collection:** poll for the handle artifact between other work, bounded cadence, never a busy-wait loop; on artifact presence read the result, `session_id`, and `usage` from the JSON; on a failed or vanished process re-dispatch or escalate. Bounded Fan-Out (max 5 in flight) still applies, and a batch never returns with a bridge spawn still in flight.
````

### 3.3 Agent Persistence, the bridge-transport clauses

These clauses lived inside the larger "Agent Persistence (v3.3): resume before respawn, scoped to the batch" section, which is NOT being deleted and is not reproduced here in full (it also covers in-session resume, which is untouched). Only the sentences and table row that named the bridge transport specifically are captured, each below as an exact excerpt of the original bullet, not the whole bullet.

The "Spawn at first use" and "Resume match rule" bullets are reproduced whole; their bridge-referencing sentences are the parts that mattered, but the full bullet text is short enough to quote entire. The "Recycle before bloat" bullet is only excerpted: its one bridge-handle sentence is quoted below, not the bullet's bold heading or its in-session-handle half, which was reworded rather than left unchanged (the post-deletion text drops the "In-session handles:" label, since there is no longer a "Bridge handles:" counterpart for it to contrast against) and is not reproduced here. The excerpt is needed because the handle table's `resolved effort` and `resume count` columns, quoted before it in the fenced block below, are otherwise unexplained without the 400,000-token recycle threshold that governed a bridge handle's lifetime.

Update: this archive's first pass flagged that Task 11's dangling-reference sweep (Step 12) greped case-sensitively for lowercase `bridge`, so it would have missed this bullet's "**Bridge** handles" (capital B) and left it orphaned. That finding is now acted on in the plan: Step 12's sweep is case-insensitive (`grep -in`) and its own text cites this exact bullet by name, so the sentence will be surfaced and removed by Task 11, not left stale. The excerpt captured below remains correct either way.

```markdown
* **Spawn at first use, resume by handle.** No pre-spawned idle agents (an idle subagent cannot exist on this harness). In-session transport: the spawn tool returns an agent handle; continue it with the harness agent-continuation affordance (`SendMessage` on current builds). Bridge transport: `claude --resume <session_id> -p ...` per the bridge above. Where a transport cannot resume, fall back to handoff digest plus fresh spawn, a degradation path, not the expectation.
* **Resume match rule:** resume only when the chain calls the SAME roster agent (same definition, same specialization) AND the required resolved effort is satisfiable on the handle: a step needing a HIGHER level than the handle carries gets a fresh spawn (recorded normally in the ledger); a step needing a lower level resumes anyway, running warm a touch hot beats a cold spawn at the exact level.
* **The handle table** (batch ledger, internal): role, transport (in-session | bridge), handle (agent id | session_id), resolved effort, resume count, last usage reading (bridge only), status (live | retired | dead). A stale handle after interruption is visibly dead, never messaged.
```

Excerpt from "Recycle before bloat" (the bridge-handle sentence only):

```markdown
Bridge handles: read `usage` after every resume, retire the handle when cumulative context exceeds 400,000 tokens.
```

### 3.4 Batch session summary Effort record line

The mandatory batch-SS record-line format for the effort mechanism, and its explanatory parenthetical. The three sibling record lines (`Batch sizing:`, `Batch mode:`, `Persistence:`) are unrelated to the bridge, are NOT being deleted, and are not reproduced here.

```markdown
  `Effort: baseline <level> (declared | assumed), triggers <T> fired: <step id>/<trigger letter> elevated <agent> | declined: <reason> | refused: budget, elevations <M> of 2, resolved <agent>=<level>, ...`
  (Every trigger that fired appears with its disposition, `elevated`, `declined: <reason>`, or `refused: budget`. `triggers 0 fired` is the correct line for a batch where none did, and it is a different claim from a batch that fired two and elevated neither.)
```

### 3.5 Pinned-directives per-agent effort callout

This bullet lived in the generated `pinned:phanes` block that every project's root `CLAUDE.md` carries (the block Phanes regenerates every run), near the top of `phanes.md`'s own template for that block.

```markdown
> **Per-agent effort.** Session baseline effort = the orchestrating agent's launch dial (`high` default, `xhigh` design-heavy). The in-session Task/Agent tool IGNORES `effort:` frontmatter (claude-code #43083, open). To run an `xhigh` archetype ABOVE baseline (security/money critics, architect, synthesizer) you MUST CLI-spawn it; the in-session tool cannot lift effort. Before dispatching any such archetype, re-read phanes.md "Per-Agent Effort Delivery" and use the bridge. At an `xhigh` baseline the bridge has no upward use.
```

### 3.6 The elevation decision procedure (found in a self-sweep, not on the original extraction list)

Task 11 Step 5 rewrites the Orchestrator's per-step elevation clause inside the larger "Per batch, the Orchestrator MUST:" numbered list (item 2 of that list). Only that clause is excerpted below; the surrounding list item also covers tier triage and the grouping-mode decision, which are unrelated to effort, untouched by Task 11, and not reproduced here. The four elevation triggers themselves (security/authentication/credentials/money; cross-module or high-ambiguity; a step that already failed one Reflect loop; `batch_recommendation` reporting the step larger than estimated) are NOT reproduced again here since their conditions survive into v3.3.2 under a reworded lead-in (Section 5). One exception: trigger (c) originally carried a trailing rationale clause that Step 5's rewrite drops entirely, destroyed with no replacement text. It is excerpted first, separately, since it is not part of the MUST-consider/MAY-decline/MUST-record protocol that follows it:

```markdown
(c) the step already failed one Reflect loop, the second attempt earns more reasoning than the first;
```

What is captured next is the discretionary decision procedure built around the four triggers, which does NOT survive: the MUST-consider/MAY-decline/MUST-record protocol, the disposition labels, and the hard budget of 2. This excerpt begins and ends mid-sentence in the original (a trailing semicolon is exact, not a typo):

```markdown
**MUST consider, MAY decline, MUST record (v3.3).** Elevation stays discretionary, the Orchestrator may decline any trigger on cost or on judgment, but **every trigger that fires is recorded with its disposition** in the batch SS effort line, `elevated` or `declined: <reason>`. A silently ignored trigger is the failure this rule closes: elevation is delivered by CLI bridge spawn and therefore always looks locally expensive, so declining is the standing path of least resistance, and an unrecorded decline makes a run where two triggers fired and nothing happened indistinguishable from a run where nothing triggered. The record is what makes the heuristic tunable; it does not force the spend. Trigger (c) obliges the Orchestrator to carry per-step Reflect-loop counts into this decision, a repeatedly failing loop is the clearest signal in the set. Hard budget 2 elevations per batch, never sticky, never `+2`, a refused third trigger recorded as refused;
```

### 3.7 Template Contract frontmatter clause, phanes.md (found in the same self-sweep)

Task 11 Step 9 removes the `effort_class` clause from the Sub-Agent Definition Template Contract's frontmatter bullet in `phanes.md`. That bullet also documents `name`, `description`, `color`, `model`, `tools`, and `mcpServers`, none of which are touched; only the `effort_class` clause is excerpted, an exact substring of the original bullet, not the bullet entire:

```markdown
`effort_class: baseline | elevated` (resolved per the resolution table; OMIT for haiku; every shipped archetype is `baseline`)
```

### 3.8 Agent-definition template's `effort_class` field, a different file (found in the same self-sweep)

Task 11 Step 10 removes the `effort_class` line from `templates/prompts/agent-definition.md:8`, the fetched frontmatter template every generated agent definition is instantiated from. This is a different source file from `phanes.md`, but it is explicitly in Task 11's file list, and its comment carries detail not stated anywhere else in this archive: that the orchestrator passes the resolved level as `--effort` specifically on bridge spawns, and what changes once `#43083` lands. Reproduced whole, the entire line:

```markdown
effort_class: baseline | elevated  # Relative to the session effort dial, resolved by the orchestrator at dispatch (resolution table, rubric). OMIT for haiku (no dial). Shipped default is baseline for EVERY archetype; elevated is a user lever for pinning an archetype hot, nothing ships with it set. The orchestrator passes the RESOLVED absolute level as --effort on bridge spawns (temporary bridge, see rubric); when claude-code #43083 lands, the resolved level is what the Task tool consumes natively.
```

### 3.9 §III rule 11's effort-baseline declaration mandate (found in final-review verification, not on the original extraction list)

Task 11's rewrite of §III rule 11 ("Orchestrator engagement (scope check, v3.2)") kept the rest of the rule (the step-count threshold, the spawn-per-batch instruction, the narrowing exceptions) and replaced only its effort-declaration sentence with "The spawn prompt declares no effort baseline (v3.3.2): every non-haiku agent runs at the run's single level, `high`, so there is nothing per-agent left to resolve." Section 3.1's cross-reference to "§III rule 11" elsewhere in this archive names the rule but does not preserve the deleted sentence itself; captured verbatim below, an exact excerpt of the original rule, not the rule entire:

```markdown
Every orchestrator spawn prompt MUST declare the session's effort baseline (the level the session was launched at; readable via the `CLAUDE_EFFORT` environment variable when unknown), the value the Orchestrator resolves every `effort_class` against (v3.3).
```

### 3.10 Batch Renegotiation clamp (3), "a CLI bridge spawn is still in flight" (found in final-review verification, not on the original extraction list)

The pre-deletion "How the Orchestrator responds: adopt by default" bullet listed five renegotiation clamps; Task 11 deletes clamp (3) outright and renumbers the survivors down by one (the v3.3.2 overlap clamp moves from (5) to (4)). Captured verbatim below is the full pre-deletion clamp list, an exact excerpt of the original bullet:

```markdown
Check these clamps and nothing else: (1) the resulting batch would exceed 3 steps; (2) growth would cross a phase boundary; (3) a CLI bridge spawn is still in flight; (4) the Orchestrator's own context is already heavy (the early-close-out condition); (5) **(v3.3.2)** the absorbed step's working set overlaps a step already in the batch, a step edits a file another step already in the batch edits, or consumes another step's output; a batch is never part grouped and part per-step.
```

### 3.11 "The generated agent definition is self-carrying" restatement duty, pre-deletion text (found in final-review verification, not on the original extraction list)

Task 11 rewrote this bullet's restatement list (replacing the "effort resolution protocol" clause with a shorter "effort record duty" clause reflecting the flattened `high`-only scheme) and its `tools:` grant sentence (dropping the bridge from the Bash grant). Reproduced whole below, the entire pre-deletion bullet, an exact excerpt of the original:

```markdown
**The generated agent definition is self-carrying.** `.claude/agents/<projectSlug>-orchestrator.md` MUST restate, in its own operating protocol: the spawn-grant exception ("this agent is the sole non-scout archetype permitted to spawn agents; its workers may spawn scouts only, nothing deeper"), the batching rules, the batch renegotiation protocol (look-ahead block, adopt-by-default, the clamps including the overlap clamp, the mandatory SS sizing line), the grouped-batch protocol (the single overlap-only gate condition and the ambiguity-resolves-to-per-step rule, per-step Critic verdicts, per-step Executor checkpointing, the combined security pass per batch keyed by step id, Reflect over the failing subset only, the mandatory SS mode line), the Agent Persistence protocol (scope table, resume match rule, recycle triggers and the retire notice, handle-table duty, termination at batch close), the effort resolution protocol (the resolution table, the `+1`-only rule, the declared-baseline contract and its assume-`medium` fallback, the four elevation triggers, the consider-decline-record rule, the budget of 2, the duty to record EVERY fired trigger with its disposition in the SS effort line, and the duty to carry per-step Reflect-loop counts into trigger (c)), the early close-out right, the effort-bridge duty, and the receipt schema above, so the rules are visible at the point of use, not only in §II and §III. Its `description` field MUST state it is invoked ONLY by the primary session at plan launch, never mid-chain, and no other agent's Next Task table may route to it. `tools:` grant: Task (agent spawning), SendMessage or the harness's agent-continuation affordance (resuming persistent workers, v3.3), Write (batch SS and own report only), Bash (effort bridge and `.phanes/scripts/`), plus read/search tools per least privilege.
```

The `tools:` grant's Bash clause is the specific change Task 11 makes to this bullet's final sentence: `Bash (effort bridge and .phanes/scripts/)` above narrows to `Bash (.phanes/scripts/)` in the post-deletion text, since there is no longer a bridge for the orchestrator to shell out to.

## 4. Preconditions for reinstating

Two distinct events can make this mechanism worth reinstating, and they call for different amounts of it back.

**Precondition A: the session baseline drops below the ceiling again.** If a future version reintroduces a baseline below `high` for some or all non-haiku agents (for example, reverting to a `medium` default with `high`/`xhigh` as elevation targets, as v3.3 and v3.3.1 did), escalation becomes meaningful again: there is once more a floor to lift an agent's effort above. Under this precondition, restore all of what is archived here: the model-tier table and the `effort_class` rung scheme and resolution table (Section 3.1), authoring which agents are eligible for elevation; the CLI-spawn bridge (Section 3.2) as the transport that actually delivers a resolved level above the session dial, because issue #43083 is presumed still open under this precondition; the bridge-transport persistence clauses (Section 3.3); the elevation decision procedure with its disposition labels and budget of 2 (Section 3.6); and the `effort_class` frontmatter contract in both `phanes.md` and the agent-definition template (Sections 3.7 and 3.8), since without it there is no authored field for the resolution table to resolve.

**Precondition B: anthropics/claude-code #43083 lands.** If the in-session Task/Agent tool starts reading the `effort:` frontmatter field natively, or accepts a resolved effort level as a native spawn parameter, the situation is different: per-agent effort becomes native, and the CLI-spawn TRANSPORT (Section 3.2, the whole bridge subsection, and the bridge-transport half of Section 3.3) is no longer needed under any baseline configuration, high or otherwise. The orchestrator would pass the resolved level directly at spawn instead of shelling out to a separate process. But the `effort_class` RUNG SCHEME and resolution table (Section 3.1) become directly usable exactly as designed, now delivered natively in-session instead of over a bridge. Reinstating under this precondition means restoring Section 3.1 and rewiring its delivery to whatever native mechanism #43083 introduces, WITHOUT restoring the CLI-spawn machinery of Section 3.2, which stays retired for good under this path.

These are not the same reinstatement. Precondition A restores everything captured in Section 3, the bridge included. Precondition B restores the rung-and-resolution concept but never the CLI bridge itself. Confirm which precondition actually holds before copying anything back.

## 5. What was deliberately kept

Not everything the bridge touched was deleted, but not everything survives unchanged either; these are two different claims and this section separates them.

The four elevation triggers themselves DO survive into v3.3.2, under a reworded lead-in: (a) the step touches security, authentication, credentials, or money, (b) the step is cross-module or plan-marked high-ambiguity, (c) the step already failed one Reflect loop, (d) `batch_recommendation` reported the step materially larger than estimated. Trigger (a) now does double duty as the selector for the batch's combined security pass (Task 9). The batch session summary keeps a line naming which trigger fired on which step. One piece of trigger (c) does NOT survive: its original trailing rationale, "the second attempt earns more reasoning than the first", is dropped by the rewrite with no replacement, and is captured verbatim in Section 3.6 since it appears nowhere else in this archive.

What does NOT survive is the decision procedure built around those triggers, captured verbatim in Section 3.6: the discretionary MUST-consider/MAY-decline/MUST-record protocol, the disposition labels (`elevated`, `declined: <reason>`, `refused: budget`), and the hard budget of 2 elevations per batch. With a single effort level there is no elevate-or-decline choice left to make, so the effort record line itself changes shape: the format captured verbatim in Section 3.4 is the OLD, pre-deletion format, the one this archive preserves for reinstatement, not the line v3.3.2 actually writes. The replacement line records only that a trigger fired and on which step, with no disposition field at all.

This is a deliberate choice, not an oversight: it means a future reinstatement under either precondition in Section 4 starts from real usage data, which triggers actually fired, and how often, rather than reintroducing the mechanism blind. But it is thinner data than the pre-deletion record: it says a trigger fired, not what was done about it, elevated, declined, or refused on budget. That finer signal is exactly what Section 3.6 preserves the mechanism for producing again, should either precondition in Section 4 hold.
