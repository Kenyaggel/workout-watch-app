import Foundation

public struct WeeklyVolume {
    public let weekStart: Date
    public let totalVolumeKg: Double

    public init(weekStart: Date, totalVolumeKg: Double) {
        self.weekStart = weekStart
        self.totalVolumeKg = totalVolumeKg
    }
}

public struct ExerciseDataPoint {
    public let sessionDate: Date
    public let maxWeightKg: Double
    public let totalVolumeKg: Double

    public init(sessionDate: Date, maxWeightKg: Double, totalVolumeKg: Double) {
        self.sessionDate = sessionDate
        self.maxWeightKg = maxWeightKg
        self.totalVolumeKg = totalVolumeKg
    }
}

public struct E1RMDataPoint {
    public let sessionDate: Date
    public let estimatedMax: Double

    public init(sessionDate: Date, estimatedMax: Double) {
        self.sessionDate = sessionDate
        self.estimatedMax = estimatedMax
    }
}

public struct FrequencyPoint {
    public let weekStart: Date
    public let sessionCount: Int

    public init(weekStart: Date, sessionCount: Int) {
        self.weekStart = weekStart
        self.sessionCount = sessionCount
    }
}
