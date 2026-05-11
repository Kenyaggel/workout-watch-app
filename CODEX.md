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
- Adding an exercise to a workout should go through the fast setup flow that creates one `PlannedExercise` and repeated `PlannedSet` rows.

## Build And Test

```bash
cd WorkoutCore && swift build
cd WorkoutCore && swift test
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
