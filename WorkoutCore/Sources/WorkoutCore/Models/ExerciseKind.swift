import Foundation

public enum ExerciseKind: String, Codable, CaseIterable, Hashable, Sendable {
    case reps
    case timed
    case distance

    public var displayName: String {
        switch self {
        case .reps: return "Reps"
        case .timed: return "Timed"
        case .distance: return "Distance"
        }
    }
}
