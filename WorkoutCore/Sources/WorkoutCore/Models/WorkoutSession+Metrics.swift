import Foundation

public extension WorkoutSession {
    var durationSec: Int? {
        guard let endedAt else { return nil }
        return max(0, Int(endedAt.timeIntervalSince(startedAt)))
    }

    var totalVolumeKg: Double {
        performedSets.reduce(0) { total, set in
            total + set.volumeKg
        }
    }
}

public extension PerformedSet {
    var volumeKg: Double {
        guard let weightKg, let reps else { return 0 }
        return weightKg * Double(reps)
    }
}
