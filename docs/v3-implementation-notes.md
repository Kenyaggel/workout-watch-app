# v3 implementation notes — the progression coach

What was built for Theme 6, the decisions taken along the way that the plan did not settle,
and what is still open. `ROADMAP.md` carries the plan and its tick-boxes; this file carries
the things you would otherwise have to reconstruct from the diff.

Branch: `claude/app-v3-implementation-3bc15e`, nine commits from `6399eb0` to `02acb4c`.
State at the time of writing: 135 tests passing in `WorkoutCore`, both app targets building,
working tree clean.

---

## 1. What shipped

| Theme | Status |
|---|---|
| **6a** Exercise identity migration | Done |
| **6b** Backtest the rules | Done, against a simulated lifter (see §4) |
| **6c** The progression rules | Done |
| **6d** Write-back and the phone review screen | Done, phone side verified on simulator |
| **6e** Language-model narration | **Not started, deliberately** |

New code lives in `WorkoutCore/Sources/WorkoutCore/Coach/` (7 files) plus
`SchemaV3.swift`, and `WorkoutApp/WorkoutApp/Views/Coach/ProposalReviewView.swift`.
Roughly 5,100 lines added, about half of them tests.

### Commits

```
02acb4c  Stop legacy history proposing an increase and then a deload for it
6d27573  Store the progression step per axis, not per exercise
b0d7abd  Let an acknowledged proposal actually clear the review screen
f50b848  Add the phone review surface for proposed targets
11ef12d  Backtest the progression rules over months of training
4f36261  Run the coach on session receipt and write back single-step moves
29da183  Add the deterministic progression coach
10cfca4  Document the V3 schema and the lift-identity rules
6399eb0  Add WorkoutSchemaV3 and match performed history on lift identity
```

The last three commits are review fixes, not new features. See §3.

---

## 2. Decisions the plan did not settle

The plan fixed the architecture; roughly a dozen rule semantics were left open. Three rival
specifications were written and judged against each other, and the judges overruled the
winning one in six places. The rules that shipped:

**Deloads round to the _nearest_ whole number of steps, not up.** Rounding up turns a 60 kg
target into 52.5 — a 12.5% cut narrated as "about ten percent" — where nearest lands on 55.

**A `.timed` slot stays on duration even when it carries a weight.** Routing a weighted plank
to load would be actively dangerous: the step is a scalar, so `5` authored as seconds would
start adding 5 kilograms. The plate is instead a gate on whether a set was met, so a lifter
cannot shed it and keep collecting seconds.

**A nonsense progression step is rejected back to the dimension default, not clamped.**
Clamping preserves an intent that is not there — a fat-fingered 500 becomes a 20 kg jump that
still looks like one honest step and applies itself.

**e1RM source sets are capped at 12 reps.** Epley is fitted near a true single; a 30-rep set
implies an inflation no safety factor absorbs.

**`PerformedSet.plannedSetCount` is recorded at run time.** Judging a 3-of-4 session against
today's three sets reads it as complete the moment the workout is edited.

**Only `.increase` auto-applies, and only when nothing about the reading is uncertain.** A
name-only identity match, a sanitized step, a changed set count or a missing target all force
review.

### Departures from the plan worth knowing about

**`PerformedSet.target*` was added, and is not in the plan.** 6d writes proposals onto
`PlannedSet`, so without recording the target in effect, every past session's "planned vs
done" would re-render against today's numbers and show a lifter targets they never had. That
is a regression 6d causes, so it is fixed in the same change.

**Proposals are recomputed, never stored.** The plan did not say where pending proposals
live. The coach is deterministic and reads only performed sets, so a proposal is a *view* of
history; storing them creates staleness with no good answer (a session syncs late, a set is
edited) plus orphan lifecycle work on every delete. `CoachDecision` persists the lifter's
*decision* instead, keyed by content fingerprint plus source session — so dismissing means
"not on that evidence", and stalling again brings it back.

**The fingerprint is a string, never `hashValue`.** Swift's `Hasher` is seeded per process,
so a persisted hash silently stops matching after a relaunch and every dismissal would
resurrect itself.

**The step is stored per axis.** `progressionStep` holds the kind-natural axis; 
`loadProgressionStepKg` holds kilograms. A `.reps` exercise maps to *two* dimensions
depending on the slot, so one scalar cannot serve both. See §3.

**`suggested*` only ever stamps proposals that were pending.** That is correct rather than a
gap: an applied proposal *becomes* the target, so `target*` already records it, and applying
moves the target so the proposal is no longer recomputable.

**One schema version, not two.** The plan put 6a and 6c in separate schema bumps. Nothing had
shipped V3, so both landed in one.

---

## 3. Bugs found by adversarial review and fixed

All five were found after the feature was "done" and building. Each fix has a test that was
confirmed to fail before it.

1. **(High) Legacy history proposed an increase, then a deload for it.** Rows performed
   before V3 carry no recorded target — which is *every row in an existing store the moment
   it migrates*, and anything synced from a watch on the previous build.
   `comparability()` let the walk continue, so `judge()` fell back to today's targets. A
   lifter who hit every prescribed rep got an unearned +2.5 kg, and the next run re-read the
   same sets against the raised target as misses and proposed backing off. Legacy sessions
   are now not comparable; the coach holds until one V3-era session exists.

2. **(Medium) A reps-axis step was spent as kilograms.** The editor hardcoded
   `hasTargetWeight: false`, so the field always said "reps", while the coach resolved the
   dimension from the slot. A `3` meaning three reps put 3 kg on the bar, auto-applied. At
   the extreme, `25` — which the reps axis itself rejects as a typo — sailed through on load
   as +25 kg a session. Fixed structurally by storing a step per axis.

3. **(High) Acknowledging a zero-delta proposal could not clear it.** Three outcomes hold for
   review but change no numbers. Because only *dismissals* suppressed proposals, tapping
   Apply re-derived a byte-identical proposal and the row never cleared — every tap inserting
   another decision row.

4. **(Medium) `holdChronicPartialSession` could not fire in the case it exists for.** It sat
   behind the guard that returns early when no session was evaluated, and a cut-short session
   *is* a skipped verdict.

5. **(Medium) Provenance flags were raised from the whole 365-day window.** One unresolvable
   row 300 days back, contributing nothing to the verdict, downgraded every future proposal
   to pending review forever.

---

## 4. Still to handle

Ordered by what I would do first.

### 4.1 The `rules` dimension has never been independently reviewed

Three review rounds ran. Round 1 covered `ui` and died on a usage cap before verifying the
rest. Round 2 covered `migration`, `store` and `spec` — its findings are what §3 is built
from — but its `rules` reviewer never ran. Round 3 targeted `rules` alone and was stopped.

So degenerate-input handling and the compositional behaviour of the pure rules rest on my own
tests only: 61 cases in `CoachTests` plus a 120-session backtest. That is not nothing, but no
independent pass has looked at it.

The workflow script is saved and can be relaunched unchanged:

```
.claude/projects/…/workflows/scripts/v3-coach-rules-review-wf_33857ba8-337.js
```

It looks for: non-finite/zero/negative/absurd targets, `Int()` traps, overflow, the deload
floor, extreme e1RM inputs, `Set` iteration order and unstable sorts reaching output,
fingerprint stability across processes, the stall streak across skipped/incomparable
sessions, and rules in ROADMAP 6c with no test.

### 4.2 The coach has never seen real training data

This is the original gate and it still stands — not on *building* the coach, which is done,
but on knowing whether its defaults suit you. Specifically unvalidated:

- **2.5 kg load step.** +4.2% on a 60 kg bench. Deliberately aggressive; double progression
  is built to absorb it, but on real data it may stall too often.
- **10% deload, nearest whole step.**
- **RPE ≥9 vetoes an increase, RPE 10 on a stall escalates to a deload.**
- **28-day layoff threshold**, **90-day e1RM window**, **0.90 e1RM safety factor**.
- **Advisory ceilings** of 30 reps and 300 s a set.

All live in `CoachConfig` and are injectable, so they can be tuned without touching the rules.

Once there is real history, `CoachBacktest.replay` takes it directly — swap
`CoachStore.sessionSnapshots` in for the simulated lifter. That is a one-line change and is
the fastest way to see whether the defaults behave.

### 4.3 The watch half of the loop is unexercised

Verified on the simulator: the phone review screen, apply, and write-back to the workout
(two stalled sessions → "Back off, 3×60 kg → 3×55 kg" → Apply → the workout reads 55 kg).

**Not verified on hardware:** a real session completing on the watch, syncing to the phone,
triggering `CoachStore.ingest`, and the resulting targets travelling back over the existing
template sync. Every hop existed before this change and none was modified, but the
end-to-end path has not been run. This is the same kind of paired-device shakedown Theme 2
needed, and it belongs on real devices.

### 4.4 Known limitations, accepted rather than fixed

**`WorkoutSchemaV3` freezes the moment this branch ships.** While unshipped, editing it is
free but invalidates every development store — adding a field without bumping
`versionIdentifier` changes the model hash and SwiftData refuses the store with *"Cannot use
staged migration with an unknown model version."* This crashed the simulator build during
development until the app was reinstalled. After shipping it means a user losing their store,
so the next change must be a V4.

**The identity backfill can resolve to the wrong lift in one case.** If an exercise was
renamed and a *different* exercise later took the old name, the name is unambiguous today and
those rows are stamped with the new lift's id — permanently, since the backfill cannot be
redone. Nothing in the store records the former name, so this is undetectable rather than
merely unhandled. It is a cost of name-based backfill, accepted because the alternative is
discarding all pre-V3 history, and it is an argument for migrating while stores are small.
Recorded in `docs/adr/0001`.

**A lifter who habitually cuts a slot short generates only skipped verdicts.** The coach goes
quiet on that slot rather than guessing. `holdChronicPartialSession` is the escape valve after
three consecutive cut-short sessions, and it now fires (see §3.4), but the quiet period before
it is intended behaviour, not a bug.

**A lifter who never opens the phone never gets a deload.** Deloads hold for review, so they
repeat a weight they cannot lift. That is the intended failure mode — safe, merely
unproductive — and the backtest asserts it never turns into an increase.

### 4.5 Not started

**6e, the language model.** Deliberately last. The design is settled in ROADMAP 6c/6e: a
phone-only, read-only protocol seam alongside `SessionRecorder` and `WorkoutLifecycle`, given
the coach's proposal and recent history, writing narration only. It mutates nothing and it is
never the source of a number. Needs a cloud key in Keychain, entered by hand.

Note that the coach already produces a plain-language reason for every outcome, written
deterministically — `ProposalReviewView` shows it. 6e would enrich that, not replace it.

---

## 5. Where the invariants are written down

`CLAUDE.md` gained three sections during this work, and they are the load-bearing ones:

- **SwiftData migration notes** — V1/V2/V3 frozen rules, and the V3-freezes-on-ship warning.
- **Lift identity in performed history** — that `exerciseID` is the matching key, that
  ambiguous names resolve to *neither*, and that `target*` is what planned-vs-done must read.
- **The progression coach** — that `Coach.propose` stays pure, that sessions are passed in
  unscoped, that proposals are recomputed, that only the phone writes targets, and that the
  step is stored per axis.

`CONTEXT.md` is the vocabulary. It is worth reading before changing anything here: three
different things in this domain were all being called "exercise", which is how a display
string became the matching key for performed history in the first place.
