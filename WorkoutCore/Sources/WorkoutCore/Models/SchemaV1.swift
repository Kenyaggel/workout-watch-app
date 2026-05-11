import Foundation
import SwiftData

public enum WorkoutSchemaV1: VersionedSchema {
    public static var versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            Exercise.self,
            PlannedSet.self,
            PlannedExercise.self,
            WorkoutTemplate.self,
            WorkoutSession.self,
            PerformedSet.self
        ]
    }

    @Model
    public final class Exercise {
        @Attribute(.unique) public var id: UUID
        public var name: String
        public var kindRaw: String
        public var defaultRestSec: Int
        public var defaultTargetReps: Int?
        public var defaultTargetDurationSec: Int?
        public var defaultTargetDistanceM: Double?

        public init(
            id: UUID = UUID(),
            name: String = "",
            kindRaw: String = "reps",
            defaultRestSec: Int = 90,
            defaultTargetReps: Int? = nil,
            defaultTargetDurationSec: Int? = nil,
            defaultTargetDistanceM: Double? = nil
        ) {
            self.id = id
            self.name = name
            self.kindRaw = kindRaw
            self.defaultRestSec = defaultRestSec
            self.defaultTargetReps = defaultTargetReps
            self.defaultTargetDurationSec = defaultTargetDurationSec
            self.defaultTargetDistanceM = defaultTargetDistanceM
        }
    }

    @Model
    public final class PlannedSet {
        @Attribute(.unique) public var id: UUID
        public var orderIndex: Int
        public var targetWeightKg: Double?
        public var targetReps: Int?
        public var targetDurationSec: Int?
        public var targetDistanceM: Double?
        public var restOverrideSec: Int?
        public var plannedExercise: PlannedExercise?

        public init(
            id: UUID = UUID(),
            orderIndex: Int,
            targetWeightKg: Double? = nil,
            targetReps: Int? = nil,
            targetDurationSec: Int? = nil,
            targetDistanceM: Double? = nil,
            restOverrideSec: Int? = nil
        ) {
            self.id = id
            self.orderIndex = orderIndex
            self.targetWeightKg = targetWeightKg
            self.targetReps = targetReps
            self.targetDurationSec = targetDurationSec
            self.targetDistanceM = targetDistanceM
            self.restOverrideSec = restOverrideSec
        }
    }

    @Model
    public final class PlannedExercise {
        @Attribute(.unique) public var id: UUID
        public var orderIndex: Int
        public var exercise: Exercise?
        public var template: WorkoutTemplate?

        @Relationship(deleteRule: .cascade, inverse: \PlannedSet.plannedExercise)
        public var sets: [PlannedSet] = []

        public init(
            id: UUID = UUID(),
            orderIndex: Int,
            exercise: Exercise? = nil
        ) {
            self.id = id
            self.orderIndex = orderIndex
            self.exercise = exercise
        }
    }

    @Model
    public final class WorkoutTemplate {
        @Attribute(.unique) public var id: UUID
        public var name: String
        public var createdAt: Date

        @Relationship(deleteRule: .cascade, inverse: \PlannedExercise.template)
        public var plannedExercises: [PlannedExercise] = []

        public init(
            id: UUID = UUID(),
            name: String = "",
            createdAt: Date = Date()
        ) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
        }
    }

    @Model
    public final class WorkoutSession {
        @Attribute(.unique) public var id: UUID
        public var startedAt: Date
        public var endedAt: Date?
        public var template: WorkoutTemplate?
        public var templateName: String
        public var healthKitWorkoutUUID: UUID?

        @Relationship(deleteRule: .cascade, inverse: \PerformedSet.session)
        public var performedSets: [PerformedSet] = []

        public init(
            id: UUID = UUID(),
            startedAt: Date = Date(),
            templateName: String = "",
            template: WorkoutTemplate? = nil
        ) {
            self.id = id
            self.startedAt = startedAt
            self.templateName = templateName
            self.template = template
        }
    }

    @Model
    public final class PerformedSet {
        @Attribute(.unique) public var id: UUID
        public var orderIndex: Int
        public var exerciseName: String
        public var exerciseIndex: Int
        public var setIndex: Int
        public var weightKg: Double?
        public var reps: Int?
        public var durationSec: Int?
        public var distanceM: Double?
        public var rpe: Int?
        public var completedAt: Date
        public var session: WorkoutSession?

        public init(
            id: UUID = UUID(),
            orderIndex: Int = 0,
            exerciseName: String = "",
            exerciseIndex: Int = 0,
            setIndex: Int = 0,
            weightKg: Double? = nil,
            reps: Int? = nil,
            durationSec: Int? = nil,
            distanceM: Double? = nil,
            rpe: Int? = nil,
            completedAt: Date = Date()
        ) {
            self.id = id
            self.orderIndex = orderIndex
            self.exerciseName = exerciseName
            self.exerciseIndex = exerciseIndex
            self.setIndex = setIndex
            self.weightKg = weightKg
            self.reps = reps
            self.durationSec = durationSec
            self.distanceM = distanceM
            self.rpe = rpe
            self.completedAt = completedAt
        }
    }
}
