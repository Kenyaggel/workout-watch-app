import Foundation

// The half of the Coach that produces numbers. Split out so the rules that *decide* stay
// readable next to the arithmetic that *executes*.
extension Coach {

    // MARK: - Increase

    static func proposeIncrease(
        slot: SlotSnapshot,
        dimension: ProgressionDimension,
        step: Double,
        evaluated: ScopedSession,
        config: CoachConfig,
        flags: inout [CoachFlag],
        evidence: CoachEvidence,
        sourceSessionID: UUID?
    ) -> CoachOutput {
        // Baseline reconciliation, load only, on a met session: if the lifter loaded 70
        // against a programmed 60 and completed the work, the program *is* at 70. Anchoring
        // on the plan instead would fight them every single session.
        var baseline = slot.targets
        var reconciled = false
        if dimension == .load {
            for (index, set) in evaluated.sets.enumerated() where index < baseline.count {
                guard let performed = set.weightKg, performed.isFinite else { continue }
                let planned = baseline[index].weightKg ?? 0
                if performed > planned + config.epsilon {
                    baseline[index].weightKg = CoachRounding.canonical(performed)
                    reconciled = true
                }
            }
        }
        if reconciled { flags.append(.baselineExceededTarget) }

        if slot.targets.contains(where: { $0.value(on: dimension) == nil }) {
            // A half-specified slot is an authoring bug, not something to paper over.
            flags.append(.missingTargetOnDimension)
        }

        let proposed = baseline.map { target -> TargetSnapshot in
            guard let current = target.value(on: dimension), current.isFinite, current > 0 else {
                // Never add a step to "no weight", and never turn a corrupt or negative
                // stored target into a slightly less corrupt one.
                return target
            }
            return target.setting(dimension, to: current + step)
        }

        if let ceiling = dimension.advisoryCeiling,
           proposed.contains(where: { ($0.value(on: dimension) ?? 0) > ceiling }) {
            return output(
                slot: slot, dimension: dimension, outcome: .holdAdvisoryCeiling,
                applyClass: .pendingReview, delta: 0, targets: slot.targets,
                reason: "This is past \(Self.format(ceiling, dimension)) a set. More \(dimension.displayName.lowercased()) is no longer the point — a harder variation or added load is.",
                flags: flags, evidence: evidence, sourceSessionID: sourceSessionID
            )
        }

        let setCountChanged = evaluated.sets.compactMap(\.plannedSetCount).first.map { $0 != slot.targets.count } ?? false
        if setCountChanged { flags.append(.setCountChanged) }

        return finish(
            slot: slot, dimension: dimension, outcome: .increase,
            preferredClass: .automatic, delta: step, proposed: proposed,
            reason: "Every target met last session. Up one step to \(Self.summary(proposed, dimension)).",
            flags: flags, evidence: evidence, sourceSessionID: sourceSessionID, config: config, step: step
        )
    }

    // MARK: - Deload

    static func proposeDeload(
        slot: SlotSnapshot,
        dimension: ProgressionDimension,
        step: Double,
        config: CoachConfig,
        flags: inout [CoachFlag],
        evidence: CoachEvidence,
        sourceSessionID: UUID?,
        escalatedByRPE: Bool
    ) -> CoachOutput {
        // Ten percent of the slot's authored target, not of what was last performed: a
        // mis-load compounds otherwise, deloading from the mistake rather than the plan.
        guard let anchor = slot.targets.compactMap({ $0.value(on: dimension) }).first(where: { $0.isFinite && $0 > 0 }) else {
            return output(
                slot: slot, dimension: dimension, outcome: .noTargets, applyClass: .noOp,
                delta: 0, targets: slot.targets,
                reason: "Nothing to deload — no set carries a \(dimension.displayName.lowercased()) target.",
                flags: flags, evidence: evidence, sourceSessionID: sourceSessionID
            )
        }

        let steps = CoachRounding.stepsNearest(anchor * config.deloadFraction, step: step)
        let delta = -CoachRounding.canonical(Double(steps) * step)

        // Below three rungs the ladder is too coarse to say anything useful, and the real
        // answer — change the exercise, change the rep range, sleep — is outside the Coach's
        // vocabulary. It escalates to a human rather than shrinking a number.
        guard CoachRounding.canonical(anchor + delta) > 2 * step else {
            return output(
                slot: slot, dimension: dimension, outcome: .holdAtFloor, applyClass: .pendingReview,
                delta: 0, targets: slot.targets,
                reason: "Stalled twice at \(Self.format(anchor, dimension)), and that is already close to the bottom of what this step size can express. Worth changing the exercise or the rep range rather than the number.",
                flags: flags, evidence: evidence, sourceSessionID: sourceSessionID
            )
        }

        let proposed = slot.targets.map { target -> TargetSnapshot in
            guard let current = target.value(on: dimension), current.isFinite, current > 0 else {
                return target
            }
            // Per-set clamp so a shallow backoff set can never reach zero or go negative.
            return target.setting(dimension, to: Swift.max(CoachRounding.canonical(current + delta), step))
        }

        let why = escalatedByRPE
            ? "Missed reps at RPE 10."
            : "Stalled \(evidence.consecutiveStalls) sessions running."
        return finish(
            slot: slot, dimension: dimension, outcome: .deload,
            preferredClass: .pendingReview, delta: delta, proposed: proposed,
            reason: "\(why) Back down to \(Self.summary(proposed, dimension)) and build again.",
            flags: flags, evidence: evidence, sourceSessionID: sourceSessionID, config: config, step: step
        )
    }

    // MARK: - No history

    static func proposeWithoutHistory(
        input: CoachInput,
        dimension: ProgressionDimension,
        step: Double,
        flags: inout [CoachFlag],
        evidence: inout CoachEvidence,
        sawSkippedSession: Bool
    ) -> CoachOutput {
        let slot = input.slot
        let config = input.config

        if sawSkippedSession {
            return output(
                slot: slot, dimension: dimension, outcome: .holdNoComparableHistory, applyClass: .noOp,
                delta: 0, targets: slot.targets,
                reason: "Last time this slot was cut short with nothing missed, which says nothing about whether the load is right. Holding.",
                flags: flags, evidence: evidence, sourceSessionID: nil
            )
        }

        // The seed exists to fill a blank, never to overwrite a human's authored number.
        let hasAuthoredWeight = slot.targets.contains { ($0.weightKg ?? 0) > 0 }
        guard slot.kind == .reps, !hasAuthoredWeight,
              let e1rm = bestE1RM(input: input)
        else {
            // "Never trained here" and "trained here, but not against these numbers" are
            // different situations and the lifter is told which one they are in. The second
            // only arises once sessions exist for the slot and the walk rejected them all.
            let sawIncomparableHistory = evidence.comparableSessionCount > 0
            return output(
                slot: slot, dimension: dimension,
                outcome: sawIncomparableHistory ? .holdNoComparableHistory : .insufficientData,
                applyClass: .noOp, delta: 0, targets: slot.targets,
                reason: sawIncomparableHistory
                    ? "Nothing comparable to go on — the targets have changed since this slot was last run. Run it once as written."
                    : "No history for this slot yet. Log one session and the coach will take it from there.",
                flags: flags, evidence: evidence, sourceSessionID: nil
            )
        }

        evidence.sourceE1RM = e1rm
        let loadStep = resolveStep(slot.storedStep(for: .load), dimension: .load, config: config, flags: &flags)
        evidence.resolvedStep = loadStep

        // Per-set inverse Epley against each set's own rep target, so the seed falls out as
        // a descending shape instead of one flat number written across every set.
        let proposed = slot.targets.map { target -> TargetSnapshot in
            let reps = Swift.min(Swift.max(target.reps ?? 10, 1), 20)
            let raw = config.e1rmSafetyFactor * e1rm / (1.0 + Double(reps) / 30.0)
            var copy = target
            copy.weightKg = CoachRounding.snapDown(raw, step: loadStep)
            return copy
        }

        guard proposed.allSatisfy({ ($0.weightKg ?? 0) > 0 }) else {
            return output(
                slot: slot, dimension: dimension, outcome: .insufficientData, applyClass: .noOp,
                delta: 0, targets: slot.targets,
                reason: "Not enough loaded history to seed a starting weight.",
                flags: flags, evidence: evidence, sourceSessionID: nil
            )
        }

        return finish(
            slot: slot, dimension: .load, outcome: .seedFromE1RM,
            preferredClass: .pendingReview, delta: 0, proposed: proposed,
            reason: "No history in this workout yet. Starting from your best \(Self.format(e1rm, .load)) estimated max elsewhere, held back \(Int((1 - config.e1rmSafetyFactor) * 100))%: \(Self.summary(proposed, .load)).",
            flags: flags, evidence: evidence, sourceSessionID: nil, config: config, step: loadStep
        )
    }

    /// Best Epley estimate for this Lift Identity across **every** workout — the one place
    /// cross-workout history is deliberately used, because the point is to borrow capacity
    /// the lifter has demonstrated somewhere else.
    static func bestE1RM(input: CoachInput) -> Double? {
        let slot = input.slot
        let config = input.config
        guard let cutoff = Calendar(identifier: .gregorian)
            .date(byAdding: .day, value: -config.e1rmWindowDays, to: input.asOf)
        else { return nil }

        let slotExerciseName = normalize(slot.exerciseName)
        var best: Double?
        for session in input.sessions where session.endedAt != nil
            && session.startedAt >= cutoff
            && session.startedAt <= input.asOf {
            for set in session.sets {
                let identityMatches: Bool
                if let id = set.exerciseID {
                    identityMatches = id == slot.exerciseID
                } else {
                    identityMatches = normalize(set.exerciseName) == slotExerciseName
                }
                guard identityMatches,
                      let weight = set.weightKg, weight.isFinite, weight > 0,
                      let reps = set.reps, config.e1rmSourceRepRange.contains(reps)
                else { continue }
                let estimate = weight * (1.0 + Double(reps) / 30.0)
                if estimate > (best ?? 0) { best = estimate }
            }
        }
        return best.map(CoachRounding.canonical)
    }

    // MARK: - Assembly

    /// The one place an `applyClass` is decided, so the invariant "only a single step in the
    /// usual direction ever writes itself" is enforced once rather than at each call site.
    static func finish(
        slot: SlotSnapshot,
        dimension: ProgressionDimension,
        outcome: CoachOutcome,
        preferredClass: ApplyClass,
        delta: Double,
        proposed: [TargetSnapshot],
        reason: String,
        flags: [CoachFlag],
        evidence: CoachEvidence,
        sourceSessionID: UUID?,
        config: CoachConfig,
        step: Double
    ) -> CoachOutput {
        var flags = flags
        var applyClass = preferredClass

        let values = proposed.compactMap { $0.value(on: dimension) }
        if values.contains(where: { !$0.isFinite || $0 <= 0 }) {
            flags.append(.implausibleValue)
            return output(
                slot: slot, dimension: dimension, outcome: .noTargets, applyClass: .noOp,
                delta: 0, targets: slot.targets,
                reason: "This slot's stored targets are not usable, so the coach is staying out of it.",
                flags: flags, evidence: evidence, sourceSessionID: sourceSessionID
            )
        }
        if values.contains(where: { $0 > dimension.implausibleAbove }) {
            flags.append(.implausibleValue)
        }

        // Structural check on the promise the auto-apply rule makes. `.increase` is one step
        // by construction; this catches a future rule change that quietly breaks that.
        if applyClass == .automatic, abs(delta) > step + config.epsilon {
            applyClass = .pendingReview
        }

        let reviewForcing: [CoachFlag] = [
            .identityMatchedByNameOnly, .workoutMatchedByNameOnly, .exerciseMissingFromLibrary,
            .stepSanitized, .setCountChanged, .missingTargetOnDimension, .implausibleValue,
            .baselineExceededTarget
        ]
        if applyClass == .automatic, flags.contains(where: { reviewForcing.contains($0) }) {
            applyClass = .pendingReview
        }

        return output(
            slot: slot, dimension: dimension, outcome: outcome, applyClass: applyClass,
            delta: delta, targets: proposed, reason: reason,
            flags: flags, evidence: evidence, sourceSessionID: sourceSessionID
        )
    }

    static func output(
        slot: SlotSnapshot,
        dimension: ProgressionDimension,
        outcome: CoachOutcome,
        applyClass: ApplyClass,
        delta: Double,
        targets: [TargetSnapshot],
        reason: String,
        flags: [CoachFlag],
        evidence: CoachEvidence,
        sourceSessionID: UUID?
    ) -> CoachOutput {
        let sortedFlags = Array(Swift.Set(flags)).sorted()
        return CoachOutput(
            slotID: slot.slotID,
            dimension: dimension,
            outcome: outcome,
            applyClass: applyClass,
            delta: CoachRounding.canonical(delta),
            proposedTargets: targets,
            reason: reason,
            flags: sortedFlags,
            evidence: evidence,
            sourceSessionID: sourceSessionID,
            fingerprint: fingerprint(
                slotID: slot.slotID, dimension: dimension, outcome: outcome,
                delta: delta, targets: targets
            )
        )
    }

    /// Deliberately a string, and deliberately not `hashValue`: Swift's `Hasher` is seeded
    /// per process, so a persisted hash silently stops matching after a relaunch and every
    /// dismissal would quietly resurrect itself.
    static func fingerprint(
        slotID: UUID,
        dimension: ProgressionDimension,
        outcome: CoachOutcome,
        delta: Double,
        targets: [TargetSnapshot]
    ) -> String {
        func num(_ value: Double?) -> String {
            guard let value, value.isFinite else { return "-" }
            return String(format: "%.3f", value)
        }
        func int(_ value: Int?) -> String { value.map(String.init) ?? "-" }
        let sets = targets
            .map { "w:\(num($0.weightKg)),r:\(int($0.reps)),d:\(int($0.durationSec)),m:\(num($0.distanceM))" }
            .joined(separator: ";")
        return "\(slotID.uuidString)|\(dimension.rawValue)|\(outcome.rawValue)|\(num(delta))|\(sets)"
    }

    // MARK: - Narration by the coach, never by a model

    static func holdReason(
        _ outcome: CoachOutcome,
        dimension: ProgressionDimension,
        evidence: CoachEvidence,
        config: CoachConfig
    ) -> String {
        switch outcome {
        case .holdFirstStall:
            return "Missed a target last session. Same numbers again — stall twice and the coach will back it down."
        case .holdRPEVeto:
            let rpe = evidence.maxRPE.map(String.init) ?? "high"
            return "You hit every target but called it RPE \(rpe). Holding here rather than adding load."
        case .holdLayoff:
            return "It has been over \(config.layoffDays) days since this lift. Repeating last session's numbers before adding anything."
        case .holdNoComparableHistory:
            return "Nothing comparable to go on yet — the targets changed, or this slot is new. Run it once as written."
        case .insufficientData:
            return "No history for this slot yet. Log one session and the coach will take it from there."
        default:
            return "Holding this slot where it is."
        }
    }

    static func format(_ value: Double, _ dimension: ProgressionDimension) -> String {
        switch dimension {
        case .load:
            return value == value.rounded() ? "\(Int(value)) kg" : String(format: "%.1f kg", value)
        case .reps:
            return "\(Int(value)) reps"
        case .duration:
            let total = Int(value)
            if total < 60 { return "\(total)s" }
            let m = total / 60, s = total % 60
            return s == 0 ? "\(m)m" : "\(m)m \(s)s"
        case .distance:
            return "\(Int(value)) m"
        }
    }

    static func summary(_ targets: [TargetSnapshot], _ dimension: ProgressionDimension) -> String {
        let values = targets.compactMap { $0.value(on: dimension) }
        guard let first = values.first else { return "—" }
        if values.allSatisfy({ abs($0 - first) < 0.001 }) {
            return "\(values.count)×\(format(first, dimension))"
        }
        return values.map { format($0, dimension) }.joined(separator: " / ")
    }
}
