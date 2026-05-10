import Foundation
import SwiftData

@MainActor
public final class SwiftDataRecorder: SessionRecorder {
    private let context: ModelContext
    private var session: WorkoutSession?
    private var orderCounter = 0

    public init(context: ModelContext) {
        self.context = context
    }

    public var currentSession: WorkoutSession? { session }

    public func sessionStarted(at: Date, plan: SessionPlan) {
        let new = WorkoutSession(startedAt: at, templateName: plan.templateName)
        context.insert(new)
        self.session = new
        self.orderCounter = 0
        try? context.save()
    }

    public func setCompleted(_ entry: CompletedSetEntry) {
        guard let session else { return }
        let performed = PerformedSet(
            orderIndex: orderCounter,
            exerciseName: entry.exerciseName,
            exerciseIndex: entry.cursor.exerciseIndex,
            setIndex: entry.cursor.setIndex,
            weightKg: entry.weightKg,
            reps: entry.reps,
            durationSec: entry.durationSec,
            distanceM: entry.distanceM,
            rpe: entry.rpe,
            completedAt: entry.completedAt
        )
        performed.session = session
        context.insert(performed)
        orderCounter += 1
        try? context.save()
    }

    public func sessionEnded(at: Date) {
        session?.endedAt = at
        try? context.save()
        session = nil
    }
}
