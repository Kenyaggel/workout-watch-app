import Foundation
import Observation

public enum SessionPhase: Equatable, Sendable {
    case idle
    case inSet(cursor: SetCursor, startedAt: Date)
    case rest(endsAt: Date, justCompleted: SetCursor, nextCursor: SetCursor)
    case prep(startedAt: Date, nextCursor: SetCursor)
    case complete(endedAt: Date)

    public var cursor: SetCursor? {
        switch self {
        case .inSet(let c, _): return c
        case .rest(_, _, let next): return next
        case .prep(_, let next): return next
        case .idle, .complete: return nil
        }
    }
}

@MainActor
@Observable
public final class SessionEngine {
    public private(set) var plan: SessionPlan
    public private(set) var phase: SessionPhase = .idle

    private let nowProvider: @Sendable () -> Date
    private let haptics: Haptics
    private weak var recorder: (any SessionRecorder)?
    private var hapticTask: Task<Void, Never>?

    public init(
        plan: SessionPlan,
        recorder: (any SessionRecorder)? = nil,
        haptics: Haptics = NoopHaptics(),
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.plan = plan
        self.recorder = recorder
        self.haptics = haptics
        self.nowProvider = nowProvider
    }

    // (No deinit cleanup — the haptic task uses `weak self` and short-circuits
    // when self is deallocated, so leaving it to natural cancellation is safe.)

    // MARK: - Transitions

    public func start() {
        guard case .idle = phase else { return }
        guard let first = plan.firstCursor else {
            phase = .complete(endedAt: nowProvider())
            return
        }
        let now = nowProvider()
        recorder?.sessionStarted(at: now, plan: plan)
        enterInSet(cursor: first, at: now)
    }

    public func completeSet(
        weightKg: Double? = nil,
        reps: Int? = nil,
        durationSec: Int? = nil,
        distanceM: Double? = nil,
        rpe: Int? = nil
    ) {
        guard case let .inSet(cursor, _) = phase else { return }
        guard let exercise = plan.exercise(at: cursor) else { return }
        let now = nowProvider()

        recorder?.setCompleted(.init(
            cursor: cursor,
            exerciseName: exercise.name,
            weightKg: weightKg,
            reps: reps,
            durationSec: durationSec,
            distanceM: distanceM,
            rpe: rpe,
            completedAt: now
        ))

        guard let succ = plan.successor(of: cursor) else {
            finish(at: now)
            return
        }

        if succ.crossesExercise {
            enterPrep(nextCursor: succ.next, at: now)
        } else {
            let restSec = plan.set(at: cursor)?.restSec ?? 0
            let endsAt = now.addingTimeInterval(TimeInterval(restSec))
            enterRest(endsAt: endsAt, justCompleted: cursor, nextCursor: succ.next)
        }
    }

    public func skipRest() {
        guard case let .rest(_, _, next) = phase else { return }
        enterInSet(cursor: next, at: nowProvider())
    }

    /// Called when the wall-clock rest deadline has been reached.
    /// Idempotent — safe to call from a TimelineView re-render.
    public func restAutoExpired() {
        guard case let .rest(endsAt, _, next) = phase else { return }
        guard nowProvider() >= endsAt else { return }
        enterInSet(cursor: next, at: nowProvider())
    }

    public func startNextExercise() {
        guard case let .prep(_, next) = phase else { return }
        enterInSet(cursor: next, at: nowProvider())
    }

    /// Early termination of the workout (user tapped End).
    public func endWorkout() {
        finish(at: nowProvider())
    }

    // MARK: - Phase entry helpers

    private func enterInSet(cursor: SetCursor, at now: Date) {
        cancelHaptics()
        phase = .inSet(cursor: cursor, startedAt: now)
        haptics.play(.setStart)
    }

    private func enterRest(endsAt: Date, justCompleted: SetCursor, nextCursor: SetCursor) {
        cancelHaptics()
        phase = .rest(endsAt: endsAt, justCompleted: justCompleted, nextCursor: nextCursor)
        scheduleRestHaptics(endsAt: endsAt)
    }

    private func enterPrep(nextCursor: SetCursor, at now: Date) {
        cancelHaptics()
        phase = .prep(startedAt: now, nextCursor: nextCursor)
    }

    private func finish(at now: Date) {
        cancelHaptics()
        phase = .complete(endedAt: now)
        haptics.play(.workoutComplete)
        recorder?.sessionEnded(at: now)
    }

    // MARK: - Haptic scheduling

    private func scheduleRestHaptics(endsAt: Date) {
        let now = nowProvider()
        let warningAt = endsAt.addingTimeInterval(-10)
        let h = haptics

        hapticTask = Task { @MainActor [weak self] in
            if warningAt > now {
                let warningDelay = warningAt.timeIntervalSince(now)
                try? await Task.sleep(nanoseconds: UInt64(max(warningDelay, 0) * 1_000_000_000))
                guard !Task.isCancelled, self != nil else { return }
                h.play(.restWarning)
            }
            let endDelay = endsAt.timeIntervalSince(self?.nowProvider() ?? now)
            if endDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(endDelay * 1_000_000_000))
            }
            guard !Task.isCancelled, self != nil else { return }
            h.play(.restEnd)
        }
    }

    private func cancelHaptics() {
        hapticTask?.cancel()
        hapticTask = nil
    }

    // MARK: - Conveniences for views

    public var isComplete: Bool {
        if case .complete = phase { return true }
        return false
    }

    public var totalSets: Int {
        plan.exercises.reduce(0) { $0 + $1.sets.count }
    }

    public func setNumber(of cursor: SetCursor) -> Int {
        var n = 0
        for (i, ex) in plan.exercises.enumerated() {
            if i < cursor.exerciseIndex {
                n += ex.sets.count
            } else {
                return n + cursor.setIndex + 1
            }
        }
        return n
    }
}
