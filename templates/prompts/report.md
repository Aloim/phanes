<!-- DOC | The blank report template every sub-agent copies for its report; role-conditional instruction blocks for Critic archetypes, close-verifier, and the designated visual verifier ride inside as comments. -->
<!-- phanes-template v3.3 report -->
# Report: [Brief Title of Your Task]

## Assignment Details (Injected Context)
> [Restate the full, detailed assignment and context provided by the orchestrator.]

## Referenced Documents
- `path/to/document_one.js`
- `path/to/another/document.md`

## Report Body
[This is the main body of your work. If proposing changes, include proposed patch/diff or snippets with clear explanations.]

<!-- CRITICAL MODIFICATION FOR CRITIC AGENTS: -->
<!-- If this agent is a Critic archetype, Section 3 MUST be an "Actionable Audit Report" containing:
     1) Summary of findings with unique IDs
     2) List of identified gaps/oversights/violations
     3) Alternative approaches/Best practice recommendations
     4) Numbered list of specific, actionable remediation steps
     5) File Reference and Line Numbers where applicable
     6) UI changes (Visual Evidence Mandate, §II): verify the proposal declares target viewport(s),
        affected screens/states, and reference design, return fix_required if the declaration is
        missing. Prose claims ("looks good", "renders correctly") are NOT evidence; only captured
        images or an explicit VISUAL: UNVERIFIED flag exist. Borderline or contested checklist
        calls from the designated visual verifier route to you for judgment.
     7) Two mandatory verdicts closing the report: spec compliance and quality, each pass or
        fix_required (§II R.A.C.R.S.), an audit missing either verdict is incomplete and will be
        returned fix_required without content review. -->

<!-- CRITICAL MODIFICATION FOR THE CLOSE-VERIFIER AGENT: -->
<!-- If this agent is close-verifier, the Report Body MUST be an independent verification record
     (facts you re-derived, not the producers' self-reports) containing:
     1) Baseline regen summary (modules touched)
     2) API changes since baseline (added/removed/changed signatures, with file refs)
     3) Plan adherence check: planned-and-found, planned-and-missing, unplanned-additions
        (an unplanned change is drift even when it compiles)
     4) Independent build/typecheck/test result: the command you ran yourself and its real
        outcome, NEVER a restatement of what the Executor claimed
     5) Applied-vs-approved reconciliation: does the applied diff match what the Critic approved?
        An undisclosed deviation is a reportable drift event. Critic self-fix diffs attached to a
        review report (v3.3) count as approved-with-attached-diff; reconcile them like any other
        applied change. The same holds for a security reviewer's post-Critic self-fix diff
        (Security Review Gate, v3.3): it is approved-with-attached-diff and is NOT drift merely
        because it postdates the Critic's approval. A security self-fix with no attached diff IS.
     6) Caller verification status for changed signatures
     7) Drift flags requiring architect attention
     8) Hot-file budget status: the per-file output of `phanes register-check`, an OBSERVATION,
        never a fix; the register's single writer is the primary agent, and close-verifier NEVER
        edits a hot file. A SOFT-BREACH or CROP-REQUIRED line here is the primary's cue to run
        the Cropping Operation (Phase 2 register mandate). -->

<!-- CRITICAL MODIFICATION FOR THE DESIGNATED VISUAL VERIFIER: -->
<!-- If this agent carries the visual verification duty (Phase 3) and the task altered a rendered UI,
     the Report Body MUST contain a Visual Evidence block:
     1) The evidence contract as fixed at Critic review (viewports, screens/states, reference design)
     2) Capture manifest: before/after image paths under reports/ui-evidence/<date>-<task>/, per viewport
     3) Pass/fail checklist results: visual hierarchy; clipped/overlapping/truncated elements; focus and
        hover states; contrast/readability; per-viewport layout; reference-design match; adjacent-UI regression
     4) Verdict: PASS | FAIL (fix_required, listing each failed check) | VISUAL: UNVERIFIED (with diagnosis,
        failure-memory entry, and user-eyeball request)
     5) Tooling failures: symptom, diagnosis, retry command, mirrored to .phanes/config.json failure memory -->

## Next Step   (Designate next agent if you wish to chain this as a workflow, or say submit for final review)
