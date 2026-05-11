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
- [ ] **Timed exercise duration input** — timed exercise setup/editing should use ergonomic hours/minutes/seconds controls instead of forcing raw seconds. Hours should be optional/collapsed so common minute/second entries do not require typing `00` for hours.
- [ ] **Optional RPE capture** — completing a set should not force RPE entry. Keep RPE available for users who want to log it, store missing RPE as nil, and make later analytics ignore nil values rather than treating them as low effort.

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

- **Watch**: `SessionSummaryView` already exists for end-of-session; add a "History" tab showing last 10 sessions (date, total volume, duration).
- **iPhone**: full history list → session detail (per-set actuals, RPE, planned vs done diff). Charts (weekly volume, e1RM per exercise) are a stretch.
- **Status**: iPhone History and Analytics screens exist, but History still needs real-world testing before calling this theme complete.
- **Data is already there** — `WorkoutSession` + `PerformedSet` records every set. This is pure UI work on top of existing models.
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

## Order to tackle

1. [x] **Rest skip button styling.** Small visual fix with immediate payoff.
2. [x] **Size up reps and RPE controls.** Keep the current editing model, improve legibility and tap targets.
3. [x] **Add weight and reps to Up next.** Make prep screens more useful before each set/exercise.
4. [x] **Workout start summary + first Up next.** Add the full-plan summary after start, then show Up next before the first exercise and every exercise transition.
5. **Timed exercise duration input.** Replace raw seconds entry with minute/second-first controls and optional hours.
6. **Optional RPE capture.** Let users finish sets without RPE while preserving optional RPE analytics data.
7. **Theme 2: History verification.** Test the existing iPhone History flow with real saved workouts; fix gaps found there.
8. **Theme 1: iPhone workout editor polish.** WatchConnectivity sync backbone exists; remaining work is real-device sync shakedown plus any editor affordances found during use.
9. **Theme 3: Recovery UI.** (1 evening once #6 is done — sync-ish skeleton already exists.)
10. **Theme 4: Complication.** (1 evening — widget + deep link.)
11. **Theme 5: App Store**, only if user opts in.

## Out of scope (still)

- iCloud / cross-device sync across multiple iPhones. WatchConnectivity is enough for one pair.
- Music control. Spotify keeps playing on its own; we still don't claim `AVAudioSession`.
- Action Button (Ultra). No public API.
- Apple Health import (treadmill, cycling, etc.). This is a strength app.
- AI / form feedback / video. Not a thing for v2.

## Engineering invariants to keep

These are load-bearing — don't break them.

- **`SessionEngine` stays pure-Swift testable.** Every new transition gets a unit test in `WorkoutCoreTests`. Inject `nowProvider`, never read `Date()` directly inside the engine.
- **Wall-clock timers, never `Timer.scheduledTimer`.** Even when adding a workout-rest-time complication.
- **`HKWorkoutSession` only — no `WKExtendedRuntimeSession`** during an active session.
- **Don't configure `AVAudioSession`.** Spotify must keep playing.
- **HealthKit lifecycle**: always `endCollection(...)` *then* `finishWorkout(...)`. Both calls.
- **SwiftData schema-breaking changes go through a new versioned schema + stage in `WorkoutMigrationPlan`.** `WorkoutSchemaV1` is frozen as the on-disk shape for users updating from the prior build; `WorkoutSchemaV2` is current. The next break adds `WorkoutSchemaV3` with its own nested `@Model` types, appends a stage, and retargets the module-level typealiases. Lightweight additions still must be migration-safe for real devices — optional stored fields plus computed resolved values are acceptable when the old store can load cleanly.
- **No `@Model` types crossing process boundaries.** Always encode to a `Codable` DTO before sending over `WCSession` or saving to a file.
