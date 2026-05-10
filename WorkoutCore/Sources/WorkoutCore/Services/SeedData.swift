import Foundation
import SwiftData

public enum SeedData {
    /// Inserts an example "Push Day" template if no templates exist.
    @MainActor
    public static func seedIfEmpty(context: ModelContext) {
        let descriptor = FetchDescriptor<WorkoutTemplate>()
        let existing = (try? context.fetch(descriptor)) ?? []
        guard existing.isEmpty else { return }

        let benchPress = Exercise(
            name: "Bench Press",
            kind: .reps,
            defaultRestSec: 120,
            defaultTargetReps: 8
        )
        let inclineDB = Exercise(
            name: "Incline DB Press",
            kind: .reps,
            defaultRestSec: 90,
            defaultTargetReps: 10
        )
        let plank = Exercise(
            name: "Plank",
            kind: .timed,
            defaultRestSec: 60,
            defaultTargetDurationSec: 45
        )

        [benchPress, inclineDB, plank].forEach { context.insert($0) }

        let template = WorkoutTemplate(name: "Push Day")
        context.insert(template)

        let pe1 = PlannedExercise(orderIndex: 0, exercise: benchPress)
        pe1.template = template
        context.insert(pe1)
        for i in 0..<4 {
            let s = PlannedSet(
                orderIndex: i,
                targetWeightKg: 60,
                targetReps: 8
            )
            s.plannedExercise = pe1
            context.insert(s)
        }

        let pe2 = PlannedExercise(orderIndex: 1, exercise: inclineDB)
        pe2.template = template
        context.insert(pe2)
        for i in 0..<3 {
            let s = PlannedSet(
                orderIndex: i,
                targetWeightKg: 22.5,
                targetReps: 10
            )
            s.plannedExercise = pe2
            context.insert(s)
        }

        let pe3 = PlannedExercise(orderIndex: 2, exercise: plank)
        pe3.template = template
        context.insert(pe3)
        for i in 0..<3 {
            let s = PlannedSet(
                orderIndex: i,
                targetDurationSec: 45
            )
            s.plannedExercise = pe3
            context.insert(s)
        }

        try? context.save()
    }
}
