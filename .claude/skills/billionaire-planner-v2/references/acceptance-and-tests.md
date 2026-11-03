# Acceptance and test reference

The PRD acceptance IDs AC-01 through AC-16 are release requirements. Link production changes and tests to those IDs where practical.

## Required domain suites

### CapacityPolicyTests

- fixed work, rest, and buffer are excluded before flexible capacity;
- boundary load states are deterministic;
- missing rest or excessive switching can raise risk;
- overload proposals never mutate the plan;
- zero/negative availability and overnight windows are safe.

### EstimateSuggestionTests

- fewer than three comparable samples yields no numeric suggestion;
- median resists one extreme outlier;
- user estimate is never overwritten;
- explanation includes sample count and uncertainty/range;
- cancelled or inferred durations are excluded unless product policy explicitly includes them.

### LagDetectionTests

- one miss, rest, pause, waiting, and no data do not trigger recovery;
- two independent recurring signals do;
- evidence is stable and user-readable;
- resolved/snoozed signals obey suppression;
- a new materially higher risk can break cooldown.

### RecoveryTests

- interventions rank smallest change first;
- restart adds a cycle and preserves accumulated evidence;
- deadline changes append history;
- cancel leaves all state unchanged;
- repeated confirmation cannot duplicate a recovery cycle.

### ReplanTests

- completed, in-progress, locked, and unaffected placements do not move;
- only the conflict window changes;
- preview equals committed result;
- undo restores the exact prior plan;
- insufficient capacity produces tradeoffs rather than silent deletion.

### TomorrowDraftTests

- locked items and fixed template precede flexible candidates;
- rest/buffer are present;
- focus actions are ranked but never overfill capacity;
- excluded candidates retain reasons;
- accepting part of a draft does not accept the rest.

## Migration suites

Cover every fixture in `migration-and-release.md`, including a real anonymized backup copy if available. Assert stable IDs, counts, content, relationships, warnings, reopen, retry, and failed-migration restoration.

## UI journeys

1. First launch → create progressive goal → add strategy/next action → plan today → record outcome.
2. Apply weekday work template → edit today only → verify future template unchanged.
3. Insert urgent work → preview local replan → apply → undo.
4. Complete work close → complete evening close → review tomorrow draft later.
5. Simulate recurring lag → inspect reasons → choose smaller action → preserve history.
6. Change deadline → inspect original and revised deadlines.
7. Restart goal → compare accumulated versus current-cycle views.
8. Migrate v1 with ambiguous goal titles → resolve from post-migration review.
9. Complete core flows with VoiceOver and keyboard without drag-and-drop.
10. Deny notifications and network → core behavior remains usable.

## Review checklist

- Is this action-first or administrative overhead?
- Does any path equate activity with outcome?
- Can a missed plan erase or reduce prior achievement?
- Is a suggestion explained, dismissible, and confirmed before mutation?
- Are rest and buffer protected in the same model as work?
- Does the change accidentally create project-management scope?
- Is relationship identity stable across renames?
- Are time-zone and local-day semantics explicit?
- Is important history archived instead of cascaded away?
- Can the behavior be tested without rendering a View?

## Definition of done for a change

- Relevant acceptance behavior is implemented and tested.
- Migration impact is either covered or explicitly none.
- Accessibility labels and non-drag path exist for new UI.
- Empty, loading/migrating, error, and large-data states are handled.
- Tests/builds run are reported; skipped platform checks are named.
- No unrelated user changes are overwritten.

## v2 release gate

Do not declare v2 complete unless all AC-01–AC-16 pass, the PRD completion definition is met, migration is rehearsed, and critical/high defects are zero. Medium defects affecting recovery history, capacity correctness, or accessibility of a core path are also release blockers.

