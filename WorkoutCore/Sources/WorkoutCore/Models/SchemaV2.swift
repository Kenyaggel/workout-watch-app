import Foundation
import SwiftData

public enum WorkoutSchemaV2: VersionedSchema {
    public static var versionIdentifier = Schema.Version(2, 0, 0)

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

        public var kind: ExerciseKind {
            get { ExerciseKind(rawValue: kindRaw) ?? .reps }
            set { kindRaw = newValue.rawValue }
        }

        public init(
            id: UUID = UUID(),
            name: String,
            kind: ExerciseKind,
            defaultRestSec: Int,
            defaultTargetReps: Int? = nil,
            defaultTargetDurationSec: Int? = nil,
            defaultTargetDistanceM: Double? = nil
        ) {
            self.id = id
            self.name = name
            self.kindRaw = kind.rawValue
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
        public var plannedExercise: PlannedExercise?

        public init(
            id: UUID = UUID(),
            orderIndex: Int,
            targetWeightKg: Double? = nil,
            targetReps: Int? = nil,
            targetDurationSec: Int? = nil,
            targetDistanceM: Double? = nil
        ) {
            self.id = id
            self.orderIndex = orderIndex
            self.targetWeightKg = targetWeightKg
            self.targetReps = targetReps
            self.targetDurationSec = targetDurationSec
            self.targetDistanceM = targetDistanceM
        }
    }

    @Model
    public final class PlannedExercise {
        @Attribute(.unique) public var id: UUID
        public var orderIndex: Int
        public var restSec: Int?
        public var exercise: Exercise?
        public var template: WorkoutTemplate?

        @Relationship(deleteRule: .cascade, inverse: \PlannedSet.plannedExercise)
        public var sets: [PlannedSet] = []

        /// Pass `restSec: nil` to mean "use the exercise's default rest" — not
        /// "no rest". The init normalizes nil to `exercise?.defaultRestSec ?? 90`
        /// so newly-created rows always carry a concrete value; only rows that
        /// predate the V1→V2 migration can hold nil at rest. Read rest through
        /// `resolvedRestSec` to paper over both cases.
        public init(
            id: UUID = UUID(),
            orderIndex: Int,
            exercise: Exercise? = nil,
            restSec: Int? = nil
        ) {
            self.id = id
            self.orderIndex = orderIndex
            self.restSec = restSec ?? exercise?.defaultRestSec ?? 90
            self.exercise = exercise
        }

        public var orderedSets: [PlannedSet] {
            sets.sorted { $0.orderIndex < $1.orderIndex }
        }

        public var resolvedRestSec: Int {
            restSec ?? exercise?.defaultRestSec ?? 90
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
            name: String,
            createdAt: Date = Date()
        ) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
        }

        public var orderedExercises: [PlannedExercise] {
            plannedExercises.sorted { $0.orderIndex < $1.orderIndex }
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
            startedAt: Date,
            templateName: String,
            template: WorkoutTemplate? = nil
        ) {
            self.id = id
            self.startedAt = startedAt
            self.templateName = templateName
            self.template = template
        }

        public var isFinished: Bool { endedAt != nil }

        public var orderedPerformedSets: [PerformedSet] {
            performedSets.sorted { $0.orderIndex < $1.orderIndex }
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
            orderIndex: Int,
            exerciseName: String,
            exerciseIndex: Int,
            setIndex: Int,
            weightKg: Double? = nil,
            reps: Int? = nil,
            durationSec: Int? = nil,
            distanceM: Double? = nil,
            rpe: Int? = nil,
            completedAt: Date
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

// MARK: - Module-level typealiases (current = V2)

public typealias Exercise = WorkoutSchemaV2.Exercise
public typealias PlannedSet = WorkoutSchemaV2.PlannedSet
public typealias PlannedExercise = WorkoutSchemaV2.PlannedExercise
public typealias WorkoutTemplate = WorkoutSchemaV2.WorkoutTemplate
public typealias WorkoutSession = WorkoutSchemaV2.WorkoutSession
public typealias PerformedSet = WorkoutSchemaV2.PerformedSet
