import Foundation
import SwiftData

public enum SessionSyncImporter {
    @MainActor
    public static func upsert(
        _ snapshot: SessionSyncSnapshot,
        in context: ModelContext
    ) throws {
        let dto = snapshot.session
        let existingSession = try session(matching: dto.id, in: context)
        let workoutSession: WorkoutSession
        if let existingSession {
            workoutSession = existingSession
        } else {
            workoutSession = WorkoutSession(
                id: dto.id,
                startedAt: dto.startedAt,
                templateName: dto.templateName,
                template: try template(matching: dto.templateID, in: context)
            )
        }

        if existingSession == nil {
            context.insert(workoutSession)
        }

        workoutSession.startedAt = dto.startedAt
        workoutSession.endedAt = dto.endedAt
        workoutSession.templateName = dto.templateName
        workoutSession.healthKitWorkoutUUID = dto.healthKitWorkoutUUID
        workoutSession.template = try template(matching: dto.templateID, in: context)

        for performedSet in Array(workoutSession.performedSets) {
            context.delete(performedSet)
        }
        try context.save()

        let exerciseIDs = try unambiguousExerciseIDsByName(in: context)

        for setDTO in dto.performedSets {
            let performedSet = PerformedSet(
                id: setDTO.id,
                orderIndex: setDTO.orderIndex,
                exerciseName: setDTO.exerciseName,
                exerciseID: setDTO.exerciseID ?? exerciseIDs[normalizedName(setDTO.exerciseName)],
                exerciseIndex: setDTO.exerciseIndex,
                setIndex: setDTO.setIndex,
                weightKg: setDTO.weightKg,
                reps: setDTO.reps,
                durationSec: setDTO.durationSec,
                distanceM: setDTO.distanceM,
                rpe: setDTO.rpe,
                completedAt: setDTO.completedAt,
                targetWeightKg: setDTO.targetWeightKg,
                targetReps: setDTO.targetReps,
                targetDurationSec: setDTO.targetDurationSec,
                targetDistanceM: setDTO.targetDistanceM
            )
            performedSet.session = workoutSession
            context.insert(performedSet)
        }

        try context.save()
    }

    /// Names that map to exactly one library `Exercise`. A name shared by two exercises
    /// is deliberately absent: guessing between them would invent a Lift Identity that is
    /// wrong, and a null identity falls back to name matching, which is no worse than the
    /// behaviour this replaces.
    @MainActor
    private static func unambiguousExerciseIDsByName(
        in context: ModelContext
    ) throws -> [String: UUID] {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        var byName: [String: UUID] = [:]
        var ambiguous: Swift.Set<String> = []
        for exercise in exercises {
            let key = normalizedName(exercise.name)
            if byName[key] != nil {
                ambiguous.insert(key)
            } else {
                byName[key] = exercise.id
            }
        }
        for name in ambiguous {
            byName.removeValue(forKey: name)
        }
        return byName
    }

    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    @MainActor
    private static func session(
        matching id: UUID,
        in context: ModelContext
    ) throws -> WorkoutSession? {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    @MainActor
    private static func template(
        matching id: UUID?,
        in context: ModelContext
    ) throws -> WorkoutTemplate? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<WorkoutTemplate>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }
}
