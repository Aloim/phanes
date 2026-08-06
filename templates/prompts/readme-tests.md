<!-- DOC | The verbatim tests/README.md body `phanes scaffold` writes when a project has no test tree README; phanes.md Phase 2.5 Step 1b is the authoritative wording. -->
<!-- phanes-template v3.4.0 readme-tests -->
<!-- Verbatim tests/README.md body (phanes.md Phase 2.5 Step 1b), consumed by
     `phanes scaffold`; written only when tests/README.md is absent. -->
<!-- SECTION tests-readme -->
Test tree for this project.

Layout:
- unit/, fast, isolated tests. No network, no filesystem beyond tmp, no real DB.
- integration/, multi-module tests using real dependencies (DB, queue, etc.) where feasible.
- e2e/, full-stack scenarios driven through public entry points.
- fixtures/, shared inputs and golden files. Never edit fixtures to make a test pass.
- helpers/, shared builders, matchers, and harness code.

Conventions:
- New tests are created via `phanes new-file tests <path> "<description>"` (same header stamp rule as src/).
- TDD workflow: write failing test → commit → implement → commit (see CLAUDE.md workflows).
- Integration tests for migrations or DB-touching code MUST hit a real database, not mocks.
- Test files mirror the src/ module path of the code under test so navigation is mechanical.

Single writer per test file: the agent that authored the test owns subsequent edits unless handed off via the standard review flow.
<!-- END SECTION -->
