import Foundation

// MARK: - Input

/// One set's Target, on whichever axes it specifies.
public struct TargetSnapshot: Equatable, Hashable, Sendable {
    public var weightKg: Double?
    public var reps: Int?
    public var durationSec: Int?
    public var distanceM: Double?

    public init(
        weightKg: Double? = nil,
        reps: Int? = nil,
        durationSec: Int? = nil,
        distanceM: Double? = nil
    ) {
        self.weightKg = weightKg
        self.reps = reps
        self.durationSec = durationSec
        self.distanceM = distanceM
    }

    public var isEmpty: Bool {
        weightKg == nil && reps == nil && durationSec == nil && distanceM == nil
    }

    public func value(on dimension: ProgressionDimension) -> Double? {
        switch dimension {
        case .load: return weightKg
        case .reps: return reps.map(Double.init)
        case .duration: return durationSec.map(Double.init)
        case .distance: return distanceM
        }
    }

    public func setting(_ dimension: ProgressionDimension, to value: Double) -> TargetSnapshot {
        var copy = self
        switch dimension {
        case .load: copy.weightKg = CoachRounding.canonical(value)
        case .reps: copy.reps = CoachRounding.integer(value, fallback: reps)
        case .duration: copy.durationSec = CoachRounding.integer(value, fallback: durationSec)
        case .distance: copy.distanceM = CoachRounding.canonical(value)
        }
        return copy
    }
}

/// The Slot the Coach is proposing for, flattened out of SwiftData so the rules stay pure.
public struct SlotSnapshot: Equatable, Sendable {
    /// `PlannedExercise.id`.
    public var slotID: UUID
    public var workoutID: UUID
    public var workoutName: String
    /// Lift Identity. Nil when the slot's exercise was deleted from the library.
    public var exerciseID: UUID?
    public var exerciseName: String
    /// Nil when the exercise is gone, which forces the dimension to be inferred.
    public var kind: ExerciseKind?
    public var progressionStep: Double?
    public var targets: [TargetSnapshot]
    /// This slot's position in its workout.
    public var orderIndex: Int
    /// The `orderIndex` of every slot in this workout sharing this exercise, ascending —
    /// including this one. Lets the rules tell a heavy bench slot from a backoff bench slot
    /// in the same workout without reaching back into SwiftData.
    public var peerSlotOrderIndexes: [Int]

    public init(
        slotID: UUID,
        workoutID: UUID,
        workoutName: String,
        exerciseID: UUID?,
        exerciseName: String,
        kind: ExerciseKind?,
        progressionStep: Double?,
        targets: [TargetSnapshot],
        orderIndex: Int = 0,
        peerSlotOrderIndexes: [Int] = []
    ) {
        self.slotID = slotID
        self.workoutID = workoutID
        self.workoutName = workoutName
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.kind = kind
        self.progressionStep = progressionStep
        self.targets = targets
        self.orderIndex = orderIndex
        self.peerSlotOrderIndexes = peerSlotOrderIndexes.isEmpty ? [orderIndex] : peerSlotOrderIndexes
    }
}

public struct PerformedSnapshot: Equatable, Sendable {
    public var id: UUID
    public var exerciseID: UUID?
    public var exerciseName: String
    public var exerciseIndex: Int
    public var setIndex: Int
    public var orderIndex: Int
    public var weightKg: Double?
    public var reps: Int?
    public var durationSec: Int?
    public var distanceM: Double?
    public var rpe: Int?
    public var completedAt: Date
    /// The Target this set was actually run against. Nil for rows performed before V3.
    public var target: TargetSnapshot?
    /// How many sets the slot planned at the time. Nil for rows performed before V3.
    public var plannedSetCount: Int?

    public init(
        id: UUID,
        exerciseID: UUID?,
        exerciseName: String,
        exerciseIndex: Int,
        setIndex: Int,
        orderIndex: Int,
        weightKg: Double? = nil,
        reps: Int? = nil,
        durationSec: Int? = nil,
        distanceM: Double? = nil,
        rpe: Int? = nil,
        completedAt: Date,
        target: TargetSnapshot? = nil,
        plannedSetCount: Int? = nil
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.exerciseIndex = exerciseIndex
        self.setIndex = setIndex
        self.orderIndex = orderIndex
        self.weightKg = weightKg
        self.reps = reps
        self.durationSec = durationSec
        self.distanceM = distanceM
        self.rpe = rpe
        self.completedAt = completedAt
        self.target = target
        self.plannedSetCount = plannedSetCount
    }

    /// A non-finite stored value reads as zero, so a corrupt row misses its target rather
    /// than earning progress.
    func performedValue(on dimension: ProgressionDimension) -> Double {
        let raw: Double?
        switch dimension {
        case .load: raw = weightKg
        case .reps: raw = reps.map(Double.init)
        case .duration: raw = durationSec.map(Double.init)
        case .distance: raw = distanceM
        }
        guard let raw, raw.isFinite else { return 0 }
        return raw
    }
}

public struct SessionSnapshot: Equatable, Sendable {
    public var id: UUID
    /// Nil when the workout was deleted, which is what makes the name fallback necessary.
    public var workoutID: UUID?
    public var workoutName: String
    public var startedAt: Date
    public var endedAt: Date?
    public var sets: [PerformedSnapshot]

    public init(
        id: UUID,
        workoutID: UUID?,
        workoutName: String,
        startedAt: Date,
        endedAt: Date?,
        sets: [PerformedSnapshot]
    ) {
        self.id = id
        self.workoutID = workoutID
        self.workoutName = workoutName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.sets = sets
    }
}

public struct CoachConfig: Equatable, Sendable {
    /// Fraction of the current target a Deload aims to remove.
    public var deloadFraction: Double = 0.10
    /// Consecutive Stalls that trigger a Deload.
    public var stallsBeforeDeload: Int = 2
    /// How far back the history walk looks for comparable sessions.
    public var maxLookbackSessions: Int = 6
    /// A lift untouched for longer than this gets no increase — adding a step to a weight
    /// last touched six weeks ago is how people get hurt on their first session back.
    public var layoffDays: Int = 28
    /// Window for the cross-workout e1RM seed. A PR from two years ago is not capacity.
    public var e1rmWindowDays: Int = 90
    /// Epley is fitted near a true single and reads badly above roughly a dozen reps, so
    /// only sets inside this range may seed.
    public var e1rmSourceRepRange: ClosedRange<Int> = 1...12
    /// The seed is borrowed from a different slot and discards fatigue, order and equipment,
    /// so it lands one notch under what Epley implies.
    public var e1rmSafetyFactor: Double = 0.90
    /// RPE at or above this vetoes an increase.
    public var rpeHoldThreshold: Int = 9
    /// RPE at this level on a stalled session escalates to a Deload.
    public var rpeDeloadThreshold: Int = 10
    /// A stored Progression Step beyond this multiple of the default is rejected as a typo.
    public var maxStepMultipleOfDefault: Double = 10
    /// Consecutive cut-short sessions before the Coach asks whether the slot is mis-authored.
    public var chronicPartialSessions: Int = 3
    public var epsilon: Double = 0.001

    public init() {}
}

public struct CoachInput: Sendable {
    public var slot: SlotSnapshot
    /// Every session in a bounded window, **not** pre-scoped to the slot. Slot scoping,
    /// occurrence matching and the cross-workout e1RM scan all happen inside the pure
    /// function, so the part most likely to be wrong is the part under test.
    public var sessions: [SessionSnapshot]
    /// Injected, never read from the clock — same discipline as `SessionEngine.nowProvider`.
    public var asOf: Date
    public var config: CoachConfig

    public init(
        slot: SlotSnapshot,
        sessions: [SessionSnapshot],
        asOf: Date,
        config: CoachConfig = CoachConfig()
    ) {
        self.slot = slot
        self.sessions = sessions
        self.asOf = asOf
        self.config = config
    }
}

// MARK: - Output

public enum CoachOutcome: String, Codable, Hashable, Sendable {
    case increase
    case deload
    case seedFromE1RM
    case holdFirstStall
    case holdRPEVeto
    case holdNoComparableHistory
    case holdAtFloor
    case holdLayoff
    case holdAdvisoryCeiling
    case holdChronicPartialSession
    case insufficientData
    case noTargets
}

/// Governs the writer only. The review screen renders every outcome; `.noOp` means
/// "nothing to write and nothing to approve", not "nothing to show".
public enum ApplyClass: String, Codable, Hashable, Sendable {
    /// One step in the usual direction. Applied straight to the workout so the watch is
    /// never stale on a day the lifter skips the phone.
    case automatic
    /// Held until a human looks at it. Approval authority stays where the stakes are.
    case pendingReview
    /// Numbers unchanged; there is nothing to write.
    case noOp
}

/// Reasons a proposal cannot be trusted enough to apply itself.
public enum CoachFlag: String, Codable, Hashable, Sendable, Comparable {
    case identityMatchedByNameOnly
    case workoutMatchedByNameOnly
    case exerciseMissingFromLibrary
    case stepSanitized
    case setCountChanged
    case missingTargetOnDimension
    case implausibleValue
    case baselineExceededTarget
    case legacyRowsWithoutRecordedTarget

    public static func < (lhs: CoachFlag, rhs: CoachFlag) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// How one session scored for one slot.
public enum SlotVerdict: String, Codable, Hashable, Sendable {
    case hit
    case stall
    /// Not trained, or trained short with no miss — carries no information about whether the
    /// load is right, so the history walk passes straight through it.
    case skipped
}

public struct CoachEvidence: Equatable, Sendable {
    public var consecutiveStalls: Int = 0
    public var comparableSessionCount: Int = 0
    public var lastVerdict: SlotVerdict?
    public var lastSessionDate: Date?
    public var maxRPE: Int?
    public var sourceE1RM: Double?
    public var resolvedStep: Double = 0
    public var consecutivePartialSessions: Int = 0

    public init() {}
}

public struct CoachOutput: Equatable, Sendable {
    public var slotID: UUID
    public var dimension: ProgressionDimension
    public var outcome: CoachOutcome
    public var applyClass: ApplyClass
    /// Signed move on the dimension's axis. Zero for every hold.
    public var delta: Double
    /// Always a complete vector, same count and order as the slot's targets, equal to the
    /// current targets on every hold — so the writer never has to reason about which sets
    /// to touch.
    public var proposedTargets: [TargetSnapshot]
    public var reason: String
    public var flags: [CoachFlag]
    public var evidence: CoachEvidence
    /// The session that produced this reading. A dismissal is scoped to it, so dismissing
    /// means "not on this evidence" rather than "never again".
    public var sourceSessionID: UUID?
    /// Content identity of the proposal, as an explicit string. Never `hashValue`: Swift's
    /// `Hasher` is seeded per process, so a persisted hash silently stops matching after a
    /// relaunch.
    public var fingerprint: String

    public var isPendingReview: Bool { applyClass == .pendingReview }
}
