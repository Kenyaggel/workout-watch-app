# Roadmap — Workout Watch App

Where v1 ended and where v2 takes us. Use this as the working plan; tick items off as they land.

## v1 — what shipped

- Three-mode session loop: **in-set / rest / prep** with wall-clock timers via `TimelineView`.
- `SessionEngine` finite state machine, unit-tested against an injected `nowProvider` in `SessionEngineTests`, alongside analytics and migration coverage in `WorkoutCoreTests`.
- `WorkoutCore` Swift Package with versioned SwiftData schema (`WorkoutSchemaV1` and `WorkoutSchemaV2`, the latter lifting per-set `restOverrideSec` onto `PlannedExercise.restSec` via a custom migration stage) and a clean recorder/lifecycle protocol split so the package builds on macOS for tests.
- HealthKit recording on watchOS via `HKWorkoutSession` + `HKLiveWorkoutBuilder`, gated `#if canImport(HealthKit) && os(watchOS)`.
- One seeded template (Push Day) so the app is usable from launch.
- iPhone target has early Workouts, Exercises, History, and Analytics surfaces (signing/entitlements pre-wired).
- Repo on GitHub (`Kenyaggel/workout-watch-app`), `.gitignore` keeps build artifacts out.
- App icon is ready, and the app has been checked on device.

## Carry-over: open bugs / polish

These belong at the top of v2 because they're already half-done.

- [x] **Bigger in-set editing controls** — reps editing is fine as +/- buttons and does not need Digital Crown editing, but the reps control should be sized up. RPE should be sized up too so both are easier to read and tap mid-workout.
- [x] **Rest skip button styling** — the visible gray button capsule around the `Skip` label is awkward and overlaps the timer. Keep the skip action, but make the button background invisible so the timer stays visually clean.
- [x] **Up next details** — add the planned weight and reps to the Up next window so the lifter can prepare before the next set or exercise.
- [x] **Workout start summary** — after starting a workout, show a summary of the whole plan before the first set: exercises, weights, reps, and set structure.
- [x] **Exercise transition prep** — show an Up next window before every exercise, including the first exercise, not only between exercises later in the session.
- [x] **Timed exercise duration input** — timed exercise setup/editing should use ergonomic hours/minutes/seconds controls instead of forcing raw seconds. Hours should be optional/collapsed so common minute/second entries do not require typing `00` for hours.
- [x] **Optional RPE capture** — completing a set should not force RPE entry. Keep RPE available for users who want to log it, store missing RPE as nil, and make later analytics ignore nil values rather than treating them as low effort.

## v2 themes

Five themes, ranked by user value. Each is independently shippable.

### Theme 1: Workout authoring (iPhone-first)

The watch can run workouts but shouldn't create or edit them. Authoring belongs on the phone — bigger screen, real keyboard.

- [x] **iPhone UI foundation**: separate Workouts and Exercises tabs; reusable `Exercise` management; workout detail editor that adds an exercise through a fast set setup flow.
- [x] **Template editor refactor**: rest now belongs to `PlannedExercise`; `PlannedSet` only stores set targets. Existing iPhone stores migrate safely via optional stored rest plus `resolvedRestSec`.
- [x] **Template editor navigation fix**: planned exercise rows use direct destination links so one tap opens the weight/reps/rest editor on device.
- [x] **Default planned sets**: newly picked exercises and newly added sets start with sensible reps/duration/distance defaults and copy prior set targets where possible.
- **Remaining iPhone UI polish**: rename internal/template-heavy view names only if it becomes worth the churn; add richer editing affordances as needed after real use.
- **Watch UI**: read-only template picker stays as is; **add a "duplicate & edit on phone" affordance** so users discover the phone editor.
- [x] **Sync backbone**: `WatchConnectivity` `WCSession` with `transferUserInfo` now sends Codable template snapshots from iPhone to watch. The watch treats the phone as source of truth and replaces local templates when a snapshot arrives. Don't use `sendMessage` — it requires both devices reachable.
- **Files**:
  - `WorkoutApp/WorkoutApp/Views/Library/TemplateListView.swift` (iOS Workouts list)
  - `WorkoutApp/WorkoutApp/Views/Library/TemplateDetailView.swift` (iOS workout editor)
  - `WorkoutApp/WorkoutApp/Views/Library/ExerciseLibraryView.swift` and `ExerciseDetailView.swift` (iOS exercise management)
  - `WorkoutCore/Sources/WorkoutCore/Sync/WatchConnectivityManager.swift` (new)
  - Encode `WorkoutTemplate` → `Codable` DTO (don't ship `@Model` types over the wire).
- **Risks**: SwiftData on both ends + WCSession ordering. Treat the phone as source of truth for templates; the watch overwrites its local copy on receipt. Conflict resolution is "last write wins, scoped per-template-id."

### Theme 2: History & progress

A workout that's saved to HealthKit but invisible inside the app feels half-finished.

- [x] **Watch**: `SessionSummaryView` exists for end-of-session; the watch now has a "History" tab showing the last 10 sessions (date, total volume, duration).
- [x] **iPhone**: full history list → session detail (per-set actuals, RPE, planned vs done diff), with clearer session summaries.
- [x] **Sync**: completed watch sessions now transfer to iPhone over `WCSession.transferUserInfo` as Codable session snapshots.
- **Status**: Paired-device shakedown passed on watch hardware: workout completion, watch History, and iPhone History receipt all work.
- **Analytics follow-ups**: Workout Frequency currently reads as an oversized blue bar/rectangle; redesign the chart once more data exists. Make Exercise Progression and Estimated 1RM interactive/responsive so tapping a point reveals the source workout and set context. Weekly Volume currently has little visible response with sparse data; revisit its empty/single-point behavior and interaction model.
- **Data model is already there** — `WorkoutSession` + `PerformedSet` records every set; Theme 2 adds watch/iPhone surfaces plus watch→phone delivery.
- **Files**:
  - `WorkoutApp/WorkoutApp Watch App/Views/HistoryListView.swift`
  - `WorkoutApp/WorkoutApp/Views/HistoryListView.swift` (iOS variant)
  - `WorkoutApp/WorkoutApp/Views/SessionDetailView.swift`

### Theme 3: Session recovery UI

The engine and recorder already persist the session as it runs. The app currently doesn't *resume* a crashed session — on launch it just goes back to the template picker.

- **App-launch check**: query for an unfinished `WorkoutSession` (no `endedAt`). If one exists, show a recovery prompt: *Resume / Discard*.
- **Resume path**: rebuild the engine state from the persisted record. The trickiest piece is figuring out what phase to restore to — for v2 we can resume to **in-set** of the next planned set after the most recent `PerformedSet`. Rest/prep state is ephemeral and not worth restoring.
- **Discard path**: mark `endedAt = now`, no HealthKit save, return to picker.
- **HealthKit angle**: if `HKLiveWorkoutBuilder` was active, it's gone. Don't try to attach to the orphaned builder — just save what we have via `HKWorkoutBuilder` (non-live) for the partial duration. Or skip the HK save on resumed-then-finished sessions for v2 and document the limitation.
- **Files**:
  - `WorkoutCore/Sources/WorkoutCore/Services/SessionRecovery.swift` (new)
  - `WorkoutApp/WorkoutApp Watch App/Views/RecoveryPromptView.swift`
  - Hook into `WorkoutAppApp.init` / `.task` on the root view.

### Theme 4: Watch-face complication + Smart Stack

Big retention lever on watchOS. One tap from the wrist starts the last-used template.

- **Complication**: `WidgetKit` widget targeting `.accessoryCircular`, `.accessoryCorner`, `.accessoryRectangular`. Tapping deep-links to `ActiveSessionView` with the last template pre-selected.
- **Smart Stack relevance**: surface the widget after a typical workout time-of-day or when entering a known gym location (CLLocation). Optional for v2.
- **Deep link scheme**: `workoutapp://start?templateId=…`. Handle in `WorkoutAppApp` via `.onOpenURL`.
- **Files**:
  - `WorkoutApp/WorkoutApp Watch App/Widget/StartWorkoutWidget.swift`
  - URL routing in `WorkoutAppApp`

### Theme 5: Polish for App Store

Optional — only if the user wants to actually ship.

- `PrivacyInfo.xcprivacy` review (HealthKit + UserDefaults reasons already declared; verify against Apple's required-reason API list).
- Screenshots on a real Watch (App Store Connect requires per-size assets).
- Marketing copy / What's New string.
- TestFlight beta with 2–3 friends before public submission.

### Theme 6: Progression coach (v3)

The app records what you lifted but never advises. The coach closes that loop: it reads session
history and proposes the next session's targets. See `CONTEXT.md` for the vocabulary and
`docs/adr/0001-exercise-identity-in-performed-history.md` for the identity decision.

**Gated on data.** The store currently holds under ~10 sessions, mostly test data. Slot-scoped
lookup needs repeat visits to the same slot and a deload needs two consecutive stalls, so none
of this is buildable or verifiable yet. Revisit after roughly 6–8 weeks of real logging. The
design below is settled; only the timing is open.

#### 6a. Exercise identity migration — do this now, not with the rest

This is a correctness fix, independent of the coach, and it is cheapest while the store is
small and disposable. It should land well before anything else in Theme 6.

- `WorkoutSchemaV3` adds `exerciseID: UUID?` to `PerformedSet`; a migration stage backfills it
  by matching `exerciseName` against the `Exercise` library.
- Thread the id through `SessionPlan.Exercise` (which carries only `name` today) and through
  `PerformedSetDTO` so synced watch sessions preserve it.
- `AnalyticsEngine` matches on `exerciseID` when present, falling back to `exerciseName`.
- Follow the existing migration discipline: new nested `@Model` types in `SchemaV3.swift`, a new
  stage appended to `WorkoutMigrationPlan.stages`, typealiases retargeted, and a
  `MigrationTests` case against a real file-backed store.

#### 6b. Backtest the rules — an afternoon, throwaway

Before migrating anything else or writing engine code, replay existing history through the
rules below and print what they *would* have proposed, session by session. If the rules stall
or run away on real data, better to find out in a script than in a schema. Do not skip this
just because the rules look obvious.

#### 6c. The progression rules

- **Scope.** Propose from the last performance of this exercise *in this workout* — the slot.
  Never pool heavy 5s with volume 12s. When a slot has no history (new workout, new exercise),
  fall back to the exercise's best e1RM across all workouts, scaled down to the target rep
  count. `AnalyticsEngine.exerciseAnalytics` already computes Epley e1RM.
- **Dimension.** Every exercise progresses along exactly one axis, with a step in that axis's
  unit: `.reps` with a weight → load in kg; `.reps` with no weight → target reps; `.timed` →
  duration; `.distance` → distance. `progressionStep: Double?` goes on `Exercise`, defaulted by
  kind, overridable per exercise. This is what makes Plank and push-ups coachable at all.
- **Baseline.** Double progression. Hit every target rep on every set → one step up. Miss any
  set → repeat the same targets. Stall twice consecutively → propose a ~10% deload.
- **RPE is a veto, never a throttle.** Step size is always the exercise's fixed step; RPE only
  changes direction. RPE ≥9 on an otherwise successful session turns increase into hold. RPE 10
  with missed reps turns hold into deload. Below 9 it does nothing, and absent RPE changes
  nothing — the rule must work on sessions with no RPE at all, which is most of them.

#### 6d. Where proposals live and how they reach the watch

- A completed session syncs watch → phone. **On receipt, the phone runs the coach and writes
  accepted targets onto the workout's `PlannedSet` rows**, and the existing template sync
  carries them back to the watch. Both hops already exist — no new DTO, no new `@Model`.
- Writing to the workout is only safe because the *phone* is the writer. Template sync is
  phone → watch and the watch replaces its local copy; a watch-side write would be clobbered.
- **Review by exception.** A proposal that is a single step in the usual direction applies
  automatically, so the watch is never stale on a day you skip the phone. Deloads, second
  consecutive stalls, and anything larger than one step hold as pending until reviewed on the
  phone. Approval authority stays where the stakes are.
- `suggestedWeightKg` / `suggestedReps` on `PerformedSet` record what the coach proposed versus
  what was actually run. That deviation signal is the only way to tell whether the coach is any
  good. Add these with 6c, not with 6a — their shape should follow a working engine.
- Overriding needs no special handling: the coach reads only performed sets, so training
  through a suggestion you disagree with self-corrects next session.

#### 6e. The language model — last, and deliberately small

- The coach is pure Swift, runs offline on both devices, and is the **only** source of a number.
  The watch must produce targets at Start with no network and no phone nearby.
- A model sits behind an injected protocol alongside `SessionRecorder` and `WorkoutLifecycle`,
  **phone-only and read-only**: it sees the coach's proposal, recent history, and existing
  analytics, and writes narration — why a load moved, what has stalled. It mutates nothing.
- Cloud model to start, key in Keychain and entered by hand. No hardcoded key, since shipping
  stays open. The protocol seam is what lets on-device `FoundationModels` drop in later; that
  would cost a bump to iOS/watchOS 26, which is not worth paying now.
- **Exercise substitution is out of scope** until `Exercise` carries equipment and muscle group.
  With only a name to go on, a model will confidently suggest an exercise the gym doesn't equip
  or that loads the exact joint being protected, and nothing in the system could catch it.

## Order to tackle

1. [x] **Rest skip button styling.** Small visual fix with immediate payoff.
2. [x] **Size up reps and RPE controls.** Keep the current editing model, improve legibility and tap targets.
3. [x] **Add weight and reps to Up next.** Make prep screens more useful before each set/exercise.
4. [x] **Workout start summary + first Up next.** Add the full-plan summary after start, then show Up next before the first exercise and every exercise transition.
5. [x] **Timed exercise duration input.** Replace raw seconds entry with minute/second-first controls and optional hours.
6. [x] **Optional RPE capture.** Let users finish sets without RPE while preserving optional RPE analytics data.
7. [x] **Theme 2: History implementation.** Watch History, watch→phone completed-session sync, and iPhone History summary/detail gaps are implemented and build-tested.
8. [x] **Theme 2: paired-device shakedown.** Complete a workout on watch hardware and verify the iPhone receives it in History.
9. **Analytics polish.** Improve sparse-data chart presentation, point selection, source-workout details, and later add average/average-of-top-N set metrics.
10. **Theme 1: iPhone workout editor polish.** WatchConnectivity sync backbone exists; remaining work is real-device sync shakedown plus any editor affordances found during use.
11. **Theme 6a: exercise identity migration.** Do this early, while the store is still small
    enough that a name-match backfill is safe. Blocks nothing else, but gets harder with time.
12. **Theme 3: Recovery UI.** (1 evening once #6 is done — sync-ish skeleton already exists.)
13. **Theme 4: Complication.** (1 evening — widget + deep link.)
14. **Log real training.** The coach needs roughly 6–8 weeks of real sessions before it can be
    built or verified. This is the actual gate on v3, and it is not an engineering task.
15. **Theme 6b–6e: the coach**, once #14 has produced data. Backtest first, then the engine,
    then the phone review screen, then narration.
16. **Theme 5: App Store**, only if user opts in.

## Out of scope (still)

- iCloud / cross-device sync across multiple iPhones. WatchConnectivity is enough for one pair.
- Music control. Spotify keeps playing on its own; we still don't claim `AVAudioSession`.
- Action Button (Ultra). No public API.
- Apple Health import (treadmill, cycling, etc.). This is a strength app.
- Form feedback, video, and on-watch rep detection from motion data. Still out at any version.
- Natural-language workout authoring, and any language model that emits a training load. See
  Theme 6 — the coach is deterministic; a model may only explain it.

## Engineering invariants to keep

These are load-bearing — don't break them.

- **`SessionEngine` stays pure-Swift testable.** Every new transition gets a unit test in `WorkoutCoreTests`. Inject `nowProvider`, never read `Date()` directly inside the engine.
- **Wall-clock timers, never `Timer.scheduledTimer`.** Even when adding a workout-rest-time complication.
- **`HKWorkoutSession` only — no `WKExtendedRuntimeSession`** during an active session.
- **Don't configure `AVAudioSession`.** Spotify must keep playing.
- **HealthKit lifecycle**: always `endCollection(...)` *then* `finishWorkout(...)`. Both calls.
- **SwiftData schema-breaking changes go through a new versioned schema + stage in `WorkoutMigrationPlan`.** `WorkoutSchemaV1` is frozen as the on-disk shape for users updating from the prior build; `WorkoutSchemaV2` is current. The next break adds `WorkoutSchemaV3` with its own nested `@Model` types, appends a stage, and retargets the module-level typealiases. Lightweight additions still must be migration-safe for real devices — optional stored fields plus computed resolved values are acceptable when the old store can load cleanly.
- **No `@Model` types crossing process boundaries.** Always encode to a `Codable` DTO before sending over `WCSession` or saving to a file.
