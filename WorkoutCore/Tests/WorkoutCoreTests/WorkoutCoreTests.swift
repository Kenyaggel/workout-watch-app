import XCTest
@testable import WorkoutCore

@MainActor
final class SessionEngineTests: XCTestCase {

    // MARK: - Helpers

    private func makePlan(restSec: Int = 60) -> SessionPlan {
        SessionPlan(
            templateName: "Test",
            exercises: [
                .init(name: "A", kind: .reps, sets: [
                    .init(targetWeightKg: 50, targetReps: 5, restSec: restSec),
                    .init(targetWeightKg: 50, targetReps: 5, restSec: restSec)
                ]),
                .init(name: "B", kind: .reps, sets: [
                    .init(targetWeightKg: 30, targetReps: 8, restSec: restSec)
                ])
            ]
        )
    }

    private func makeEngine(
        plan: SessionPlan? = nil,
        now: @escaping () -> Date
    ) -> (SessionEngine, InMemorySessionRecorder) {
        let p = plan ?? makePlan()
        let rec = InMemorySessionRecorder()
        let eng = SessionEngine(plan: p, recorder: rec, haptics: NoopHaptics(), nowProvider: now)
        return (eng, rec)
    }

    // MARK: - Tests

    func testStartFromIdleEntersPrepForFirstSet() {
        var t = Date(timeIntervalSince1970: 0)
        let (engine, rec) = makeEngine { t }

        engine.start()

        if case let .prep(startedAt, cursor) = engine.phase {
            XCTAssertEqual(cursor, SetCursor(exerciseIndex: 0, setIndex: 0))
            XCTAssertEqual(startedAt, t)
        } else {
            XCTFail("Expected prep, got \(engine.phase)")
        }
        XCTAssertEqual(rec.startedAt, t)
    }

    func testStartNextExerciseFromInitialPrepEntersFirstSet() {
        var t = Date(timeIntervalSince1970: 0)
        let (engine, _) = makeEngine { t }

        engine.start()
        t = t.addingTimeInterval(10)
        engine.startNextExercise()

        if case let .inSet(cursor, startedAt) = engine.phase {
            XCTAssertEqual(cursor, SetCursor(exerciseIndex: 0, setIndex: 0))
            XCTAssertEqual(startedAt, t)
        } else {
            XCTFail("Expected inSet, got \(engine.phase)")
        }
    }

    func testCompleteSetWithMoreSetsInExerciseEntersRest() {
        var t = Date(timeIntervalSince1970: 0)
        let plan = makePlan(restSec: 90)
        let (engine, rec) = makeEngine(plan: plan) { t }
        engine.start()
        engine.startNextExercise()

        t = t.addingTimeInterval(30)
        engine.completeSet(weightKg: 50, reps: 5, rpe: 7)

        if case let .rest(endsAt, justCompleted, nextCursor) = engine.phase {
            XCTAssertEqual(justCompleted, SetCursor(exerciseIndex: 0, setIndex: 0))
            XCTAssertEqual(nextCursor, SetCursor(exerciseIndex: 0, setIndex: 1))
            XCTAssertEqual(endsAt.timeIntervalSince(t), 90, accuracy: 0.001)
        } else {
            XCTFail("Expected rest, got \(engine.phase)")
        }
        XCTAssertEqual(rec.entries.count, 1)
        XCTAssertEqual(rec.entries.first?.weightKg, 50)
    }

    func testCompleteLastSetOfExerciseEntersPrep() {
        var t = Date(timeIntervalSince1970: 0)
        let (engine, _) = makeEngine { t }
        engine.start()
        engine.startNextExercise()

        // Complete first set → rest
        t = t.addingTimeInterval(30)
        engine.completeSet()
        // Skip rest → into second set
        t = t.addingTimeInterval(60)
        engine.skipRest()
        // Complete second (last) set of exercise A → prep
        t = t.addingTimeInterval(30)
        engine.completeSet()

        if case let .prep(startedAt, nextCursor) = engine.phase {
            XCTAssertEqual(nextCursor, SetCursor(exerciseIndex: 1, setIndex: 0))
            XCTAssertEqual(startedAt, t)
        } else {
            XCTFail("Expected prep, got \(engine.phase)")
        }
    }

    func testStartNextExerciseFromPrep() {
        var t = Date(timeIntervalSince1970: 0)
        let (engine, _) = makeEngine { t }
        engine.start()
        engine.startNextExercise()
        t = t.addingTimeInterval(10); engine.completeSet()
        t = t.addingTimeInterval(10); engine.skipRest()
        t = t.addingTimeInterval(10); engine.completeSet() // → prep
        t = t.addingTimeInterval(10); engine.startNextExercise()

        if case let .inSet(cursor, _) = engine.phase {
            XCTAssertEqual(cursor, SetCursor(exerciseIndex: 1, setIndex: 0))
        } else {
            XCTFail("Expected inSet, got \(engine.phase)")
        }
    }

    func testCompleteFinalSetEntersComplete() {
        var t = Date(timeIntervalSince1970: 0)
        let (engine, rec) = makeEngine { t }
        engine.start()
        engine.startNextExercise()
        t = t.addingTimeInterval(10); engine.completeSet() // ex0 set0 done → rest
        t = t.addingTimeInterval(10); engine.skipRest()    // → ex0 set1
        t = t.addingTimeInterval(10); engine.completeSet() // ex0 set1 done → prep
        t = t.addingTimeInterval(10); engine.startNextExercise() // → ex1 set0
        t = t.addingTimeInterval(10); engine.completeSet() // ex1 set0 (last) done → complete

        if case let .complete(endedAt) = engine.phase {
            XCTAssertEqual(endedAt, t)
        } else {
            XCTFail("Expected complete, got \(engine.phase)")
        }
        XCTAssertEqual(rec.entries.count, 3)
        XCTAssertEqual(rec.endedAt, t)
    }

    func testSkipRestAdvancesImmediately() {
        var t = Date(timeIntervalSince1970: 0)
        let (engine, _) = makeEngine { t }
        engine.start()
        engine.startNextExercise()
        t = t.addingTimeInterval(30); engine.completeSet() // → rest
        t = t.addingTimeInterval(5); engine.skipRest()

        if case let .inSet(cursor, _) = engine.phase {
            XCTAssertEqual(cursor, SetCursor(exerciseIndex: 0, setIndex: 1))
        } else {
            XCTFail("Expected inSet after skipRest, got \(engine.phase)")
        }
    }

    func testRestAutoExpiredAdvancesAtDeadline() {
        var t = Date(timeIntervalSince1970: 0)
        let plan = makePlan(restSec: 60)
        let (engine, _) = makeEngine(plan: plan) { t }
        engine.start()
        engine.startNextExercise()
        t = t.addingTimeInterval(30); engine.completeSet() // rest until t+60

        // Before deadline — should be no-op
        t = t.addingTimeInterval(30) // halfway
        engine.restAutoExpired()
        XCTAssertTrue({
            if case .rest = engine.phase { return true } else { return false }
        }())

        // At deadline — should advance
        t = t.addingTimeInterval(30) // exactly at deadline
        engine.restAutoExpired()
        if case let .inSet(cursor, _) = engine.phase {
            XCTAssertEqual(cursor, SetCursor(exerciseIndex: 0, setIndex: 1))
        } else {
            XCTFail("Expected inSet after rest expiry, got \(engine.phase)")
        }
    }

    func testEndWorkoutEarly() {
        var t = Date(timeIntervalSince1970: 0)
        let (engine, rec) = makeEngine { t }
        engine.start()
        engine.startNextExercise()
        t = t.addingTimeInterval(10); engine.completeSet() // → rest
        t = t.addingTimeInterval(5); engine.endWorkout()

        if case .complete = engine.phase {
            // ok
        } else {
            XCTFail("Expected complete, got \(engine.phase)")
        }
        XCTAssertNotNil(rec.endedAt)
    }

    func testStartWithEmptyPlanGoesStraightToComplete() {
        var t = Date(timeIntervalSince1970: 0)
        let plan = SessionPlan(templateName: "Empty", exercises: [])
        let (engine, _) = makeEngine(plan: plan) { t }
        engine.start()
        if case .complete = engine.phase { } else {
            XCTFail("Expected complete for empty plan, got \(engine.phase)")
        }
    }

    func testCompleteSetIgnoredWhenNotInSet() {
        var t = Date(timeIntervalSince1970: 0)
        let (engine, _) = makeEngine { t }
        // Idle: completeSet should be a no-op
        engine.completeSet(weightKg: 100, reps: 100)
        if case .idle = engine.phase { } else {
            XCTFail("completeSet from idle should be no-op")
        }
    }

    func testSkipRestIgnoredWhenNotResting() {
        var t = Date(timeIntervalSince1970: 0)
        let (engine, _) = makeEngine { t }
        engine.start()
        engine.skipRest() // in-set, should be no-op
        if case .prep = engine.phase { } else {
            XCTFail("skipRest from prep should be no-op")
        }
    }

    func testSetNumberAndTotalSets() {
        let plan = makePlan()
        let (engine, _) = makeEngine(plan: plan) { Date() }
        XCTAssertEqual(engine.totalSets, 3)
        XCTAssertEqual(engine.setNumber(of: SetCursor(exerciseIndex: 0, setIndex: 0)), 1)
        XCTAssertEqual(engine.setNumber(of: SetCursor(exerciseIndex: 0, setIndex: 1)), 2)
        XCTAssertEqual(engine.setNumber(of: SetCursor(exerciseIndex: 1, setIndex: 0)), 3)
    }

    func testSuccessorSkipsEmptyExercise() {
        let plan = SessionPlan(
            templateName: "T",
            exercises: [
                .init(name: "A", kind: .reps, sets: [.init(restSec: 30)]),
                .init(name: "Empty", kind: .reps, sets: []),
                .init(name: "C", kind: .reps, sets: [.init(restSec: 30)])
            ]
        )
        let succ = plan.successor(of: SetCursor(exerciseIndex: 0, setIndex: 0))
        XCTAssertEqual(succ?.next, SetCursor(exerciseIndex: 2, setIndex: 0))
        XCTAssertEqual(succ?.crossesExercise, true)
    }

    func testTemplatePlanUsesPlannedExerciseRestForEverySet() {
        let exercise = Exercise(
            name: "Bench",
            kind: .reps,
            defaultRestSec: 45,
            defaultTargetReps: 8
        )
        let template = WorkoutTemplate(name: "Strength")
        let plannedExercise = PlannedExercise(orderIndex: 0, exercise: exercise, restSec: 120)
        let firstSet = PlannedSet(orderIndex: 0, targetWeightKg: 60, targetReps: 8)
        let secondSet = PlannedSet(orderIndex: 1, targetWeightKg: 60, targetReps: 8)

        plannedExercise.sets = [firstSet, secondSet]
        template.plannedExercises = [plannedExercise]

        let plan = SessionPlan.from(template: template)

        XCTAssertEqual(plan.exercises.first?.sets.map(\.restSec), [120, 120])
    }
}
