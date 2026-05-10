import XCTest
import SwiftData
@testable import WorkoutCore

final class AnalyticsEngineTests: XCTestCase {

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        let container = try WorkoutModelContainer.makeShared(inMemory: true)
        return ModelContext(container)
    }

    /// Returns midnight of the given date in the current calendar.
    private func dayStart(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    /// Returns the Monday-start week anchor for the given date.
    private func weekStart(_ date: Date) -> Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: date)!.start
    }

    // MARK: - weeklyVolume

    func testWeeklyVolumeSum() throws {
        let ctx = try makeContext()

        // Use a fixed point in time well within the last 4 weeks.
        let now = Date()
        let yesterday = now.addingTimeInterval(-86_400)
        let twoDaysAgo = now.addingTimeInterval(-2 * 86_400)

        // Session 1 — yesterday
        let session1 = WorkoutSession(startedAt: yesterday, templateName: "Push")
        ctx.insert(session1)

        let set1 = PerformedSet(
            orderIndex: 0, exerciseName: "Bench Press",
            exerciseIndex: 0, setIndex: 0,
            weightKg: 100, reps: 5,
            completedAt: yesterday
        )
        set1.session = session1
        ctx.insert(set1)

        // Session 2 — two days ago
        let session2 = WorkoutSession(startedAt: twoDaysAgo, templateName: "Push")
        ctx.insert(session2)

        let set2 = PerformedSet(
            orderIndex: 0, exerciseName: "Squat",
            exerciseIndex: 0, setIndex: 0,
            weightKg: 80, reps: 3,
            completedAt: twoDaysAgo
        )
        set2.session = session2
        ctx.insert(set2)

        try ctx.save()

        let engine = AnalyticsEngine(modelContext: ctx)
        let results = engine.weeklyVolume(last: 4)

        // Both dates should fall in the same calendar week (both within the last 2 days).
        // Expected volume for that week: 100*5 + 80*3 = 500 + 240 = 740
        XCTAssertFalse(results.isEmpty, "Expected at least one week")
        let totalVolume = results.map(\.totalVolumeKg).reduce(0, +)
        XCTAssertEqual(totalVolume, 740, accuracy: 0.001)
    }

    func testWeeklyVolumeExcludesOldSets() throws {
        let ctx = try makeContext()

        // A set from 10 weeks ago should NOT appear in a last-4-weeks query.
        let tenWeeksAgo = Date().addingTimeInterval(-10 * 7 * 86_400)
        let session = WorkoutSession(startedAt: tenWeeksAgo, templateName: "Old")
        ctx.insert(session)
        let oldSet = PerformedSet(
            orderIndex: 0, exerciseName: "Deadlift",
            exerciseIndex: 0, setIndex: 0,
            weightKg: 200, reps: 1,
            completedAt: tenWeeksAgo
        )
        oldSet.session = session
        ctx.insert(oldSet)
        try ctx.save()

        let engine = AnalyticsEngine(modelContext: ctx)
        let results = engine.weeklyVolume(last: 4)
        XCTAssertTrue(results.isEmpty, "Old sets should not appear in last-4-weeks window")
    }

    // MARK: - exerciseProgression

    func testExerciseProgressionCorrectDataPoints() throws {
        let ctx = try makeContext()

        let cal = Calendar.current
        let now = Date()
        // Two distinct days
        let day1 = cal.date(byAdding: .day, value: -10, to: now)!
        let day2 = cal.date(byAdding: .day, value: -3, to: now)!

        // Day 1: two sets of Bench Press
        let session1 = WorkoutSession(startedAt: day1, templateName: "Push")
        ctx.insert(session1)
        let s1a = PerformedSet(orderIndex: 0, exerciseName: "Bench Press",
                               exerciseIndex: 0, setIndex: 0,
                               weightKg: 80, reps: 5, completedAt: day1)
        s1a.session = session1
        ctx.insert(s1a)
        let s1b = PerformedSet(orderIndex: 1, exerciseName: "Bench Press",
                               exerciseIndex: 0, setIndex: 1,
                               weightKg: 90, reps: 3, completedAt: day1)
        s1b.session = session1
        ctx.insert(s1b)

        // Day 2: one set of Bench Press
        let session2 = WorkoutSession(startedAt: day2, templateName: "Push")
        ctx.insert(session2)
        let s2 = PerformedSet(orderIndex: 0, exerciseName: "Bench Press",
                              exerciseIndex: 0, setIndex: 0,
                              weightKg: 95, reps: 4, completedAt: day2)
        s2.session = session2
        ctx.insert(s2)

        // Irrelevant exercise — should not appear
        let sOther = PerformedSet(orderIndex: 0, exerciseName: "Squat",
                                  exerciseIndex: 1, setIndex: 0,
                                  weightKg: 120, reps: 5, completedAt: day2)
        sOther.session = session2
        ctx.insert(sOther)

        try ctx.save()

        let engine = AnalyticsEngine(modelContext: ctx)
        let points = engine.exerciseProgression(exerciseName: "Bench Press", last: 10)

        XCTAssertEqual(points.count, 2, "Expected 2 data points, one per session day")

        // Sorted ascending — day1 first
        let p1 = points[0]
        XCTAssertEqual(p1.maxWeightKg, 90, accuracy: 0.001)
        XCTAssertEqual(p1.totalVolumeKg, 80*5 + 90*3, accuracy: 0.001) // 400+270=670

        let p2 = points[1]
        XCTAssertEqual(p2.maxWeightKg, 95, accuracy: 0.001)
        XCTAssertEqual(p2.totalVolumeKg, 95*4, accuracy: 0.001) // 380
    }

    func testExerciseProgressionRespectsLastNSessions() throws {
        let ctx = try makeContext()

        let cal = Calendar.current
        let now = Date()

        // Insert 5 sessions on different days
        for i in 1...5 {
            let day = cal.date(byAdding: .day, value: -i * 5, to: now)!
            let session = WorkoutSession(startedAt: day, templateName: "Push")
            ctx.insert(session)
            let s = PerformedSet(orderIndex: 0, exerciseName: "OHP",
                                 exerciseIndex: 0, setIndex: 0,
                                 weightKg: Double(50 + i * 5), reps: 5,
                                 completedAt: day)
            s.session = session
            ctx.insert(s)
        }
        try ctx.save()

        let engine = AnalyticsEngine(modelContext: ctx)
        let points = engine.exerciseProgression(exerciseName: "OHP", last: 3)
        XCTAssertEqual(points.count, 3, "Should return only the last 3 sessions")
    }

    // MARK: - workoutFrequency

    func testWorkoutFrequencyCountsPerWeek() throws {
        let ctx = try makeContext()

        let cal = Calendar.current
        let now = Date()

        // Anchor to the start of THIS week so we get deterministic Monday references
        // regardless of what day the test runs.
        let thisWeekMonday = weekStart(now)
        // Wednesday of this week (Monday + 2 days) — guaranteed same week as Monday
        let thisWeekWed = cal.date(byAdding: .day, value: 2, to: thisWeekMonday)!
        // Wednesday of LAST week — 7 days before thisWeekWed
        let lastWeekWed = cal.date(byAdding: .day, value: -7, to: thisWeekWed)!

        // Insert two sessions in this week and one in last week
        for day in [thisWeekMonday, thisWeekWed, lastWeekWed] {
            let session = WorkoutSession(startedAt: day, templateName: "Session")
            ctx.insert(session)
        }
        try ctx.save()

        let engine = AnalyticsEngine(modelContext: ctx)
        let points = engine.workoutFrequency(last: 1)

        XCTAssertFalse(points.isEmpty)

        let lastWeekStart = weekStart(lastWeekWed)

        if let thisWeek = points.first(where: { $0.weekStart == thisWeekMonday }) {
            XCTAssertEqual(thisWeek.sessionCount, 2, "Expected 2 sessions in this week")
        } else {
            XCTFail("Expected a point for this week (weekStart=\(thisWeekMonday))")
        }

        if let lastWeek = points.first(where: { $0.weekStart == lastWeekStart }) {
            XCTAssertEqual(lastWeek.sessionCount, 1, "Expected 1 session in last week")
        } else {
            XCTFail("Expected a point for last week (weekStart=\(lastWeekStart))")
        }
    }

    // MARK: - exerciseProgression edge cases

    func testExerciseProgressionReturnsEmptyForNonExistentExercise() throws {
        let ctx = try makeContext()
        // Insert a set for a different exercise so the store is not totally empty.
        let session = WorkoutSession(startedAt: Date(), templateName: "Push")
        ctx.insert(session)
        let s = PerformedSet(orderIndex: 0, exerciseName: "Bench Press",
                             exerciseIndex: 0, setIndex: 0,
                             weightKg: 100, reps: 5, completedAt: Date())
        s.session = session
        ctx.insert(s)
        try ctx.save()

        let engine = AnalyticsEngine(modelContext: ctx)
        let points = engine.exerciseProgression(exerciseName: "NonExistentExercise", last: 10)
        XCTAssertEqual(points, [], "Querying for a non-existent exercise should return an empty array")
    }

    // MARK: - estimated1RM

    func testEstimated1RMEpleyFormula() throws {
        let ctx = try makeContext()

        let now = Date()
        let session = WorkoutSession(startedAt: now, templateName: "Test")
        ctx.insert(session)

        // 100 kg × 5 reps → e1RM = 100 * (1 + 5/30) ≈ 116.6̄
        let s = PerformedSet(orderIndex: 0, exerciseName: "Squat",
                             exerciseIndex: 0, setIndex: 0,
                             weightKg: 100, reps: 5, completedAt: now)
        s.session = session
        ctx.insert(s)
        try ctx.save()

        let engine = AnalyticsEngine(modelContext: ctx)
        let points = engine.estimated1RM(exerciseName: "Squat", last: 10)

        XCTAssertEqual(points.count, 1)
        let expected = 100.0 * (1.0 + 5.0 / 30.0)
        XCTAssertEqual(points[0].estimatedMax, expected, accuracy: 0.001)
    }

    func testEstimated1RMTakesMaxPerSession() throws {
        let ctx = try makeContext()

        let now = Date()
        let session = WorkoutSession(startedAt: now, templateName: "Test")
        ctx.insert(session)

        // Two sets in the same session — take the higher e1RM
        // Set A: 100kg×5 → 116.67
        // Set B: 120kg×1 → 120*(1+1/30) = 124.0
        let sA = PerformedSet(orderIndex: 0, exerciseName: "Squat",
                              exerciseIndex: 0, setIndex: 0,
                              weightKg: 100, reps: 5, completedAt: now)
        sA.session = session
        ctx.insert(sA)

        let sB = PerformedSet(orderIndex: 1, exerciseName: "Squat",
                              exerciseIndex: 0, setIndex: 1,
                              weightKg: 120, reps: 1, completedAt: now)
        sB.session = session
        ctx.insert(sB)

        try ctx.save()

        let engine = AnalyticsEngine(modelContext: ctx)
        let points = engine.estimated1RM(exerciseName: "Squat", last: 10)

        XCTAssertEqual(points.count, 1)
        let expected = 120.0 * (1.0 + 1.0 / 30.0)
        XCTAssertEqual(points[0].estimatedMax, expected, accuracy: 0.001)
    }
}
