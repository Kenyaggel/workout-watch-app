# CODEX.md

Codex project notes for the Apple Watch workout companion.

## What This App Is

A watch-first strength workout app. The watch target manages the live workout loop, logs performed sets, uses haptics around rest/set transitions, saves sessions through SwiftData, and integrates with HealthKit without interrupting third-party audio. The iPhone app now provides early authoring and review surfaces: Workouts, Exercises, History, and Analytics.

## Current Shape

- `WorkoutCore` is the shared Swift package and the safest place for domain behavior.
- `SessionEngine` is the finite-state machine for workout execution.
- `SessionPlan` is an immutable snapshot used by the engine, decoupling live workout behavior from SwiftData.
- `SessionRecorder`, `Haptics`, and `WorkoutLifecycle` keep persistence, feedback, and HealthKit behind protocols.
- Watch UI lives under `WorkoutApp/WorkoutApp Watch App`.
- iOS UI lives under `WorkoutApp/WorkoutApp`.
- iPhone visible language uses "Workouts" for reusable plans, but the model is still `WorkoutTemplate`; avoid schema churn unless explicitly requested.
- iPhone `Exercise` management owns name, kind, default rest, and kind-specific default target. Weight belongs to workout-specific planned sets, not reusable exercises.
- In a template, rest belongs to `PlannedExercise`. `PlannedSet` is for set-specific targets only: weight, reps, duration, and distance.
- `PlannedExercise.restSec` is optional in storage so migrated rows from earlier app versions still load; read with `resolvedRestSec` and write concrete values for new/edited planned exercises.
- The SwiftData schema is at `WorkoutSchemaV2`. Every `@Model` class is nested inside both `WorkoutSchemaV1` (`SchemaV1.swift`) and `WorkoutSchemaV2` (`SchemaV2.swift`); module-level typealiases bind the bare names to V2. `WorkoutMigrationPlan` carries a custom V1→V2 stage that lifts `PlannedSet.restOverrideSec` onto `PlannedExercise.restSec`. Treat `WorkoutSchemaV1` as frozen; the next break adds `WorkoutSchemaV3` + a new stage.
- Reusable iPhone form components live under `WorkoutApp/WorkoutApp/Views/Components/` (`NumberFields.swift` with `OptionalDoubleField` / `OptionalIntField` / `RequiredIntField`). Date and duration helpers live in `WorkoutApp/WorkoutApp/Extensions/Date+Formatting.swift`. For combined exercise analytics use `AnalyticsEngine.exerciseAnalytics(name:last:)` rather than two separate calls.
- Adding an exercise to a workout should go through the fast setup flow that creates one `PlannedExercise` and repeated `PlannedSet` rows with sensible defaults. Reps default to 10, timed duration to 30 seconds, distance to 1000 meters, and distance work starts at one set.
- Planned exercise rows should navigate with direct destination `NavigationLink`s. Avoid value-based navigation destinations for `PlannedExercise` SwiftData models in the template editor.

## Build And Test

```bash
cd WorkoutCore && swift build
cd WorkoutCore && swift test
xcodebuild -project WorkoutApp/WorkoutApp.xcodeproj -scheme WorkoutApp -destination 'generic/platform=iOS' build
```

Open the full app in Xcode:

```bash
open WorkoutApp/WorkoutApp.xcodeproj
```

Use Xcode for watch app build/run workflows.

## Codex Working Notes

- Read `CLAUDE.md` first when returning to this project; it contains detailed historical guidance.
- Also read `AGENTS.md`; it is the Codex-owned operational guide.
- Be careful with `project.yml`. It appears out of date compared with the checked-in Xcode project and folder names.
- Prefer changing the Swift package for business logic and adding macOS-runnable tests there.
- Keep watch target changes focused on presentation, interaction, haptics wiring, and HealthKit lifecycle wiring.
- Keep iPhone authoring changes in the iOS target unless shared model/session behavior truly needs to change.
- Treat SwiftData schema changes as on-device migrations. New model fields should be optional/resolved or covered by an explicit migration before they are required. The V1→V2 stage in `WorkoutMigrationPlan` is the working template; `MigrationTests` shows how to verify a stage end-to-end on a file-backed store.
