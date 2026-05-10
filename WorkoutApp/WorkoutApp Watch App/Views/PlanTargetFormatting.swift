import Foundation
import WorkoutCore

func plannedTargetText(for set: SessionPlan.Set, kind: ExerciseKind) -> String {
    switch kind {
    case .reps:
        var parts: [String] = []
        if let weight = set.targetWeightKg {
            parts.append("\(formatWeight(weight)) kg")
        }
        if let reps = set.targetReps {
            parts.append("\(reps) reps")
        }
        return parts.isEmpty ? "Open target" : parts.joined(separator: " x ")
    case .timed:
        if let seconds = set.targetDurationSec {
            return "\(seconds) sec"
        }
        return "Timed set"
    case .distance:
        if let meters = set.targetDistanceM {
            return "\(formatDistance(meters)) m"
        }
        return "Distance set"
    }
}

func plannedRestText(_ seconds: Int) -> String {
    guard seconds > 0 else { return "No rest" }
    let minutes = seconds / 60
    let remainder = seconds % 60
    if minutes == 0 {
        return "\(seconds)s rest"
    }
    if remainder == 0 {
        return "\(minutes)m rest"
    }
    return "\(minutes)m \(remainder)s rest"
}

private func formatWeight(_ value: Double) -> String {
    if value.rounded() == value {
        return String(Int(value))
    }
    return String(format: "%.1f", value)
}

private func formatDistance(_ value: Double) -> String {
    if value.rounded() == value {
        return String(Int(value))
    }
    return String(format: "%.1f", value)
}
