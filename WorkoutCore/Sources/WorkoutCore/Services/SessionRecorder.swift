import Foundation

public struct CompletedSetEntry: Sendable {
    public let cursor: SetCursor
    public let exerciseName: String
    /// Lift Identity, carried from the plan so performed history matches on the
    /// exercise's stable id rather than its display name.
    public let exerciseID: UUID?
    public let weightKg: Double?
    public let reps: Int?
    public let durationSec: Int?
    public let distanceM: Double?
    public let rpe: Int?
    public let completedAt: Date

    /// The Target that was in effect for this set. Recorded alongside the actuals
    /// because the Coach moves a workout's targets over time — without it, a past
    /// Session's planned-vs-done would re-render against today's numbers.
    public let targetWeightKg: Double?
    public let targetReps: Int?
    public let targetDurationSec: Int?
    public let targetDistanceM: Double?

    public init(
        cursor: SetCursor,
        exerciseName: String,
        exerciseID: UUID? = nil,
        weightKg: Double?,
        reps: Int?,
        durationSec: Int?,
        distanceM: Double?,
        rpe: Int?,
        completedAt: Date,
        targetWeightKg: Double? = nil,
        targetReps: Int? = nil,
        targetDurationSec: Int? = nil,
        targetDistanceM: Double? = nil
    ) {
        self.cursor = cursor
        self.exerciseName = exerciseName
        self.exerciseID = exerciseID
        self.weightKg = weightKg
        self.reps = reps
        self.durationSec = durationSec
        self.distanceM = distanceM
        self.rpe = rpe
        self.completedAt = completedAt
        self.targetWeightKg = targetWeightKg
        self.targetReps = targetReps
        self.targetDurationSec = targetDurationSec
        self.targetDistanceM = targetDistanceM
    }
}

@MainActor
public protocol SessionRecorder: AnyObject {
    func sessionStarted(at: Date, plan: SessionPlan)
    func setCompleted(_ entry: CompletedSetEntry)
    func sessionEnded(at: Date)
}

@MainActor
public final class InMemorySessionRecorder: SessionRecorder {
    public private(set) var startedAt: Date?
    public private(set) var endedAt: Date?
    public private(set) var entries: [CompletedSetEntry] = []
    public private(set) var plan: SessionPlan?

    public init() {}

    public func sessionStarted(at: Date, plan: SessionPlan) {
        self.startedAt = at
        self.plan = plan
    }

    public func setCompleted(_ entry: CompletedSetEntry) {
        entries.append(entry)
    }

    public func sessionEnded(at: Date) {
        self.endedAt = at
    }
}
