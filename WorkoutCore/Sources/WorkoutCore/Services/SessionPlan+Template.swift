import Foundation

public extension SessionPlan {
    /// Builds an immutable session plan from a stored template.
    /// Resolves rest times: per-set override → exercise default.
    static func from(template: WorkoutTemplate) -> SessionPlan {
        let exercises: [SessionPlan.Exercise] = template.orderedExercises.compactMap { plannedEx in
            guard let exercise = plannedEx.exercise else { return nil }
            let sets: [SessionPlan.Set] = plannedEx.orderedSets.map { plannedSet in
                SessionPlan.Set(
                    targetWeightKg: plannedSet.targetWeightKg,
                    targetReps: plannedSet.targetReps,
                    targetDurationSec: plannedSet.targetDurationSec,
                    targetDistanceM: plannedSet.targetDistanceM,
                    restSec: plannedSet.restOverrideSec ?? exercise.defaultRestSec
                )
            }
            return SessionPlan.Exercise(
                name: exercise.name,
                kind: exercise.kind,
                sets: sets
            )
        }
        return SessionPlan(templateName: template.name, exercises: exercises)
    }
}
