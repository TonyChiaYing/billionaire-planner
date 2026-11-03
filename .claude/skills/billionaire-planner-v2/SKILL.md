---
name: billionaire-planner-v2
description: Develop, review, migrate, or test BillionairePlanner v2.0.0.0 while preserving its goal-first recovery-oriented product rules and v1 user data. Use for work inside the BillionairePlanner SwiftUI/SwiftData repository; do not use for unrelated planner or project-management products.
---

# BillionairePlanner v2

Use this skill to implement the v2 product baseline without turning the app into project management or erasing a user's progress when plans change.

## Start here

1. Read the repository's `BillionairePlanner_v2.0.0.0_PRD.md` if present. It is the product baseline.
2. Read [references/source-of-truth.md](references/source-of-truth.md) before resolving ambiguity.
3. Inspect the current repository, schema, tests, dirty changes, platform targets, and build instructions before editing.
4. Load only the additional reference needed for the task:
   - Domain, architecture, schema, calculations: [references/architecture-and-data.md](references/architecture-and-data.md)
   - Product behavior and flows: [references/product-rules.md](references/product-rules.md)
   - v1 migration or release: [references/migration-and-release.md](references/migration-and-release.md)
   - Acceptance, testing, review: [references/acceptance-and-tests.md](references/acceptance-and-tests.md)

## Non-negotiable product invariants

- Center the app on `Goal → Strategy → Action → Plan → Outcome → Review → Recovery`.
- Keep focus goals few: recommend 3, never allow more than 5 active focus goals.
- Show outcome progress and action evidence separately; activity is not outcome.
- Treat work, personal goals, rest, and buffer as consumers of one daily capacity model.
- Estimates are optional. Suggestions require enough history and must be editable or dismissible.
- A missed time is a request for disposition, not failure.
- Detect recurring lag from multiple signals; never label a single miss or planned rest as falling behind.
- Restarting or changing a deadline must preserve all prior outcomes and history.
- Suggestions never silently change deadlines, focus, strategies, or committed plans.
- Keep core workflows offline and local-first. Do not introduce cloud, telemetry, or generative-AI dependencies without an explicit requirement.
- Preserve v1 data. Never use goal titles as permanent relationship keys in v2.

## Working method

- Make the smallest coherent vertical slice that leaves the app usable and the store migratable.
- Put capacity, lag, recovery, estimates, and rescheduling in testable domain/application code, not SwiftUI views.
- Preview every consequential automatic proposal and provide cancel plus undo where practical.
- Prefer archive and history records over destructive deletion.
- Keep drag-and-drop optional; every flow needs an accessible tap/keyboard path.
- When the requested change conflicts with the PRD, explain the conflict before implementation. A newer explicit user decision may override the baseline; record that decision near the affected specification or test.

## Implementation phases

Follow phase order unless the task is explicitly narrower:

1. Versioned schema, backup, migration harness, v1 characterization.
2. Goal, milestone, strategy, action, outcome, and dual progress.
3. Today, work template overrides, rest/buffer, capacity, estimates, local replan.
4. Work close, evening review, weekly review, tomorrow draft.
5. Lag signals, recovery cycles, deadline history, layered interventions.
6. Accessibility, cross-platform behavior, performance, migration rehearsal, release checks.

Do not land a schema phase without migration fixtures and restart/idempotency coverage.

## Verification and handoff

Run the narrowest relevant tests first, then the repository's full supported test/build checks. Report:

- Behavior delivered and acceptance IDs covered.
- Schema or migration effects, including backup/rollback behavior.
- Tests and platform builds run, with any unrun checks stated plainly.
- Assumptions, deferred scope, and product decisions needing confirmation.

Do not claim v2 complete until the PRD definition of done and [references/acceptance-and-tests.md](references/acceptance-and-tests.md) release gate are satisfied.

