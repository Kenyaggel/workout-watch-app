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
open WorkoutApp/WorkoutApp.xcodeproj
```

The watch app generally needs Xcode and a watch simulator/provisioning setup. Do not assume the full watch target can be built reliably from CLI.

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
- Adding an exercise to a workout should use the fast setup flow: choose set count, optional weight, target reps/duration/distance, and rest, then create repeated `PlannedSet` rows under one `PlannedExercise`.
- Keep watch execution and HealthKit behavior unchanged when working on iPhone-only authoring.

## watchOS Notes

- `Stepper` can steal the Digital Crown when focused. Prefer custom plus/minus buttons where scrolling must remain natural.
- Crown-driven controls usually need separate state for visual highlight and focus ownership.
- Avoid `@MainActor` `deinit` cleanup that touches actor-isolated properties. Prefer task cancellation on phase transitions and weak captures.

## Editing Expectations

- Follow the existing Swift style: small value types in the core package, injected protocols at boundaries, focused SwiftUI views in the watch target.
- Keep feature changes narrow. Avoid unrelated project-file churn.
- When adding iPhone UI files, put them under `WorkoutApp/WorkoutApp/Views/`.
- When adding watch UI files, put them under `WorkoutApp/WorkoutApp Watch App/Views/`.
- When adding core tests, use the existing `var t: Date` plus `nowProvider` pattern.
- Before finishing code changes, run `cd WorkoutCore && swift test` when the change touches `WorkoutCore`.
