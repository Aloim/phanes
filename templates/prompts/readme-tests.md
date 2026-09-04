<!-- DOC | The verbatim tests/README.md body `phaneslight scaffold` writes when a project has no test tree README; phaneslight.md Phase 2.5 Step 1b is the authoritative wording. -->
<!-- phaneslight-template v3.7.1 readme-tests -->
<!-- Verbatim tests/README.md body (phaneslight.md Phase 2.5 Step 1b), consumed by
     `phaneslight scaffold`; written only when tests/README.md is absent. -->
<!-- SECTION tests-readme -->
Test tree for this project.

Layout:
- unit/, fast, isolated tests. No network, no filesystem beyond tmp, no real DB.
- integration/, multi-module tests using real dependencies (DB, queue, etc.) where feasible.
- e2e/, full-stack scenarios driven through public entry points.
- fixtures/, shared inputs and golden files. Never edit fixtures to make a test pass.
- helpers/, shared builders, matchers, and harness code.

Conventions:
- New tests are created via `phaneslight new-file tests <path> "<description>"` (same header stamp rule as src/).
- TDD workflow: write failing test â†’ commit â†’ implement â†’ commit (see CLAUDE.md workflows).
- Integration tests for migrations or DB-touching code MUST hit a real database, not mocks.
- Test files mirror the src/ module path of the code under test so navigation is mechanical.

Single writer per test file: the agent that authored the test owns subsequent edits unless handed off via the standard review flow.
<!-- END SECTION -->
