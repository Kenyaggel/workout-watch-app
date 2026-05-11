import Foundation

public struct WeeklyVolume: Sendable, Equatable {
    public let weekStart: Date
    public let totalVolumeKg: Double

    public init(weekStart: Date, totalVolumeKg: Double) {
        self.weekStart = weekStart
        self.totalVolumeKg = totalVolumeKg
    }
}

public struct ExerciseDataPoint: Sendable, Equatable {
    public let sessionDate: Date
    public let maxWeightKg: Double
    public let totalVolumeKg: Double

    public init(sessionDate: Date, maxWeightKg: Double, totalVolumeKg: Double) {
        self.sessionDate = sessionDate
        self.maxWeightKg = maxWeightKg
        self.totalVolumeKg = totalVolumeKg
    }
}

public struct E1RMDataPoint: Sendable, Equatable {
    public let sessionDate: Date
    public let estimatedMax: Double

    public init(sessionDate: Date, estimatedMax: Double) {
        self.sessionDate = sessionDate
        self.estimatedMax = estimatedMax
    }
}

public struct ExerciseAnalytics: Sendable, Equatable {
    public let progression: [ExerciseDataPoint]
    public let e1rm: [E1RMDataPoint]

    public init(progression: [ExerciseDataPoint], e1rm: [E1RMDataPoint]) {
        self.progression = progression
        self.e1rm = e1rm
    }
}

public struct FrequencyPoint: Sendable, Equatable {
    public let weekStart: Date
    public let sessionCount: Int

    public init(weekStart: Date, sessionCount: Int) {
        self.weekStart = weekStart
        self.sessionCount = sessionCount
    }
}
