# AGENTS.md

Guidance for Codex and other coding agents working in this repository. This file is based on `CLAUDE.md` plus the current project layout.

## Project Snapshot

This is an Apple Watch Ultra workout companion. The watchOS app owns the real workout flow: prep, in-set, rest, session summary, haptics, SwiftData persistence, and HealthKit workout lifecycle. The iPhone target now owns early authoring and review flows: Workouts, Exercises, History, and Analytics.

Core behavior lives in the `WorkoutCore` Swift package so it can be built and tested on macOS without requiring a watch simulator.

## Layout

```text
WorkoutCore/                    Swift package shared by iOS/watchOS/macOS.
  Sources/WorkoutCore/Models/    SwiftData schema and domain models.
  Sources/WorkoutCore/Services/  Session engine, recorder, haptics, seed data.
  Sources/WorkoutCore/Health/    HealthKit lifecycle abstractions.
  Tests/WorkoutCoreTests/        Unit tests, especially SessionEngineTests.

WorkoutApp/                     Xcode project and app targets.
  WorkoutApp.xcodeproj           Main Xcode project.
  WorkoutApp/                    iOS app target source: Workouts, Exercises, History, Analytics.
  WorkoutApp Watch App/          watchOS app target source, primary user UI.

CLAUDE.md                       Original project guidance.
project.yml                     XcodeGen spec, currently optional/stale.
```

The checked-in Xcode project uses Xcode 16 file-system-synchronized groups. New files placed in the correct target folder should be picked up by Xcode automatically.

## Important Caveat

`project.yml` does not currently match the checked-in app folders: it references `WatchApp` and `iPhoneApp`, while the repository has `WorkoutApp/WorkoutApp Watch App` and `WorkoutApp/WorkoutApp`. Treat `project.yml` as stale unless it is intentionally refreshed alongside the project structure.

## Commands

Run from the repository root unless noted.

```bash
cd WorkoutCore && swift build
cd WorkoutCore && swift test
cd WorkoutCore && swift test --filter SessionEngineTests/testRestAutoExpiredAdvancesAtDeadline
swiftc -parse "WorkoutApp/WorkoutApp Watch App/Views/InSetView.swift"
xcodebuild -project WorkoutApp/WorkoutApp.xcodeproj -scheme WorkoutApp -destination 'generic/platform=iOS' build
open WorkoutApp/WorkoutApp.xcodeproj
```

The iPhone app can be checked from CLI with the `xcodebuild` command above. The watch app generally needs Xcode and a watch simulator/provisioning setup; do not assume the full watch target can be built reliably from CLI.

## Architecture Rules

- Keep `WorkoutCore` platform-safe. Gate watch-only HealthKit code with `#if canImport(HealthKit) && os(watchOS)`.
- Keep `SessionEngine` independent from SwiftData. It should take an immutable `SessionPlan`, injected `SessionRecorder`, injected `Haptics`, and an injectable `nowProvider`.
- Preserve deterministic time in tests. Add or update `SessionEngineTests` for every new engine transition.
- Use wall-clock deadlines for rest periods. Rest stores `endsAt: Date`; UI should compute remaining time from the clock.
- Do not introduce tick-counter timers or `Timer.scheduledTimer` for rest behavior.
- Do not stack `WKExtendedRuntimeSession` on top of an active `HKWorkoutSession`.
- Do not configure `AVAudioSession`; the app should not steal audio from Spotify/Music.
- HealthKit workout completion requires both ending collection and finishing the workout.

## iPhone Authoring Notes

- User-facing iPhone language calls reusable plans "Workouts"; the backing model is still `WorkoutTemplate` to avoid unnecessary schema churn.
- `Exercise` is the reusable movement definition. It should contain name, kind, default rest, and kind-specific default target reps/duration/distance.
- Do not put default weight on `Exercise`; weight is specific to a workout prescription and belongs on `PlannedSet`.
- Rest inside a workout template belongs to `PlannedExercise`, not `PlannedSet`. Use `PlannedExercise.resolvedRestSec` when reading so existing on-device SwiftData stores can fall back to the linked exercise default.
- `PlannedSet` should only contain set-specific targets: weight, reps, duration, and distance. Do not reintroduce per-set rest unless the product explicitly needs mixed-rest sets.
- Adding an exercise to a workout should use the fast setup flow: choose set count, optional weight, target reps/duration/distance, and rest, then create repeated `PlannedSet` rows under one `PlannedExercise`.
- New picked exercises should start with sensible target defaults: reps default to 10, timed duration to 30 seconds, distance to 1000 meters, and distance work defaults to one set. Adding another set in the detail editor should copy the last set's targets or fall back to the exercise defaults.
- In `TemplateDetailView`, prefer direct `NavigationLink { PlannedExerciseDetailView(...) }` links for planned exercise rows. Avoid `NavigationLink(value:)` plus `navigationDestination(for: PlannedExercise.self)` for SwiftData model objects; it caused on-device duplicate/missing destination routing.
- Keep watch execution and HealthKit behavior unchanged when working on iPhone-only authoring.

## SwiftData Migration Notes

- Existing iPhone installs may already have a persistent store. New stored properties on `@Model` types should either be optional with a computed resolved value, have an explicit migration, or be safely backfilled before becoming mandatory.
- The schema is currently at `WorkoutSchemaV2`. Every `@Model` type is nested inside both `WorkoutSchemaV1` and `WorkoutSchemaV2` (see `SchemaV1.swift` / `SchemaV2.swift`); module-level typealiases bind the bare names (`PlannedSet`, `Exercise`, …) to the V2 nested types so call sites don't change.
- `WorkoutMigrationPlan` (in `Schema.swift`) runs a custom V1→V2 stage: `willMigrate` reads each `PlannedSet.restOverrideSec` and stashes the first non-nil value per parent; `didMigrate` writes it onto `PlannedExercise.restSec`. Don't mutate `WorkoutSchemaV1` in place — it's frozen as the on-disk shape for users updating from the prior build.
- `PlannedExercise.restSec` is intentionally optional in storage so migrated rows that pre-date the rest-lifting stage still load. App code should write concrete values for new/edited planned exercises and read through `resolvedRestSec`.
- For the next schema-breaking change: add `WorkoutSchemaV3` with its own nested `@Model` types, append a stage to `WorkoutMigrationPlan.stages`, and retarget the module-level typealiases. Use `MigrationTests` as the template for verifying the migration on a real on-disk store.

## watchOS Notes

- `Stepper` can steal the Digital Crown when focused. Prefer custom plus/minus buttons where scrolling must remain natural.
- Crown-driven controls usually need separate state for visual highlight and focus ownership.
- Avoid `@MainActor` `deinit` cleanup that touches actor-isolated properties. Prefer task cancellation on phase transitions and weak captures.

## Editing Expectations

- Follow the existing Swift style: small value types in the core package, injected protocols at boundaries, focused SwiftUI views in the watch target.
- Keep feature changes narrow. Avoid unrelated project-file churn.
- When adding iPhone UI files, put them under `WorkoutApp/WorkoutApp/Views/`.
- Reusable iPhone form components (numeric text fields, formatters, etc.) belong under `WorkoutApp/WorkoutApp/Views/Components/`. `NumberFields.swift` already exports `OptionalDoubleField`, `OptionalIntField`, and `RequiredIntField` with an `onChange(of: value)` mirror; reuse them instead of defining new private copies inside detail views.
- Date helpers go in `WorkoutApp/WorkoutApp/Extensions/Date+Formatting.swift` (`formattedDate(_:)`, `formatDuration(_:_:)`).
- When pickers select a SwiftData model, key on `persistentModelID` rather than on user-mutable strings like `name` — see `AnalyticsDashboardView`.
- For combined analytics (progression + e1RM for the same exercise), call `AnalyticsEngine.exerciseAnalytics(name:last:)` once instead of two separate methods; it shares the fetch and grouping.
- When adding watch UI files, put them under `WorkoutApp/WorkoutApp Watch App/Views/`.
- When adding core tests, use the existing `var t: Date` plus `nowProvider` pattern.
- Before finishing code changes, run `cd WorkoutCore && swift test` when the change touches `WorkoutCore`.
