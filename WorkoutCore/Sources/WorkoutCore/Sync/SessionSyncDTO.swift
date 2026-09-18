import Foundation
import SwiftData

public struct SessionSyncSnapshot: Codable, Equatable, Sendable {
    public var session: WorkoutSessionSyncDTO

    public init(session: WorkoutSessionSyncDTO) {
        self.session = session
    }

    public init(session: WorkoutSession, templateID: UUID? = nil) {
        self.init(session: WorkoutSessionSyncDTO(session: session, templateID: templateID))
    }
}

public struct WorkoutSessionSyncDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var templateID: UUID?
    public var templateName: String
    public var healthKitWorkoutUUID: UUID?
    public var performedSets: [PerformedSetSyncDTO]

    public init(
        id: UUID,
        startedAt: Date,
        endedAt: Date?,
        templateID: UUID?,
        templateName: String,
        healthKitWorkoutUUID: UUID?,
        performedSets: [PerformedSetSyncDTO]
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.templateID = templateID
        self.templateName = templateName
        self.healthKitWorkoutUUID = healthKitWorkoutUUID
        self.performedSets = performedSets.sorted { $0.orderIndex < $1.orderIndex }
    }

    public init(session: WorkoutSession, templateID: UUID? = nil) {
        self.init(
            id: session.id,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            templateID: templateID ?? session.template?.id,
            templateName: session.templateName,
            healthKitWorkoutUUID: session.healthKitWorkoutUUID,
            performedSets: session.orderedPerformedSets.map(PerformedSetSyncDTO.init(performedSet:))
        )
    }
}

/// Every field added after the first shipped version is `Optional`, so the synthesized
/// `Codable` conformance decodes them with `decodeIfPresent`. A watch still running the
/// previous build therefore syncs cleanly to a phone on this one — the new keys simply
/// arrive nil.
public struct PerformedSetSyncDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var orderIndex: Int
    public var exerciseName: String
    /// Lift Identity. Nil from a watch that predates V3.
    public var exerciseID: UUID?
    public var exerciseIndex: Int
    public var setIndex: Int
    public var weightKg: Double?
    public var reps: Int?
    public var durationSec: Int?
    public var distanceM: Double?
    public var rpe: Int?
    public var completedAt: Date

    /// How many sets the Slot planned when this set was run.
    public var plannedSetCount: Int?

    /// The Target in effect on the watch when this set was performed.
    public var targetWeightKg: Double?
    public var targetReps: Int?
    public var targetDurationSec: Int?
    public var targetDistanceM: Double?

    public init(
        id: UUID,
        orderIndex: Int,
        exerciseName: String,
        exerciseID: UUID? = nil,
        exerciseIndex: Int,
        setIndex: Int,
        weightKg: Double?,
        reps: Int?,
        durationSec: Int?,
        distanceM: Double?,
        rpe: Int?,
        completedAt: Date,
        plannedSetCount: Int? = nil,
        targetWeightKg: Double? = nil,
        targetReps: Int? = nil,
        targetDurationSec: Int? = nil,
        targetDistanceM: Double? = nil
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.exerciseName = exerciseName
        self.exerciseID = exerciseID
        self.exerciseIndex = exerciseIndex
        self.setIndex = setIndex
        self.weightKg = weightKg
        self.reps = reps
        self.durationSec = durationSec
        self.distanceM = distanceM
        self.rpe = rpe
        self.completedAt = completedAt
        self.plannedSetCount = plannedSetCount
        self.targetWeightKg = targetWeightKg
        self.targetReps = targetReps
        self.targetDurationSec = targetDurationSec
        self.targetDistanceM = targetDistanceM
    }

    public init(performedSet: PerformedSet) {
        self.init(
            id: performedSet.id,
            orderIndex: performedSet.orderIndex,
            exerciseName: performedSet.exerciseName,
            exerciseID: performedSet.exerciseID,
            exerciseIndex: performedSet.exerciseIndex,
            setIndex: performedSet.setIndex,
            weightKg: performedSet.weightKg,
            reps: performedSet.reps,
            durationSec: performedSet.durationSec,
            distanceM: performedSet.distanceM,
            rpe: performedSet.rpe,
            completedAt: performedSet.completedAt,
            plannedSetCount: performedSet.plannedSetCount,
            targetWeightKg: performedSet.targetWeightKg,
            targetReps: performedSet.targetReps,
            targetDurationSec: performedSet.targetDurationSec,
            targetDistanceM: performedSet.targetDistanceM
        )
    }
}
