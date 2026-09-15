import Foundation

/// The deterministic rules that turn Session history into Proposed Targets.
///
/// `propose` is pure and total: it reads no clock, touches no SwiftData, and returns a
/// value for every input including degenerate ones. `asOf` is injected exactly the way
/// `SessionEngine` injects `nowProvider`, so the whole thing is testable in plain Swift on
/// macOS. Sessions arrive **unscoped** — slot scoping, occurrence matching and the
/// cross-workout e1RM scan all happen in here, which keeps the intricate part under test
/// rather than in a SwiftData adapter.
///
/// The Coach is the only source of a number. A language model never is.
public enum Coach {

    public static func propose(_ input: CoachInput) -> CoachOutput {
        let slot = input.slot
        let config = input.config
        var flags: [CoachFlag] = []

        // MARK: Dimension

        let dimension: ProgressionDimension
        if let kind = slot.kind {
            let hasWeight = slot.targets.contains { ($0.weightKg ?? 0) > 0 }
            dimension = ProgressionDimension.resolve(kind: kind, hasTargetWeight: hasWeight)
        } else {
            dimension = ProgressionDimension.infer(from: slot.targets)
            flags.append(.exerciseMissingFromLibrary)
        }

        guard !slot.targets.isEmpty else {
            return output(
                slot: slot, dimension: dimension, outcome: .noTargets, applyClass: .noOp,
                delta: 0, targets: slot.targets,
                reason: "This slot has no sets to progress.",
                flags: flags, evidence: CoachEvidence(), sourceSessionID: nil
            )
        }

        let step = resolveStep(slot.progressionStep, dimension: dimension, config: config, flags: &flags)
        var evidence = CoachEvidence()
        evidence.resolvedStep = step

        guard slot.targets.contains(where: { ($0.value(on: dimension) ?? 0) > 0 }) else {
            return output(
                slot: slot, dimension: dimension, outcome: .noTargets, applyClass: .noOp,
                delta: 0, targets: slot.targets,
                reason: "No set specifies a \(dimension.displayName.lowercased()) target, so there is nothing to move.",
                flags: flags, evidence: evidence, sourceSessionID: nil
            )
        }

        // MARK: History

        let history = scopedHistory(input: input, dimension: dimension, flags: &flags)
        evidence.comparableSessionCount = history.count

        let walk = walkBackward(history: history, slot: slot, dimension: dimension, config: config, flags: &flags)
        evidence.consecutiveStalls = walk.consecutiveStalls
        evidence.consecutivePartialSessions = walk.consecutivePartialSessions
        evidence.lastVerdict = walk.lastVerdict
        evidence.lastSessionDate = walk.evaluated?.session.startedAt
        evidence.maxRPE = walk.maxRPE

        // MARK: No comparable history — seed, or stay quiet

        guard let evaluated = walk.evaluated, let verdict = walk.lastVerdict, verdict != .skipped else {
            return proposeWithoutHistory(
                input: input, dimension: dimension, step: step,
                flags: &flags, evidence: &evidence,
                sawSkippedSession: walk.lastVerdict == .skipped
            )
        }

        let sourceSessionID = evaluated.session.id

        // MARK: Base outcome

        var outcome: CoachOutcome
        switch verdict {
        case .hit:
            outcome = .increase
        case .stall:
            outcome = walk.consecutiveStalls >= config.stallsBeforeDeload ? .deload : .holdFirstStall
        case .skipped:
            outcome = .holdNoComparableHistory
        }

        if walk.consecutivePartialSessions >= config.chronicPartialSessions {
            outcome = .holdChronicPartialSession
        }

        // MARK: RPE veto — direction only, never step size

        if let rpe = walk.maxRPE {
            if outcome == .increase, rpe >= config.rpeHoldThreshold {
                outcome = .holdRPEVeto
            } else if outcome == .holdFirstStall, rpe >= config.rpeDeloadThreshold {
                outcome = .deload
            }
        }

        // MARK: Layoff

        if outcome == .increase,
           let last = walk.evaluated?.session.startedAt,
           let cutoff = Calendar(identifier: .gregorian).date(byAdding: .day, value: -config.layoffDays, to: input.asOf),
           last < cutoff {
            outcome = .holdLayoff
        }

        // MARK: Numbers

        switch outcome {
        case .increase:
            return proposeIncrease(
                slot: slot, dimension: dimension, step: step, evaluated: evaluated,
                config: config, flags: &flags, evidence: evidence, sourceSessionID: sourceSessionID
            )

        case .deload:
            return proposeDeload(
                slot: slot, dimension: dimension, step: step, config: config,
                flags: &flags, evidence: evidence, sourceSessionID: sourceSessionID,
                escalatedByRPE: verdict == .stall && walk.consecutiveStalls < config.stallsBeforeDeload
            )

        case .holdChronicPartialSession:
            return output(
                slot: slot, dimension: dimension, outcome: outcome, applyClass: .pendingReview,
                delta: 0, targets: slot.targets,
                reason: "This slot has been cut short \(walk.consecutivePartialSessions) sessions running. Should it have fewer sets?",
                flags: flags, evidence: evidence, sourceSessionID: sourceSessionID
            )

        default:
            return output(
                slot: slot, dimension: dimension, outcome: outcome, applyClass: .noOp,
                delta: 0, targets: slot.targets,
                reason: holdReason(outcome, dimension: dimension, evidence: evidence, config: config),
                flags: flags, evidence: evidence, sourceSessionID: sourceSessionID
            )
        }
    }

    // MARK: - Step

    /// A stored step that is nil, non-positive, non-finite, or wildly out of scale is
    /// **rejected** back to the dimension default rather than clamped. Clamping preserves an
    /// intent that is not there: a fat-fingered 500 in the kg field would become a 20 kg
    /// jump that still looked like one honest step and applied itself.
    static func resolveStep(
        _ stored: Double?,
        dimension: ProgressionDimension,
        config: CoachConfig,
        flags: inout [CoachFlag]
    ) -> Double {
        let fallback = dimension.defaultStep
        guard let stored, stored.isFinite, stored > 0 else { return fallback }
        guard stored <= fallback * config.maxStepMultipleOfDefault else {
            flags.append(.stepSanitized)
            return fallback
        }
        if dimension.isIntegral {
            let rounded = stored.rounded()
            guard rounded >= 1 else {
                flags.append(.stepSanitized)
                return fallback
            }
            // A step of 2.5 on an axis quantized at 1 is not a step this axis can express.
            if abs(stored - rounded) > config.epsilon {
                flags.append(.stepSanitized)
            }
            return rounded
        }
        return CoachRounding.canonical(stored)
    }

    // MARK: - Scoping

    struct ScopedSession: Equatable {
        var session: SessionSnapshot
        var sets: [PerformedSnapshot]
    }

    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// Scope is the (workout, exercise) pair, never `exerciseIndex` — that only separates
    /// two occurrences of the same exercise *within* one session. Keying on position would
    /// break the moment a slot was reordered.
    static func scopedHistory(
        input: CoachInput,
        dimension: ProgressionDimension,
        flags: inout [CoachFlag]
    ) -> [ScopedSession] {
        let slot = input.slot
        let slotWorkoutName = normalize(slot.workoutName)
        let slotExerciseName = normalize(slot.exerciseName)

        // Rank of this slot among the slots in this workout that share its exercise.
        let peers = slot.peerSlotOrderIndexes.sorted()
        let rank = peers.firstIndex(of: slot.orderIndex) ?? 0

        var matchedByWorkoutName = false
        var matchedByExerciseName = false

        let candidates = input.sessions.filter { session in
            guard session.endedAt != nil, session.startedAt <= input.asOf else { return false }
            if let id = session.workoutID { return id == slot.workoutID }
            // The template relationship was nullified by a delete; reconnect by name so a
            // recreated workout of the same name keeps its history.
            let matches = normalize(session.workoutName) == slotWorkoutName
            if matches { matchedByWorkoutName = true }
            return matches
        }
        .sorted { lhs, rhs in
            if lhs.startedAt != rhs.startedAt { return lhs.startedAt > rhs.startedAt }
            return lhs.id.uuidString > rhs.id.uuidString
        }

        var result: [ScopedSession] = []
        for session in candidates {
            let ordered = matchedSets(in: session, slot: slot, rank: rank, matchedByName: &matchedByExerciseName)
            guard !ordered.isEmpty else { continue }
            result.append(ScopedSession(session: session, sets: ordered))
        }

        if matchedByWorkoutName { flags.append(.workoutMatchedByNameOnly) }
        if matchedByExerciseName { flags.append(.identityMatchedByNameOnly) }
        return result
    }

    /// The Performed Sets belonging to one Slot within one Session, deduplicated and totally
    /// ordered. Exposed so the write-back path pairs sets with targets exactly the way the
    /// rules did when they judged them.
    public static func matchedSets(in session: SessionSnapshot, slot: SlotSnapshot) -> [PerformedSnapshot] {
        var ignored = false
        let peers = slot.peerSlotOrderIndexes.sorted()
        let rank = peers.firstIndex(of: slot.orderIndex) ?? 0
        return matchedSets(in: session, slot: slot, rank: rank, matchedByName: &ignored)
    }

    static func matchedSets(
        in session: SessionSnapshot,
        slot: SlotSnapshot,
        rank: Int,
        matchedByName: inout Bool
    ) -> [PerformedSnapshot] {
        let slotExerciseName = normalize(slot.exerciseName)
        let matched = session.sets.filter { set in
            if let id = set.exerciseID {
                // A present-but-different id is definitive evidence of a different lift.
                // Falling back to the name here would reintroduce the pooling the ADR
                // exists to remove.
                return id == slot.exerciseID
            }
            let matches = normalize(set.exerciseName) == slotExerciseName
            if matches { matchedByName = true }
            return matches
        }
        guard !matched.isEmpty else { return [] }

        // Separate repeated occurrences of one exercise inside a single session.
        let occurrences = Array(Swift.Set(matched.map(\.exerciseIndex))).sorted()
        guard rank < occurrences.count else { return [] }
        let occurrence = occurrences[rank]

        var deduped: [Int: PerformedSnapshot] = [:]
        for set in matched where set.exerciseIndex == occurrence {
            // Re-import and crash recovery both produce duplicate setIndex rows; keep one
            // deterministically instead of letting it shift every later pairing.
            if let existing = deduped[set.setIndex], existing.orderIndex <= set.orderIndex {
                continue
            }
            deduped[set.setIndex] = set
        }

        return deduped.values.sorted { lhs, rhs in
            if lhs.setIndex != rhs.setIndex { return lhs.setIndex < rhs.setIndex }
            if lhs.orderIndex != rhs.orderIndex { return lhs.orderIndex < rhs.orderIndex }
            if lhs.completedAt != rhs.completedAt { return lhs.completedAt < rhs.completedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    // MARK: - The walk

    struct Walk {
        var evaluated: ScopedSession?
        var lastVerdict: SlotVerdict?
        var consecutiveStalls = 0
        var consecutivePartialSessions = 0
        var maxRPE: Int?
    }

    static func walkBackward(
        history: [ScopedSession],
        slot: SlotSnapshot,
        dimension: ProgressionDimension,
        config: CoachConfig,
        flags: inout [CoachFlag]
    ) -> Walk {
        var walk = Walk()
        var considered = 0
        var sawLegacyRow = false
        var countedPartials = true
        var sawIncomparable = false

        for scoped in history {
            guard considered < config.maxLookbackSessions else { break }

            // Sessions run against a different prescription are not comparable: a hit at
            // 55 kg must never earn an increase to 62.5 when the slot now says 60. This is
            // also what stops three sessions syncing in a burst from stacking three
            // increases — the first apply moves the target, and every one of those sessions
            // then reads as run against the old one.
            switch comparability(scoped: scoped, slot: slot, dimension: dimension, config: config) {
            case .incomparable:
                sawIncomparable = true
            case .legacy:
                sawLegacyRow = true
            case .comparable:
                break
            }
            if sawIncomparable { break }

            considered += 1
            let judged = judge(scoped: scoped, slot: slot, dimension: dimension, config: config)

            if judged.verdict == .skipped {
                if judged.wasCutShort, countedPartials {
                    walk.consecutivePartialSessions += 1
                }
                // A short session with no miss says nothing about whether the load is right,
                // so it neither breaks the streak nor extends it — the walk passes through.
                continue
            }
            countedPartials = false

            if walk.evaluated == nil {
                walk.evaluated = scoped
                walk.lastVerdict = judged.verdict
                walk.maxRPE = judged.maxRPE
            }

            if judged.verdict == .stall {
                walk.consecutiveStalls += 1
            } else {
                break
            }
        }

        if walk.evaluated == nil, walk.lastVerdict == nil, !history.isEmpty {
            walk.lastVerdict = .skipped
        }
        if sawLegacyRow { flags.append(.legacyRowsWithoutRecordedTarget) }
        return walk
    }

    enum Comparability { case comparable, legacy, incomparable }

    static func comparability(
        scoped: ScopedSession,
        slot: SlotSnapshot,
        dimension: ProgressionDimension,
        config: CoachConfig
    ) -> Comparability {
        guard let anchorIndex = slot.targets.firstIndex(where: { ($0.value(on: dimension) ?? 0) > 0 }),
              let currentAnchor = slot.targets[anchorIndex].value(on: dimension)
        else { return .comparable }

        let recorded = scoped.sets.compactMap(\.target)
        guard !recorded.isEmpty else { return .legacy }

        // The slot's own dimension may have changed — a weight added to what used to be a
        // bodyweight slot. Sessions from before that are a different exercise in practice.
        if let kind = slot.kind {
            let sessionHadWeight = recorded.contains { ($0.weightKg ?? 0) > 0 }
            if ProgressionDimension.resolve(kind: kind, hasTargetWeight: sessionHadWeight) != dimension {
                return .incomparable
            }
        }

        guard let ranAnchor = recorded.compactMap({ $0.value(on: dimension) }).first(where: { $0 > 0 }) else {
            return .legacy
        }
        return abs(ranAnchor - currentAnchor) <= config.epsilon ? .comparable : .incomparable
    }

    // MARK: - Judging one session

    struct Judgement {
        var verdict: SlotVerdict
        var wasCutShort = false
        var maxRPE: Int?
    }

    static func judge(
        scoped: ScopedSession,
        slot: SlotSnapshot,
        dimension: ProgressionDimension,
        config: CoachConfig
    ) -> Judgement {
        let performed = scoped.sets
        guard !performed.isEmpty else { return Judgement(verdict: .skipped) }

        // How many sets the slot planned *then*, not how many it plans now. Judging a
        // 3-of-4 session against today's 3 sets would read it as complete.
        let plannedCount = performed.compactMap(\.plannedSetCount).first ?? slot.targets.count
        let maxRPE = performed.compactMap(\.rpe).max()

        var anyMiss = false
        var judgedCount = 0
        for (index, set) in performed.enumerated() {
            guard index < plannedCount else { break }   // bonus sets neither help nor hurt
            guard let target = set.target ?? slot.targets[safeIndex: index] else { continue }
            judgedCount += 1
            if !met(set: set, target: target, config: config) { anyMiss = true }
        }

        guard judgedCount > 0 else { return Judgement(verdict: .skipped, maxRPE: maxRPE) }

        if anyMiss {
            // A short session *with* a miss is the most informative stall in the data — the
            // load beat you and you left because of it. Full weight.
            return Judgement(verdict: .stall, maxRPE: maxRPE)
        }
        if performed.count < plannedCount {
            // A short session with no misses carries no information: two perfect sets then
            // the fire alarm says nothing about set four.
            return Judgement(verdict: .skipped, wasCutShort: true, maxRPE: maxRPE)
        }
        return Judgement(verdict: .hit, maxRPE: maxRPE)
    }

    /// A set meets its Target iff every component the Target actually specifies was reached.
    /// Weight counts on every axis, so a lifter cannot shed the plate and keep collecting
    /// seconds on a weighted plank.
    static func met(set: PerformedSnapshot, target: TargetSnapshot, config: CoachConfig) -> Bool {
        if let w = target.weightKg, w > 0 {
            let actual = set.weightKg.flatMap { $0.isFinite ? $0 : nil } ?? 0
            if actual < w - config.epsilon { return false }
        }
        if let r = target.reps, r > 0, (set.reps ?? 0) < r { return false }
        if let d = target.durationSec, d > 0, (set.durationSec ?? 0) < d { return false }
        if let m = target.distanceM, m > 0 {
            let actual = set.distanceM.flatMap { $0.isFinite ? $0 : nil } ?? 0
            if actual < m - config.epsilon { return false }
        }
        return true
    }
}

extension Array {
    subscript(safeIndex index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
