# Architecture and data reference

## Target architecture

Use a modular monolith suitable for a small native app:

- `Features/Today`, `Features/Goals`, `Features/Reviews`, `Features/Think`
- `Domain/Models`, `Domain/Policies`, `Domain/Services`
- `Application/Commands`, `Application/Queries`
- `Persistence/Schema`, `Persistence/Migrations`, `Persistence/Repositories`
- `Platform/Notifications`, `Platform/Clock`, `Platform/Export`

SwiftData models may be persistence-shaped. Keep calculations in value types or services so tests can run without a live UI or notification center.

## Entity baseline

Exact Swift names may adapt to repository conventions. Stable UUIDs are required.

### Goal

- `id`, `title`, `outcomeDescription`
- `horizon`: short / medium / long
- `status`: draft / active / paused / completed / archived
- `isFocus`, `focusRank`
- `createdAt`, `activatedAt`, `completedAt`, `archivedAt`
- current deadline plus relationship to deadline history
- optional outcome target: type, target value, unit

Rules: at most five active focus goals. Prefer three. A draft can lack strategy/action; an active executable goal cannot.

### Milestone

- `id`, `goalID`, `title`, `definitionOfDone`
- optional target date and outcome target
- `status`, ordering, completion evidence/time

### Strategy

- `id`, `goalID`, `title`, optional hypothesis
- `status`: proposed / active / paused / retired / succeeded
- `startedAt`, `endedAt`, optional decision reason

Do not move historical actions to a new strategy when strategy changes.

### Action

- `id`, optional `goalID`, optional `strategyID`, optional `milestoneID`
- `kind`: personalGoal / work / maintenance
- `title`, optional notes/context
- `status`: inbox / ready / planned / inProgress / done / cancelled / waiting
- optional estimate and estimate source
- `createdAt`, `completedAt`, optional source action for carryover

### PlanPlacement

- `id`, `actionID`, local planning date
- placement type: ordered / period / timed
- optional start instant, duration, period
- `commitment`: draft / accepted / locked
- disposition and timestamps

Separate Action from placement so moving an item does not clone its identity or erase history.

### WorkTemplate and template item

- template weekday/calendar applicability and active dates
- fixed periods, common work actions, default rest/buffer assumptions
- daily instances store source template ID and overrides

Never mutate the template from a daily edit without explicit confirmation.

### RestBlock and BufferPolicy

Rest is a first-class placement or capacity reservation, not a fake task. BufferPolicy stores configured percentage/minimum plus optional learned suggestion; a learned value is never applied silently.

### OutcomeEvidence

- `id`, `goalID`, optional milestone/strategy/action IDs
- kind: numeric / checkpoint / note / artifactReference
- value/unit or text, recordedAt, optional effective date

Outcome evidence is cumulative unless explicitly reversed with an audit record.

### Review

Daily review stores work-close and evening-close completion separately. Store action dispositions, selected outcomes, blockers, optional energy, draft generation time, and accepted draft revision. Weekly review stores trend snapshot, strategy decision, next-week capacity, and recovery choice.

### RecoveryEpisode

- `id`, `goalID`, cycle number
- detected signals and explainable evidence snapshot
- opened/closed time, selected intervention, baseline date
- pre-change deadline/strategy/capacity snapshot

One goal persists across cycles. Restart creates a cycle, not a new empty goal, unless the user explicitly chooses a separate goal.

### DeadlineRevision

Append-only: old value, new value, changedAt, optional reason, triggering recovery ID. The current deadline is a projection from the latest revision or a cached field updated transactionally.

### Principle and ThinkSession

Preserve v1 fields. Add optional stable relationships to Goal and Strategy. Legacy context tags remain importable metadata; do not invent goal links.

## Policy services

### Capacity

Inputs: available window, fixed work, accepted commitments, protected rest, buffer policy, transition cost, and confidence. Outputs: available minutes, load ratio, state, reasons, and proposals.

Suggested initial load bands after exclusions:

- `comfortable`: <= 70%
- `feasible`: > 70% and <= 85%
- `tight`: > 85% and <= 100%
- `overloaded`: > 100%

Also raise `tight` for missing protected rest, excessive context switches, or clustered high-energy actions. Keep thresholds centralized and testable.

### Estimate suggestion

Use explicit history only. A reasonable baseline is median actual duration from at least three comparable completed actions, with recency/category weighting only if explainable. Round to user-friendly increments and show sample count/range. Never overwrite a user estimate.

### Lag signals

Return independent signals with evidence, never only a Boolean. Recovery eligibility normally requires two signal categories or explicit user declaration. Exclude planned pause, rest, waiting, and insufficient data.

### Local replan

Treat locked, completed, in-progress, and unaffected placements as immovable. Generate proposals for the minimum conflict window. Rank: use buffer, move flexible work, shrink an action to its defined minimum version, move to later, carry to tomorrow. Never apply before confirmation; retain an undo transaction.

### Tomorrow draft

Deterministic inputs and ranked explanations are required. Do not insert more work than capacity. When demand exceeds supply, propose a feasible subset and list excluded candidates with reasons.

## Time semantics

- Store instants as `Date`, plus the planning calendar/time-zone identifier needed to reconstruct a local day.
- Never infer a day solely by adding 24 hours.
- Test DST gaps/repeats, travel time-zone changes, midnight, and locale calendar boundaries.
- A review belongs to its explicit local planning day even if completed after midnight.

## Deletion and integrity

- Default to archive for Goal, Strategy, and historical Action.
- Use nullify/restrict rather than cascading away OutcomeEvidence, RecoveryEpisode, DeadlineRevision, or Review history.
- Enforce stable uniqueness for migration source identifiers.
- Multi-entity operations use one transaction where supported; otherwise use an application operation journal for safe retry.

