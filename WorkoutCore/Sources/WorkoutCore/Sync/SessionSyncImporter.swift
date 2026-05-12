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

        for setDTO in dto.performedSets {
            let performedSet = PerformedSet(
                id: setDTO.id,
                orderIndex: setDTO.orderIndex,
                exerciseName: setDTO.exerciseName,
                exerciseIndex: setDTO.exerciseIndex,
                setIndex: setDTO.setIndex,
                weightKg: setDTO.weightKg,
                reps: setDTO.reps,
                durationSec: setDTO.durationSec,
                distanceM: setDTO.distanceM,
                rpe: setDTO.rpe,
                completedAt: setDTO.completedAt
            )
            performedSet.session = workoutSession
            context.insert(performedSet)
        }

        try context.save()
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
