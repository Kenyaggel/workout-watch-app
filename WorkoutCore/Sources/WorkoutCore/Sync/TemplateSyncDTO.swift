import Foundation
import SwiftData

public struct TemplateSyncSnapshot: Codable, Equatable, Sendable {
    public var templates: [WorkoutTemplateSyncDTO]

    public init(templates: [WorkoutTemplateSyncDTO]) {
        self.templates = templates.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    public init(templates: [WorkoutTemplate]) {
        self.init(templates: templates.map(WorkoutTemplateSyncDTO.init(template:)))
    }
}

public struct WorkoutTemplateSyncDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var plannedExercises: [PlannedExerciseSyncDTO]

    public init(
        id: UUID,
        name: String,
        createdAt: Date,
        plannedExercises: [PlannedExerciseSyncDTO]
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.plannedExercises = plannedExercises.sorted { $0.orderIndex < $1.orderIndex }
    }

    public init(template: WorkoutTemplate) {
        self.init(
            id: template.id,
            name: template.name,
            createdAt: template.createdAt,
            plannedExercises: template.orderedExercises.compactMap(PlannedExerciseSyncDTO.init(plannedExercise:))
        )
    }
}

public struct ExerciseSyncDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: ExerciseKind
    public var defaultRestSec: Int
    public var defaultTargetReps: Int?
    public var defaultTargetDurationSec: Int?
    public var defaultTargetDistanceM: Double?

    public init(
        id: UUID,
        name: String,
        kind: ExerciseKind,
        defaultRestSec: Int,
        defaultTargetReps: Int?,
        defaultTargetDurationSec: Int?,
        defaultTargetDistanceM: Double?
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.defaultRestSec = defaultRestSec
        self.defaultTargetReps = defaultTargetReps
        self.defaultTargetDurationSec = defaultTargetDurationSec
        self.defaultTargetDistanceM = defaultTargetDistanceM
    }

    public init(exercise: Exercise) {
        self.init(
            id: exercise.id,
            name: exercise.name,
            kind: exercise.kind,
            defaultRestSec: exercise.defaultRestSec,
            defaultTargetReps: exercise.defaultTargetReps,
            defaultTargetDurationSec: exercise.defaultTargetDurationSec,
            defaultTargetDistanceM: exercise.defaultTargetDistanceM
        )
    }
}

public struct PlannedExerciseSyncDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var orderIndex: Int
    public var restSec: Int
    public var exercise: ExerciseSyncDTO
    public var sets: [PlannedSetSyncDTO]

    public init(
        id: UUID,
        orderIndex: Int,
        restSec: Int,
        exercise: ExerciseSyncDTO,
        sets: [PlannedSetSyncDTO]
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.restSec = restSec
        self.exercise = exercise
        self.sets = sets.sorted { $0.orderIndex < $1.orderIndex }
    }

    public init?(plannedExercise: PlannedExercise) {
        guard let exercise = plannedExercise.exercise else { return nil }
        self.init(
            id: plannedExercise.id,
            orderIndex: plannedExercise.orderIndex,
            restSec: plannedExercise.resolvedRestSec,
            exercise: ExerciseSyncDTO(exercise: exercise),
            sets: plannedExercise.orderedSets.map(PlannedSetSyncDTO.init(plannedSet:))
        )
    }
}

public struct PlannedSetSyncDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var orderIndex: Int
    public var targetWeightKg: Double?
    public var targetReps: Int?
    public var targetDurationSec: Int?
    public var targetDistanceM: Double?

    public init(
        id: UUID,
        orderIndex: Int,
        targetWeightKg: Double?,
        targetReps: Int?,
        targetDurationSec: Int?,
        targetDistanceM: Double?
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.targetWeightKg = targetWeightKg
        self.targetReps = targetReps
        self.targetDurationSec = targetDurationSec
        self.targetDistanceM = targetDistanceM
    }

    public init(plannedSet: PlannedSet) {
        self.init(
            id: plannedSet.id,
            orderIndex: plannedSet.orderIndex,
            targetWeightKg: plannedSet.targetWeightKg,
            targetReps: plannedSet.targetReps,
            targetDurationSec: plannedSet.targetDurationSec,
            targetDistanceM: plannedSet.targetDistanceM
        )
    }
}
