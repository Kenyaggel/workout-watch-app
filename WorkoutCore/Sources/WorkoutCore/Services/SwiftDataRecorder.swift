import Foundation
import SwiftData

@MainActor
public final class SwiftDataRecorder: SessionRecorder {
    private let context: ModelContext
    private var session: WorkoutSession?
    private var isRecording = false
    private var orderCounter = 0

    public init(context: ModelContext) {
        self.context = context
    }

    public var currentSession: WorkoutSession? { session }

    public func sessionStarted(at: Date, plan: SessionPlan) {
        let new = WorkoutSession(
            startedAt: at,
            templateName: plan.templateName,
            template: template(matching: plan.templateID)
        )
        context.insert(new)
        self.session = new
        self.isRecording = true
        self.orderCounter = 0
        try? context.save()
    }

    public func setCompleted(_ entry: CompletedSetEntry) {
        guard isRecording, let session else { return }
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
        isRecording = false
        try? context.save()
    }

    private func template(matching id: UUID?) -> WorkoutTemplate? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<WorkoutTemplate>(
            predicate: #Predicate { $0.id == id }
        )
        return (try? context.fetch(descriptor))?.first
    }
}
