import Foundation
import SwiftData

public struct AnalyticsEngine {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Weekly Volume

    /// Fetch all PerformedSets with completedAt in the last N calendar weeks, group by calendar
    /// week (ISO 8601 Monday start), sum weight×reps per week, return sorted ascending by weekStart.
    public func weeklyVolume(last weeks: Int) -> [WeeklyVolume] {
        var isoCal = Calendar(identifier: .iso8601)
        isoCal.locale = Locale(identifier: "en_US_POSIX")
        let cal = isoCal
        let now = Date()
        // Snap to the start of the current ISO week so we don't split weeks mid-day.
        guard let thisWeekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start,
              let rangeStart = cal.date(byAdding: .weekOfYear, value: -weeks, to: thisWeekStart)
        else {
            return []
        }

        let descriptor = FetchDescriptor<PerformedSet>(
            predicate: #Predicate { $0.completedAt >= rangeStart }
        )
        let sets = (try? modelContext.fetch(descriptor)) ?? []

        var volumeByWeek: [Date: Double] = [:]
        for set in sets {
            guard let weekStart = cal.dateInterval(of: .weekOfYear, for: set.completedAt)?.start else {
                continue
            }
            let volume = (set.weightKg ?? 0) * Double(set.reps ?? 0)
            volumeByWeek[weekStart, default: 0] += volume
        }

        return volumeByWeek
            .map { WeeklyVolume(weekStart: $0.key, totalVolumeKg: $0.value) }
            .sorted { $0.weekStart < $1.weekStart }
    }

    // MARK: - Exercise Progression

    /// Fetch PerformedSets filtered by exerciseName with reps > 0 and weightKg not nil,
    /// group by session.startedAt calendar day, per session take max weightKg and sum volume,
    /// return last N sessions sorted ascending by sessionDate.
    public func exerciseProgression(exerciseName: String, last sessions: Int) -> [ExerciseDataPoint] {
        let cal = Calendar.current
        let now = Date()
        // Conservative date lower-bound: 60 days per requested session keeps the fetch bounded
        // while virtually never excluding real data.
        let conservativeDaysBack = sessions * 60
        guard let rangeStart = cal.date(byAdding: .day, value: -conservativeDaysBack, to: now) else {
            return []
        }

        let descriptor = FetchDescriptor<PerformedSet>(
            predicate: #Predicate {
                $0.exerciseName == exerciseName &&
                $0.weightKg != nil &&
                $0.reps != nil &&
                $0.completedAt >= rangeStart
            }
        )
        let sets = (try? modelContext.fetch(descriptor)) ?? []

        // SwiftData #Predicate cannot express Int? > 0 comparisons — filter in Swift
        let filtered = sets.filter { ($0.reps ?? 0) > 0 }

        // Group by session day using session.startedAt if available, else completedAt
        var byDay: [Date: [PerformedSet]] = [:]
        for set in filtered {
            let anchor = set.session?.startedAt ?? set.completedAt
            guard let dayStart = cal.dateInterval(of: .day, for: anchor)?.start else { continue }
            byDay[dayStart, default: []].append(set)
        }

        let allPoints = byDay.map { (day, daySets) -> ExerciseDataPoint in
            let maxWeight = daySets.compactMap(\.weightKg).max() ?? 0
            let totalVolume = daySets.reduce(0.0) { acc, s in
                acc + (s.weightKg ?? 0) * Double(s.reps ?? 0)
            }
            return ExerciseDataPoint(sessionDate: day, maxWeightKg: maxWeight, totalVolumeKg: totalVolume)
        }
        .sorted { $0.sessionDate < $1.sessionDate }

        let lastN = allPoints.suffix(sessions)
        return Array(lastN)
    }

    // MARK: - Workout Frequency

    /// Fetch WorkoutSessions with startedAt in range, group by calendar week, count per week,
    /// return sorted ascending by weekStart.
    public func workoutFrequency(last months: Int) -> [FrequencyPoint] {
        let cal = Calendar.current
        let now = Date()
        // Snap to the start of the current month so we don't split months mid-day.
        guard let thisMonthStart = cal.dateInterval(of: .month, for: now)?.start,
              let rangeStart = cal.date(byAdding: .month, value: -months, to: thisMonthStart)
        else {
            return []
        }

        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.startedAt >= rangeStart }
        )
        let sessions = (try? modelContext.fetch(descriptor)) ?? []

        var countByWeek: [Date: Int] = [:]
        for session in sessions {
            guard let weekStart = cal.dateInterval(of: .weekOfYear, for: session.startedAt)?.start else {
                continue
            }
            countByWeek[weekStart, default: 0] += 1
        }

        return countByWeek
            .map { FrequencyPoint(weekStart: $0.key, sessionCount: $0.value) }
            .sorted { $0.weekStart < $1.weekStart }
    }

    // MARK: - Estimated 1RM

    /// Fetch PerformedSets for exercise with non-nil weightKg and reps > 0,
    /// group by session day, apply Epley formula weight * (1 + reps / 30.0) to each set,
    /// take max e1RM per session, return last N sessions sorted ascending.
    public func estimated1RM(exerciseName: String, last sessions: Int) -> [E1RMDataPoint] {
        let cal = Calendar.current
        let now = Date()
        // Conservative date lower-bound: 60 days per requested session keeps the fetch bounded.
        let conservativeDaysBack = sessions * 60
        guard let rangeStart = cal.date(byAdding: .day, value: -conservativeDaysBack, to: now) else {
            return []
        }

        let descriptor = FetchDescriptor<PerformedSet>(
            predicate: #Predicate {
                $0.exerciseName == exerciseName &&
                $0.weightKg != nil &&
                $0.reps != nil &&
                $0.completedAt >= rangeStart
            }
        )
        let sets = (try? modelContext.fetch(descriptor)) ?? []

        // SwiftData #Predicate cannot express Int? > 0 comparisons — filter in Swift
        let filtered = sets.filter { ($0.reps ?? 0) > 0 }

        var byDay: [Date: Double] = [:]
        for set in filtered {
            let anchor = set.session?.startedAt ?? set.completedAt
            guard let dayStart = cal.dateInterval(of: .day, for: anchor)?.start else { continue }
            let weight = set.weightKg ?? 0
            let reps = set.reps ?? 0
            let e1rm = weight * (1.0 + Double(reps) / 30.0)
            if e1rm > (byDay[dayStart] ?? 0) {
                byDay[dayStart] = e1rm
            }
        }

        let allPoints = byDay
            .map { E1RMDataPoint(sessionDate: $0.key, estimatedMax: $0.value) }
            .sorted { $0.sessionDate < $1.sessionDate }

        let lastN = allPoints.suffix(sessions)
        return Array(lastN)
    }
}
