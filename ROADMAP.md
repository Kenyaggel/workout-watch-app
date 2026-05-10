# Roadmap — Workout Watch App

Where v1 ended and where v2 takes us. Use this as the working plan; tick items off as they land.

## v1 — what shipped

- Three-mode session loop: **in-set / rest / prep** with wall-clock timers via `TimelineView`.
- `SessionEngine` finite state machine, fully unit-tested (13/13 green) against an injected `nowProvider`.
- `WorkoutCore` Swift Package with versioned SwiftData schema (`WorkoutSchemaV1`) and a clean recorder/lifecycle protocol split so the package builds on macOS for tests.
- HealthKit recording on watchOS via `HKWorkoutSession` + `HKLiveWorkoutBuilder`, gated `#if canImport(HealthKit) && os(watchOS)`.
- One seeded template (Push Day) so the app is usable from launch.
- iPhone target stubbed (signing/entitlements pre-wired).
- Repo on GitHub (`Kenyaggel/workout-watch-app`), `.gitignore` keeps build artifacts out.

## Carry-over: open bugs / polish

These belong at the top of v2 because they're already half-done.

1. **Digital Crown weight editing** — yellow row + `scrollDisabled` + `.focusable(weightActive)` workaround is in place but needs **on-device verification**. The simulator lies about crown rotation, so this can only be confirmed on the Watch. If still broken, the fallback is a sheet-based weight editor (modal sheets don't share crown ownership with the parent ScrollView).
2. **Reps editing parity** — once weight crown works, apply the same pattern to a tappable `repsRow`. Right now reps is +/- buttons only; crown should adjust it the same way.
3. **App icon** — placeholder `AppIcon.appiconset` is empty. Need a 1024×1024 master and the watchOS sizes derived from it.
4. **Real on-device end-to-end pass** — start workout, complete a full template, lower wrist mid-rest, force-quit and resume, verify Health app shows the workout. None of this has been done yet.

## v2 themes

Five themes, ranked by user value. Each is independently shippable.

### Theme 1: Template authoring (iPhone-first)

The watch can run templates but can't create or edit them. Authoring belongs on the phone — bigger screen, real keyboard.

- **iPhone UI**: list of templates → detail editor with sections per exercise, add/remove/reorder exercises, edit sets (weight, reps, RPE target, rest seconds).
- **Watch UI**: read-only template picker stays as is; **add a "duplicate & edit on phone" affordance** so users discover the phone editor.
- **Sync**: `WatchConnectivity` `WCSession` with `transferUserInfo` for templates (small payloads, queued, survives connectivity gaps). Don't use `sendMessage` — it requires both devices reachable.
- **Files**:
  - `WorkoutApp/WorkoutApp/Views/TemplateListView.swift` (new — iOS)
  - `WorkoutApp/WorkoutApp/Views/TemplateEditorView.swift` (new — iOS)
  - `WorkoutCore/Sources/WorkoutCore/Sync/WatchConnectivityManager.swift` (new)
  - Encode `WorkoutTemplate` → `Codable` DTO (don't ship `@Model` types over the wire).
- **Risks**: SwiftData on both ends + WCSession ordering. Treat the phone as source of truth for templates; the watch overwrites its local copy on receipt. Conflict resolution is "last write wins, scoped per-template-id."

### Theme 2: History & progress

A workout that's saved to HealthKit but invisible inside the app feels half-finished.

- **Watch**: `SessionSummaryView` already exists for end-of-session; add a "History" tab showing last 10 sessions (date, total volume, duration).
- **iPhone**: full history list → session detail (per-set actuals, RPE, planned vs done diff). Charts (weekly volume, e1RM per exercise) are a stretch.
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

- App icon (1024 master).
- `PrivacyInfo.xcprivacy` review (HealthKit + UserDefaults reasons already declared; verify against Apple's required-reason API list).
- Screenshots on a real Watch (App Store Connect requires per-size assets).
- Marketing copy / What's New string.
- TestFlight beta with 2–3 friends before public submission.

## Order to tackle

1. **Verify crown bug on device.** If broken, swap to sheet-based editor. (Half a day.)
2. **Reps crown parity.** (1 hour after #1.)
3. **App icon + on-device E2E test pass.** (Half a day.)
4. **Theme 2: History.** Pure read of existing data, gives an immediate visible payoff. (Weekend project.)
5. **Theme 1: iPhone template editor + sync.** Biggest scope item; do it next while motivation is high. (1–2 weekends.)
6. **Theme 3: Recovery UI.** (1 evening once #5 is done — sync-ish skeleton already exists.)
7. **Theme 4: Complication.** (1 evening — widget + deep link.)
8. **Theme 5: App Store**, only if user opts in.

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
- **SwiftData schema changes go through a new `WorkoutSchemaV2` + `SchemaMigrationPlan`.** Never mutate `WorkoutSchemaV1` in place.
- **No `@Model` types crossing process boundaries.** Always encode to a `Codable` DTO before sending over `WCSession` or saving to a file.
