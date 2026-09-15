import Foundation
import SwiftData

/// A Proposed Target together with enough of its Slot to render and apply it.
public struct CoachProposal: Identifiable, Sendable {
    public var output: CoachOutput
    public var slotID: UUID
    public var workoutID: UUID
    public var workoutName: String
    public var exerciseName: String
    public var currentTargets: [TargetSnapshot]

    /// Content identity, so SwiftUI keeps a row stable across recomputation and a changed
    /// proposal reads as a different row.
    public var id: String { output.fingerprint }

    public var isPendingReview: Bool { output.applyClass == .pendingReview }

    /// What the slot says today, on the progression axis.
    public var currentSummary: String {
        Coach.summary(currentTargets, output.dimension)
    }

    /// What the Coach proposes instead.
    public var proposedSummary: String {
        Coach.summary(output.proposedTargets, output.dimension)
    }

    /// False when the Coach is reporting a situation rather than proposing numbers — it has
    /// stalled the lifter out, hit a ceiling, or seen a slot cut short repeatedly. There is
    /// nothing to write; the lifter is only being told.
    public var changesTargets: Bool {
        output.proposedTargets != currentTargets
    }

    /// Nil when the proposal leaves the numbers where they are.
    public var changeSummary: String? {
        guard currentSummary != proposedSummary else { return nil }
        return "\(currentSummary) → \(proposedSummary)"
    }

    public var headline: String {
        switch output.outcome {
        case .increase: return "Step up"
        case .deload: return "Back off"
        case .seedFromE1RM: return "Starting weight"
        case .holdAtFloor: return "Stuck at the bottom"
        case .holdAdvisoryCeiling: return "Time for a harder variation"
        case .holdChronicPartialSession: return "Cut short repeatedly"
        case .holdFirstStall: return "Repeat"
        case .holdRPEVeto: return "Holding"
        case .holdLayoff: return "Back after a break"
        case .holdNoComparableHistory, .insufficientData, .noTargets: return "Nothing to change"
        }
    }
}

/// The thin SwiftData shell around the pure `Coach`.
///
/// Live proposals are **recomputed**, never stored. What persists is the lifter's decision.
/// Everything that could be a rule lives in `Coach`; this file only reads the store, hands
/// value types over, and writes back what comes out.
@MainActor
public enum CoachStore {

    /// How far back sessions are read. Well past any window the rules themselves use.
    public static let historyWindowDays = 365

    // MARK: - Reading

    public static func proposals(
        in context: ModelContext,
        asOf: Date,
        config: CoachConfig = CoachConfig()
    ) throws -> [CoachProposal] {
        let sessions = try sessionSnapshots(in: context, asOf: asOf)
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        let decisions = try context.fetch(FetchDescriptor<CoachDecision>())

        // A decision is keyed by *which* proposal and *on what evidence*, so stalling again
        // resurfaces a deload the lifter waved away last time.
        //
        // Accepting suppresses it too, not just dismissing. Most proposals move the targets,
        // which changes the fingerprint and retires them on its own — but the ones that
        // change nothing and only ask to be acknowledged (`.holdAtFloor`,
        // `.holdAdvisoryCeiling`, `.holdChronicPartialSession`) re-derive identically
        // forever, so acting on them has to be what clears them.
        let decided = Swift.Set(
            decisions.map { decisionKey(fingerprint: $0.fingerprint, sourceSessionID: $0.sourceSessionID) }
        )

        var result: [CoachProposal] = []
        for template in templates {
            for slot in template.orderedExercises {
                guard let snapshot = slotSnapshot(for: slot, in: template) else { continue }
                let output = Coach.propose(
                    CoachInput(slot: snapshot, sessions: sessions, asOf: asOf, config: config)
                )
                guard output.applyClass != .noOp || output.outcome == .holdFirstStall else { continue }
                let key = decisionKey(fingerprint: output.fingerprint, sourceSessionID: output.sourceSessionID)
                guard !decided.contains(key) else { continue }
                result.append(CoachProposal(
                    output: output,
                    slotID: snapshot.slotID,
                    workoutID: snapshot.workoutID,
                    workoutName: template.name,
                    exerciseName: snapshot.exerciseName,
                    currentTargets: snapshot.targets
                ))
            }
        }
        // Stable order: the ones that need a human first, then by workout and position.
        return result.sorted { lhs, rhs in
            if lhs.isPendingReview != rhs.isPendingReview { return lhs.isPendingReview }
            if lhs.workoutName != rhs.workoutName { return lhs.workoutName < rhs.workoutName }
            return lhs.exerciseName < rhs.exerciseName
        }
    }

    public static func pendingProposals(
        in context: ModelContext,
        asOf: Date,
        config: CoachConfig = CoachConfig()
    ) throws -> [CoachProposal] {
        try proposals(in: context, asOf: asOf, config: config).filter(\.isPendingReview)
    }

    // MARK: - Writing

    /// Runs the Coach for every Slot in a freshly-received Session's workout: records what
    /// the Coach had proposed *before* that session as the deviation signal, then applies
    /// the single-step moves and leaves everything else for review.
    ///
    /// This is phone-side by design. Writing targets is only safe because the phone is the
    /// writer — template sync is phone → watch and the watch replaces its local copy, so a
    /// watch-side write would be clobbered.
    @discardableResult
    public static func ingest(
        session: WorkoutSession,
        in context: ModelContext,
        asOf: Date,
        config: CoachConfig = CoachConfig()
    ) throws -> [CoachProposal] {
        guard let template = session.template else { return [] }

        try stampCoachSuggestions(for: session, template: template, in: context, config: config)

        let sessions = try sessionSnapshots(in: context, asOf: asOf)
        var applied: [CoachProposal] = []

        for slot in template.orderedExercises {
            guard let snapshot = slotSnapshot(for: slot, in: template) else { continue }
            let output = Coach.propose(
                CoachInput(slot: snapshot, sessions: sessions, asOf: asOf, config: config)
            )
            guard output.applyClass == .automatic else { continue }
            apply(output, to: slot)
            record(output, slot: slot, workoutName: template.name, accepted: true, at: asOf, in: context)
            applied.append(CoachProposal(
                output: output,
                slotID: snapshot.slotID,
                workoutID: snapshot.workoutID,
                workoutName: template.name,
                exerciseName: snapshot.exerciseName,
                currentTargets: snapshot.targets
            ))
        }

        try context.save()
        return applied
    }

    public static func accept(
        _ proposal: CoachProposal,
        in context: ModelContext,
        at date: Date
    ) throws {
        guard let slot = plannedExercise(proposal.slotID, in: context) else { return }
        apply(proposal.output, to: slot)
        record(
            proposal.output, slot: slot, workoutName: proposal.workoutName,
            accepted: true, at: date, in: context
        )
        try context.save()
    }

    public static func dismiss(
        _ proposal: CoachProposal,
        in context: ModelContext,
        at date: Date
    ) throws {
        let slot = plannedExercise(proposal.slotID, in: context)
        record(
            proposal.output, slot: slot, workoutName: proposal.workoutName,
            accepted: false, at: date, in: context,
            fallbackExerciseName: proposal.exerciseName, fallbackWorkoutID: proposal.workoutID
        )
        try context.save()
    }

    // MARK: - Internals

    static func decisionKey(fingerprint: String, sourceSessionID: UUID?) -> String {
        "\(fingerprint)@\(sourceSessionID?.uuidString ?? "-")"
    }

    /// Pairs by position, exactly as the rules did: `CoachOutput.proposedTargets` is always a
    /// complete vector in the slot's own set order, so there is nothing to decide here.
    static func apply(_ output: CoachOutput, to slot: PlannedExercise) {
        let sets = slot.orderedSets
        for (index, target) in output.proposedTargets.enumerated() {
            guard index < sets.count else { break }
            sets[index].targetWeightKg = target.weightKg
            sets[index].targetReps = target.reps
            sets[index].targetDurationSec = target.durationSec
            sets[index].targetDistanceM = target.distanceM
        }
    }

    static func record(
        _ output: CoachOutput,
        slot: PlannedExercise?,
        workoutName: String,
        accepted: Bool,
        at date: Date,
        in context: ModelContext,
        fallbackExerciseName: String = "",
        fallbackWorkoutID: UUID? = nil
    ) {
        context.insert(CoachDecision(
            slotID: output.slotID,
            workoutID: slot?.template?.id ?? fallbackWorkoutID,
            exerciseID: slot?.exercise?.id,
            workoutName: workoutName,
            exerciseName: slot?.exercise?.name ?? fallbackExerciseName,
            fingerprint: output.fingerprint,
            sourceSessionID: output.sourceSessionID,
            outcomeRaw: output.outcome.rawValue,
            dimensionRaw: output.dimension.rawValue,
            delta: output.delta,
            wasAccepted: accepted,
            decidedAt: date
        ))
    }

    /// Records, on each of the session's Performed Sets, what the Coach had proposed for
    /// that slot *going into* the session. Comparing it with what was actually run is the
    /// only way to tell whether the coach is any good.
    ///
    /// In practice this only ever stamps proposals that were **pending**, and that is
    /// correct rather than a gap. An applied proposal becomes the workout's target, so
    /// `target*` already records it and a copy here would say nothing new — and because
    /// applying moves the target, the proposal is no longer recomputable anyway. A pending
    /// proposal left the targets alone, so it recomputes exactly, and it is precisely the
    /// case where the lifter trained through a number the coach disagreed with.
    static func stampCoachSuggestions(
        for session: WorkoutSession,
        template: WorkoutTemplate,
        in context: ModelContext,
        config: CoachConfig
    ) throws {
        // One second before the session so the session itself cannot inform the proposal it
        // is about to be measured against.
        let asOf = session.startedAt.addingTimeInterval(-1)
        let history = try sessionSnapshots(in: context, asOf: asOf)
        let sessionSnapshot = snapshot(of: session)
        let performedByID = Dictionary(
            session.performedSets.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for slot in template.orderedExercises {
            guard let snapshot = slotSnapshot(for: slot, in: template) else { continue }
            let standing = Coach.propose(
                CoachInput(slot: snapshot, sessions: history, asOf: asOf, config: config)
            )
            guard standing.applyClass != .noOp else { continue }

            let matched = Coach.matchedSets(in: sessionSnapshot, slot: snapshot)
            for (index, performed) in matched.enumerated() {
                guard index < standing.proposedTargets.count,
                      let row = performedByID[performed.id] else { continue }
                let target = standing.proposedTargets[index]
                row.suggestedWeightKg = target.weightKg
                row.suggestedReps = target.reps
                row.suggestedDurationSec = target.durationSec
                row.suggestedDistanceM = target.distanceM
            }
        }
    }

    static func plannedExercise(_ id: UUID, in context: ModelContext) -> PlannedExercise? {
        let descriptor = FetchDescriptor<PlannedExercise>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }

    static func slotSnapshot(for slot: PlannedExercise, in template: WorkoutTemplate) -> SlotSnapshot? {
        let targets = slot.orderedSets.map {
            TargetSnapshot(
                weightKg: $0.targetWeightKg,
                reps: $0.targetReps,
                durationSec: $0.targetDurationSec,
                distanceM: $0.targetDistanceM
            )
        }
        let exercise = slot.exercise
        let peers = template.orderedExercises
            .filter { peer in
                guard let id = exercise?.id else { return peer.id == slot.id }
                return peer.exercise?.id == id
            }
            .map(\.orderIndex)

        return SlotSnapshot(
            slotID: slot.id,
            workoutID: template.id,
            workoutName: template.name,
            exerciseID: exercise?.id,
            exerciseName: exercise?.name ?? "",
            kind: exercise?.kind,
            progressionStep: exercise?.progressionStep,
            targets: targets,
            orderIndex: slot.orderIndex,
            peerSlotOrderIndexes: peers
        )
    }

    static func sessionSnapshots(in context: ModelContext, asOf: Date) throws -> [SessionSnapshot] {
        guard let cutoff = Calendar(identifier: .gregorian)
            .date(byAdding: .day, value: -historyWindowDays, to: asOf)
        else { return [] }

        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.startedAt >= cutoff && $0.startedAt <= asOf }
        )
        return try context.fetch(descriptor).map(snapshot(of:))
    }

    static func snapshot(of session: WorkoutSession) -> SessionSnapshot {
        SessionSnapshot(
            id: session.id,
            workoutID: session.template?.id,
            workoutName: session.templateName,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            sets: session.performedSets.map { set in
                PerformedSnapshot(
                    id: set.id,
                    exerciseID: set.exerciseID,
                    exerciseName: set.exerciseName,
                    exerciseIndex: set.exerciseIndex,
                    setIndex: set.setIndex,
                    orderIndex: set.orderIndex,
                    weightKg: set.weightKg,
                    reps: set.reps,
                    durationSec: set.durationSec,
                    distanceM: set.distanceM,
                    rpe: set.rpe,
                    completedAt: set.completedAt,
                    target: TargetSnapshot(
                        weightKg: set.targetWeightKg,
                        reps: set.targetReps,
                        durationSec: set.targetDurationSec,
                        distanceM: set.targetDistanceM
                    ).isEmpty ? nil : TargetSnapshot(
                        weightKg: set.targetWeightKg,
                        reps: set.targetReps,
                        durationSec: set.targetDurationSec,
                        distanceM: set.targetDistanceM
                    ),
                    plannedSetCount: set.plannedSetCount
                )
            }
        )
    }
}
