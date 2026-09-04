<!-- DOC | The blank report template every sub-agent copies for its report; role-conditional instruction blocks for the closure agent ride inside as comments. -->
<!-- phaneslight-template v3.7.1 report -->
# Report: [Brief Title of Your Task]

## Assignment Details (Injected Context)
> [Restate the full, detailed assignment and context provided by the orchestrator.]

## Referenced Documents
- `path/to/document_one.js`
- `path/to/another/document.md`

## Report Body
[This is the main body of your work. If proposing changes, include proposed patch/diff or snippets with clear explanations.]

<!-- CRITICAL MODIFICATION FOR THE CLOSURE AGENT: -->
<!-- If this agent is <projectSlug>-closure, the Report Body MUST be an independent verification record
     (facts you re-derived, not the producers' self-reports) containing:
     1) Baseline regen summary (modules touched)
     2) API changes since baseline (added/removed/changed signatures, with file refs)
     3) Plan adherence check: planned-and-found, planned-and-missing, unplanned-additions
        (an unplanned change is drift even when it compiles)
     4) Independent build/typecheck/test result: the command you ran yourself and its real
        outcome, NEVER a restatement of what any producer claimed
     5) **Applied-versus-intended reconciliation.** Your baseline is the orchestrator's step session summaries plus `<projectSlug>-reviewer`'s fix plan where one exists, checked against the `edits_made` arrays in every worker and mechanic report for the step. Report three classes: **intended-and-applied**, **intended-and-missing**, and **applied-with-no-covering-intent**. The third class is drift, and it is drift whether or not it compiles and whether or not it looks reasonable. An edit disclosed in `edits_made` but not covered by an intent is still drift; disclosure makes it visible, it does not make it authorized.
     6) Caller verification status for changed signatures
     7) Drift flags requiring architect attention
     8) Hot-file budget status: the per-file output of `phaneslight register-check`, an OBSERVATION,
        never a fix; the register's single writer is the primary agent, and `<projectSlug>-closure` NEVER
        edits a hot file. A SOFT-BREACH or CROP-REQUIRED line here is the primary's cue to run
        the Cropping Operation (Phase 2 register mandate). -->

<!-- CRITICAL MODIFICATION, VISUAL VERIFICATION DUTY (closure only): -->
<!-- If this agent is <projectSlug>-closure and the task altered a rendered UI,
     the Report Body MUST contain a Visual Evidence block:
     1) The evidence contract as declared before apply (viewports, screens/states, reference design)
     2) Capture manifest: before/after image paths under reports/ui-evidence/<date>-<task>/, per viewport
     3) Pass/fail checklist results: visual hierarchy; clipped/overlapping/truncated elements; focus and
        hover states; contrast/readability; per-viewport layout; reference-design match; adjacent-UI regression
     4) Verdict: PASS | FAIL (graded on the severity ladder, listing each failed check) | VISUAL:
        UNVERIFIED (with diagnosis, failure-memory entry, and user-eyeball request). Return the
        verdict to <projectSlug>-orchestrator; it runs the decision matrix, never you.
     5) Tooling failures: symptom, diagnosis, retry command, mirrored to .phaneslight/config.json failure memory -->

## Next Step   (Designate next agent if you wish to chain this as a workflow, or say submit for final review)
