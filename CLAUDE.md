# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Apple Watch Ultra workout companion. Watch app drives the moment-to-moment loop of a strength workout (in-set / rest / prep), saves sessions to HealthKit, and lets third-party audio (Spotify/Music) play uninterrupted. The iPhone app now owns early workout authoring: reusable Workouts, reusable Exercises, History, and Analytics.

## Layout

```
WorkoutCore/                    Swift Package, shared by both apps. macOS/iOS/watchOS.
WorkoutApp/                     Xcode project lives here.
  WorkoutApp.xcodeproj
  WorkoutApp/                   iOS app target source: Workouts, Exercises, History, Analytics.
  WorkoutApp Watch App/         watchOS app target source. All real UI is here.
project.yml                     XcodeGen spec (optional regen).
```

The Xcode project uses **`PBXFileSystemSynchronizedRootGroup`** (Xcode 16+ synced folder groups). Any file dropped into a target's folder is auto-included — never run "Add Files to…". Just `cp` into the right directory.

## Commands

Run from repo root unless noted.

```bash
# Build & unit-test the shared package (host: macOS 14+).
cd WorkoutCore && swift build
cd WorkoutCore && swift test

# Run a single test
cd WorkoutCore && swift test --filter SessionEngineTests/testRestAutoExpiredAdvancesAtDeadline

# Syntax-check any individual Swift file (works without full build).
swiftc -parse "WorkoutApp/WorkoutApp Watch App/Views/InSetView.swift"

# Build the iPhone app path, including the embedded watch target.
xcodebuild -project WorkoutApp/WorkoutApp.xcodeproj -scheme WorkoutApp -destination 'generic/platform=iOS' build

# Open in Xcode
open WorkoutApp/WorkoutApp.xcodeproj
```

Use Xcode for normal device/simulator runs, especially watch workflows. CLI iPhone builds can work when signing/provisioning is available, but watch run/debug still belongs in Xcode.

## Architecture

Three layers, deliberately separated:

1. **SwiftData models** (`WorkoutCore/Sources/WorkoutCore/Models/`). Templates, exercises, sessions, performed sets. Inheritance is avoided — `Exercise` carries a `kindRaw: String` plus a computed `kind: ExerciseKind` and nullable kind-specific fields. Schema is versioned via `WorkoutSchemaV1: VersionedSchema` from day one.

2. **SessionEngine** (`Services/SessionEngine.swift`). `@MainActor @Observable` finite state machine: `.idle → .inSet → .rest → .inSet | .prep → ... → .complete`. The engine takes a **`SessionPlan`** (immutable value type) as input — this snapshot decouples the engine from SwiftData so it can be unit-tested in pure Swift with a fake `nowProvider`. Persistence and HealthKit are injected via protocols (`SessionRecorder`, `Haptics`).

3. **Wall-clock timers, not tick counters.** Rest mode stores `endsAt: Date`; views compute remaining via `TimelineView(.periodic(...))`. Haptics are scheduled by a single `Task` that `Task.sleep`s until each absolute date and is cancelled on every phase change. Never use `Timer.scheduledTimer` — it drifts when the display sleeps.

### iPhone authoring model

- The iPhone app uses visible "Workouts" language for reusable workout plans, while the underlying SwiftData model remains `WorkoutTemplate` for now.
- The iPhone `Exercises` tab manages reusable `Exercise` records: name, kind, default rest, and kind-specific default target reps/duration/distance. Do not add default weight to `Exercise`; weight is workout-specific.
- Template rest is owned by `PlannedExercise`, not by individual `PlannedSet` rows. `PlannedSet` stores only set targets: weight, reps, duration, and distance.
- `PlannedExercise.restSec` is optional in SwiftData storage so existing on-device stores migrate safely. Read rest through `resolvedRestSec`; write concrete `restSec` values for new or edited planned exercises.
- Adding an exercise to a workout should create a `PlannedExercise` plus repeated `PlannedSet` rows from a fast setup flow: set count, optional weight, target reps/duration/distance, and rest.
- New picked exercises start with sensible defaults if the reusable `Exercise` has no target default: 10 reps, 30 seconds, 1000 meters, and one set for distance exercises. The set editor's add button should copy the last set's targets or fall back to these defaults.
- In workout detail navigation, use direct destination links for `PlannedExerciseDetailView`. Avoid value-based `NavigationLink(value:)` / `navigationDestination(for: PlannedExercise.self)` routing for SwiftData `PlannedExercise`; it produced duplicate/missing destination warnings and delayed navigation on device.
- Keep watch template execution behavior unchanged unless the task explicitly targets watch sync or watch UI wording.

### SwiftData migration notes

- This app has real on-device stores. New `@Model` attributes must be migration-safe: optional with a computed resolved value, explicitly migrated, or backfilled before they become required.
- For future schema-breaking changes, add a new versioned schema and migration stage instead of relying on launch-time crashes to expose store mismatches.

### Recorder/HealthKit decoupling

- `SessionRecorder` protocol → `SwiftDataRecorder` (prod) / `InMemorySessionRecorder` (tests).
- `WorkoutLifecycle` protocol → `HealthKitManager` (prod, watchOS only) / `NoopWorkoutLifecycle` (everything else). HealthKit imports are gated `#if canImport(HealthKit) && os(watchOS)` so the package still builds on macOS for tests.

## watchOS gotchas

- **`Stepper` auto-claims the Digital Crown** when focused, even if you didn't bind crown rotation to it. If you want the crown to scroll the page by default, replace Steppers with custom +/- buttons (see `InSetView.counterRow`).
- **Use two state vars for crown-driven controls**: a regular `@State Bool` for the visual highlight + a `@FocusState Bool` for crown ownership. A single `@FocusState` driving both produces unreliable visual updates.
- **`@MainActor` classes cannot have a `deinit` that touches main-actor properties.** Use `weak self` inside background tasks instead of cleaning up in deinit.
- **`HKWorkoutSession` is sufficient on its own** for background execution and to keep third-party audio playing. Do **not** stack `WKExtendedRuntimeSession` during an active workout — they conflict. Do **not** configure `AVAudioSession` (would steal audio from Spotify/Music).
- **HealthKit lifecycle**: `endCollection(...)` then `finishWorkout(...)`. Both are required — dropping `finishWorkout` means the workout never appears in the Health app.

## Info.plist / capabilities

Xcode 16 doesn't generate a physical `Info.plist`; the watch target's plist values live in `WorkoutApp.xcodeproj/project.pbxproj` as `INFOPLIST_KEY_*` build settings. Required keys (verified in pbxproj):

- `INFOPLIST_KEY_NSHealthShareUsageDescription`
- `INFOPLIST_KEY_NSHealthUpdateUsageDescription`

Without these the app crashes with `NSInvalidArgumentException` the first time HealthKit auth is requested. Background mode "Workout processing" is enabled via the watch target's Capabilities.

## When adding features to the engine

Cover every new transition with a test in `WorkoutCoreTests/SessionEngineTests`. Existing tests inject a `var t: Date` closure as `nowProvider` and mutate `t` between calls to drive deterministic time.
