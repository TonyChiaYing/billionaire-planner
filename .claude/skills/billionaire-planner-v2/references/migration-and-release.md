# Migration and release reference

## v1 source schema

The inspected v1 store contains `RichGoal`, `BrainDumpItem`, `TimeBlock`, `PrincipleLog`, and `ThinkSession`. `BrainDumpItem.goalTitle` and `TimeBlock.goalTitle` are optional strings, not stable relationships. The store is normally at `Application Support/BillionairePlanner/Planner.store`.

## Migration requirements

1. Close writes or perform migration before the main UI becomes editable.
2. Create a timestamped recoverable backup of the complete store family and metadata.
3. Use a versioned schema and explicit staged/custom migration where relationships are reconstructed.
4. Persist a migration run ID and per-record legacy source ID so retry is idempotent.
5. Validate counts, required fields, relationship resolution, and readable reopen before marking success.
6. Keep the backup and a human-readable migration report. Never delete the backup as part of first launch.
7. On failure, leave v1 data untouched, show a nontechnical recovery message, and log diagnostic detail locally.

## Entity mapping

### RichGoal

- Preserve UUID where possible.
- Map title and timestamps.
- Completed becomes completed Goal with completion history.
- Active `isTopFive` becomes focus intent; if corrupt data has more than five, preserve all goals but focus only the first five by deterministic order and report the rest for review.
- Set outcome description to a clearly marked migration placeholder only if the new model requires it; do not invent measurable outcomes.

### BrainDumpItem

- Create an inbox Action with title, tag metadata, and creation time.
- Resolve `goalTitle` only when exactly one migrated goal matches normalized title.
- Zero or multiple matches remain unlinked and appear in a post-migration review list.

### TimeBlock

- Create/reuse an Action and create a PlanPlacement preserving day, start minute, duration, done state, tag, and title.
- Do not merge solely by title across different dates. Use a conservative identity rule or one Action per legacy block.
- Resolve goal string using the same unique-only rule.

### PrincipleLog

- Preserve all text, tag, cause type, and creation time.
- Do not infer Goal or Strategy association from tag alone.

### ThinkSession

- Preserve topic, notes, start, planned end, and actual end.
- New Goal/Strategy relationships remain empty until user selection.

## Test fixtures

Include at least: empty store; one of every entity; duplicate goal titles; missing goal references; more than five Top Five flags; active and ended think sessions; completed goals/blocks; Unicode titles; midnight blocks; large store; migration interruption after each stage.

Assert idempotency by running migration twice against the same staged copy and comparing stable IDs/counts.

## Rollout

- Phase releases may use internal schema versions, but public v2 must upgrade directly from the shipped v1 schema.
- Run a dry migration on a copy of a real backup, never the only user store.
- Provide a migration summary: imported, unlinked, repaired, skipped, warnings.
- Keep v1 restoration instructions and verify a backed-up store can be reopened by the v1 build in an isolated location.
- Do not promise downgrade compatibility after v2 writes; promise backup-based restoration.

## Release gate

- All migration fixtures pass on every supported OS baseline.
- Interrupted migration retries without duplicates.
- Backup and restore rehearsal succeeds.
- No critical/high data-loss defects are open.
- Core flows pass offline.
- Notification content defaults to private.
- App version/build and release notes identify v2.0.0.0 and schema change.

