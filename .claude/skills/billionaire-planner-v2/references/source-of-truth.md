# Source of truth and decision protocol

## Priority

When sources disagree, use this order:

1. The user's newest explicit decision for this work.
2. `BillionairePlanner_v2.0.0.0_PRD.md`: confirmed decisions and guardrails.
3. PRD acceptance criteria.
4. These skill references.
5. Current v1 behavior and legacy documentation, only for compatibility and migration.
6. Engineering convention or model judgment.

Never let a legacy screen name, celebrity method, or existing data limitation override the v2 goal-first flow.

## Confirmed versus derived

The following are explicit: hybrid assistance, dynamic strategies, progressive goal setup, dual progress, few focus goals, action-first home, light planning with focus/rest, mixed conflict triggers, reusable work templates with daily edits, cross-day work, emergency insert with local replan, fixed daily close, work close plus evening close, tomorrow draft, time plus flexible capacity, optional estimates with suggestions, recurring-lag recovery, and daily/weekly/deadline intervention layers.

Detailed thresholds and field shapes are derived implementation baselines. Keep them configurable in domain policy where cheap. Do not present derived thresholds as user intent.

## Ambiguity protocol

Proceed with the smallest reversible interpretation when all are true:

- no user data will be lost;
- the product does not become project management;
- the choice does not introduce cloud/telemetry/external cost;
- the behavior can be adjusted without another destructive migration.

Otherwise stop and ask one focused question. Record meaningful assumptions in the change summary and, when durable, in a decision record or test name.

## Change control

A later explicit user instruction can override the baseline. When it does:

1. State the old and new behavior.
2. Identify affected acceptance criteria, migration, and tests.
3. Update the nearest source-of-truth document in the same change when authorized.
4. Preserve historical data unless the user explicitly authorizes a destructive transition with a backup path.

