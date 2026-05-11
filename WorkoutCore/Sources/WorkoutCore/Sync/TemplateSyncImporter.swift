import Foundation
import SwiftData

public enum TemplateSyncImporter {
    @MainActor
    public static func replaceTemplates(
        with snapshot: TemplateSyncSnapshot,
        in context: ModelContext
    ) throws {
        let existingTemplates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        for template in existingTemplates {
            context.delete(template)
        }
        try context.save()

        let exercisesByID = try upsertExercises(from: snapshot.templates, in: context)

        for templateDTO in snapshot.templates {
            let template = WorkoutTemplate(
                id: templateDTO.id,
                name: templateDTO.name,
                createdAt: templateDTO.createdAt
            )
            context.insert(template)

            for plannedExerciseDTO in templateDTO.plannedExercises {
                guard let exercise = exercisesByID[plannedExerciseDTO.exercise.id] else { continue }
                let plannedExercise = PlannedExercise(
                    id: plannedExerciseDTO.id,
                    orderIndex: plannedExerciseDTO.orderIndex,
                    exercise: exercise,
                    restSec: plannedExerciseDTO.restSec
                )
                plannedExercise.template = template
                context.insert(plannedExercise)

                for setDTO in plannedExerciseDTO.sets {
                    let set = PlannedSet(
                        id: setDTO.id,
                        orderIndex: setDTO.orderIndex,
                        targetWeightKg: setDTO.targetWeightKg,
                        targetReps: setDTO.targetReps,
                        targetDurationSec: setDTO.targetDurationSec,
                        targetDistanceM: setDTO.targetDistanceM
                    )
                    set.plannedExercise = plannedExercise
                    context.insert(set)
                }
            }
        }

        try context.save()
    }

    @MainActor
    private static func upsertExercises(
        from templates: [WorkoutTemplateSyncDTO],
        in context: ModelContext
    ) throws -> [UUID: Exercise] {
        let existingExercises = try context.fetch(FetchDescriptor<Exercise>())
        var exercisesByID = Dictionary(uniqueKeysWithValues: existingExercises.map { ($0.id, $0) })
        let incomingExercises = templates
            .flatMap(\.plannedExercises)
            .map(\.exercise)

        for dto in incomingExercises {
            let exercise = exercisesByID[dto.id] ?? Exercise(
                id: dto.id,
                name: dto.name,
                kind: dto.kind,
                defaultRestSec: dto.defaultRestSec,
                defaultTargetReps: dto.defaultTargetReps,
                defaultTargetDurationSec: dto.defaultTargetDurationSec,
                defaultTargetDistanceM: dto.defaultTargetDistanceM
            )
            if exercisesByID[dto.id] == nil {
                context.insert(exercise)
                exercisesByID[dto.id] = exercise
            }
            exercise.name = dto.name
            exercise.kind = dto.kind
            exercise.defaultRestSec = dto.defaultRestSec
            exercise.defaultTargetReps = dto.defaultTargetReps
            exercise.defaultTargetDurationSec = dto.defaultTargetDurationSec
            exercise.defaultTargetDistanceM = dto.defaultTargetDistanceM
        }

        return exercisesByID
    }
}
