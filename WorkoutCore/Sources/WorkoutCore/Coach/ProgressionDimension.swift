import Foundation

/// The single axis along which an exercise gets harder. Every exercise has exactly one.
public enum ProgressionDimension: String, Codable, CaseIterable, Hashable, Sendable {
    case load
    case reps
    case duration
    case distance

    /// The Progression Step used when the exercise does not override it, in this
    /// dimension's own unit.
    ///
    /// The relative magnitudes are deliberately uneven — 2.5/60kg is 4.2%, 1/10 reps is
    /// 10%, 5/45s is 11%, 100/1000m is 10%. Load is the most conservative in relative
    /// terms because load is the axis where an overshoot injures you. 2.5 kg is also the
    /// smallest pair of plates a kg gym stocks; a step below what you can physically load
    /// produces a proposal the lifter cannot execute.
    public var defaultStep: Double {
        switch self {
        case .load: return 2.5
        case .reps: return 1
        case .duration: return 5
        case .distance: return 100
        }
    }

    /// Steps on these axes must be whole numbers — there is no half a rep.
    public var isIntegral: Bool {
        switch self {
        case .reps, .duration: return true
        case .load, .distance: return false
        }
    }

    public var unitLabel: String {
        switch self {
        case .load: return "kg"
        case .reps: return "reps"
        case .duration: return "sec"
        case .distance: return "m"
        }
    }

    public var displayName: String {
        switch self {
        case .load: return "Weight"
        case .reps: return "Reps"
        case .duration: return "Duration"
        case .distance: return "Distance"
        }
    }

    /// A proposal beyond this is treated as evidence of corrupt data rather than training
    /// progress, and is never applied without a human.
    public var implausibleAbove: Double {
        switch self {
        case .load: return 500
        case .reps: return 100
        case .duration: return 7_200
        case .distance: return 100_000
        }
    }

    /// Past this the axis has stopped being a strength stimulus and the real answer — a
    /// harder variation, or adding load — is a choice only a human can make.
    public var advisoryCeiling: Double? {
        switch self {
        case .reps: return 30
        case .duration: return 300
        case .load, .distance: return nil
        }
    }

    /// `.timed` stays on duration even when the slot carries a weight, and `.reps` moves to
    /// load only once a weight is actually authored.
    ///
    /// Routing a weighted plank to load would be worse than useless: `Exercise.progressionStep`
    /// is one scalar, so a plank authored with a step of 5 *seconds* would silently start
    /// adding 5 *kilograms* a session the moment a plate appeared. The weight on a timed or
    /// distance slot is instead a gate on whether a set was met — see `Coach`.
    public static func resolve(kind: ExerciseKind, hasTargetWeight: Bool) -> ProgressionDimension {
        switch kind {
        case .reps: return hasTargetWeight ? .load : .reps
        case .timed: return .duration
        case .distance: return .distance
        }
    }

    /// For a slot whose exercise has been deleted from the library there is no kind to read,
    /// so the dimension is inferred from what the slot's own targets actually carry.
    public static func infer(from targets: [TargetSnapshot]) -> ProgressionDimension {
        if targets.contains(where: { ($0.distanceM ?? 0) > 0 }) { return .distance }
        if targets.contains(where: { ($0.durationSec ?? 0) > 0 }) { return .duration }
        if targets.contains(where: { ($0.weightKg ?? 0) > 0 }) { return .load }
        return .reps
    }
}
