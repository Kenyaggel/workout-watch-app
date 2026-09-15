# Exercise identity in performed history

`PerformedSet` has always recorded only the exercise's display name, and `AnalyticsEngine`
matches history by comparing that string. A rename therefore splits one lift's history in two
with no error, and two exercises that happen to share a name are silently pooled — tolerable
for a volume chart, unacceptable once progression rules read that history to propose loads.
Performed sets will carry the exercise's stable identity as the matching key, keeping the name
purely for display and as a fallback for rows that predate the change.

## Considered options

- **Key on the (workout, exercise) pair.** Rejected as the *identity* mechanism. It is the
  right scope for *looking up* what to propose next — heavy 5s must not contaminate volume 12s
  — but it is not what makes two sets the same lift, and treating it as identity would discard
  cross-workout history entirely. Scope and identity are kept as separate concerns.
- **Keep matching on the name.** Rejected. Costs no migration and breaks nothing today, but a
  rename is silent data loss, and every proposed target would inherit that fragility.

## Consequences

- Requires `WorkoutSchemaV3` with a stage that backfills existing rows by name match. Best done
  while on-device stores are small — the backfill becomes less reliable the more history exists,
  and cannot be redone later.
- The identity must be threaded through `SessionPlan.Exercise` and `PerformedSetDTO`, which
  today carry only the name. The engine has never known which `Exercise` a set came from.
- A performed set whose exercise was renamed or deleted *before* this migration cannot be
  resolved. Those rows keep a null identity and stay name-matched; the coach must tolerate that
  rather than assume identity is always present.
- **Correction, found while implementing:** that is true only when the old name is gone. If an
  exercise was renamed and a *different* exercise later took the old name, the name is
  unambiguous today and the backfill resolves those rows to the wrong lift — permanently, since
  it cannot be redone. Nothing in the store records the former name, so this is undetectable
  rather than merely unhandled; it is a cost of name-based backfill, accepted here because the
  alternative is discarding all pre-V3 history. It is also an argument for migrating while
  stores are small.
- `exerciseName` stays on `PerformedSet` deliberately. It is not redundant: it preserves what
  the exercise was called at the time it was performed, and covers deleted exercises.
