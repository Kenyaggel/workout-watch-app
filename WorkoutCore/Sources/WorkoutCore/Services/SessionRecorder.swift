import Foundation

public struct CompletedSetEntry: Sendable {
    public let cursor: SetCursor
    public let exerciseName: String
    public let weightKg: Double?
    public let reps: Int?
    public let durationSec: Int?
    public let distanceM: Double?
    public let rpe: Int?
    public let completedAt: Date

    public init(
        cursor: SetCursor,
        exerciseName: String,
        weightKg: Double?,
        reps: Int?,
        durationSec: Int?,
        distanceM: Double?,
        rpe: Int?,
        completedAt: Date
    ) {
        self.cursor = cursor
        self.exerciseName = exerciseName
        self.weightKg = weightKg
        self.reps = reps
        self.durationSec = durationSec
        self.distanceM = distanceM
        self.rpe = rpe
        self.completedAt = completedAt
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
