import XCTest
@testable import WorkoutCore

/// The rules replayed over months of training against a simulated lifter.
///
/// Unit tests prove each rule in isolation; these prove the rules *composed over time* do
/// not do the two things a progression scheme can do wrong — run away above what the lifter
/// can actually lift, or ratchet down forever. The store holds under ten real sessions, so
/// a simulated lifter is the only way to see the long run today; swap in
/// `CoachStore.sessionSnapshots` once there is real history.
final class CoachBacktestTests: XCTestCase {

    private let benchID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
    private let workoutID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private let slotID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!

    private func day(_ n: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000).addingTimeInterval(TimeInterval(n) * 3 * 86_400)
    }

    private func slot(targets: [TargetSnapshot], step: Double? = nil) -> SlotSnapshot {
        SlotSnapshot(
            slotID: slotID, workoutID: workoutID, workoutName: "Push Day",
            exerciseID: benchID, exerciseName: "Bench Press", kind: .reps,
            progressionStep: step, targets: targets, orderIndex: 0, peerSlotOrderIndexes: [0]
        )
    }

    /// A lifter who completes every set at or below `capacity` and misses reps above it.
    /// Deterministic — no randomness, so a failure is always reproducible.
    private func simulate(
        sessions count: Int,
        startingAt start: Double,
        capacity: @escaping (Int) -> Double,
        setCount: Int = 3,
        reps: Int = 8,
        step: Double? = nil,
        acceptance: CoachBacktest.Acceptance = .acceptsEverything,
        config: CoachConfig = CoachConfig()
    ) -> CoachBacktest.Report {
        var targets = Array(repeating: TargetSnapshot(weightKg: start, reps: reps), count: setCount)
        var sessions: [SessionSnapshot] = []
        var working = slot(targets: targets, step: step)

        for index in 0..<count {
            let weight = targets[0].weightKg ?? start
            let achieved = weight <= capacity(index) ? reps : reps - 2
            let performed = (0..<setCount).map { setIndex in
                PerformedSnapshot(
                    id: UUID(uuidString: String(format: "00000000-0000-0000-0A%02d-%012d", setIndex, index))!,
                    exerciseID: benchID, exerciseName: "Bench Press",
                    exerciseIndex: 0, setIndex: setIndex, orderIndex: setIndex,
                    weightKg: weight, reps: achieved,
                    completedAt: day(index),
                    target: targets[setIndex],
                    plannedSetCount: setCount
                )
            }
            sessions.append(SessionSnapshot(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0B00-%012d", index))!,
                workoutID: workoutID, workoutName: "Push Day",
                startedAt: day(index), endedAt: day(index).addingTimeInterval(3_600),
                sets: performed
            ))

            // Replay just this session to learn the next prescription.
            working.targets = targets
            let report = CoachBacktest.replay(
                slot: slot(targets: targets, step: step),
                sessions: sessions,
                acceptance: acceptance,
                config: config
            )
            if let last = report.steps.last, last.applied {
                targets = last.output.proposedTargets
            }
        }

        return CoachBacktest.replay(
            slot: slot(targets: Array(repeating: TargetSnapshot(weightKg: start, reps: reps), count: setCount), step: step),
            sessions: sessions,
            acceptance: acceptance,
            config: config
        )
    }

    // MARK: - The two ways this can go wrong

    func testTheLoadConvergesOnWhatTheLifterCanActuallyDoAndStaysThere() throws {
        let capacity = 80.0
        let report = simulate(sessions: 40, startingAt: 60, capacity: { _ in capacity })
        let anchors = report.anchors

        print("\n--- convergence, capacity \(capacity) kg ---\n" + report.trace(dimension: .load))

        let settled = anchors.suffix(20)
        let high = try XCTUnwrap(settled.max())
        let low = try XCTUnwrap(settled.min())

        XCTAssertLessThanOrEqual(high, capacity + 2.5,
                                 "the rules must never prescribe more than one step past what the lifter can do")
        XCTAssertGreaterThan(low, capacity * 0.75,
                             "and must not ratchet down away from it either")
        XCTAssertGreaterThan(report.count(of: .increase), 5, "it has to actually climb to get there")
        XCTAssertGreaterThan(report.count(of: .deload), 0, "and back off once it overshoots")
    }

    func testAStrongerLifterKeepsClimbingWithoutEverStalling() {
        // Capacity rises faster than 2.5 kg a session, so nothing should ever stall.
        let report = simulate(sessions: 20, startingAt: 60, capacity: { 60 + Double($0) * 5 })

        XCTAssertEqual(report.count(of: .deload), 0)
        XCTAssertEqual(report.count(of: .holdFirstStall), 0)
        XCTAssertEqual(report.anchors.last, 60 + 20 * 2.5)
    }

    func testTheLoadNeverRunsAwayNorCollapsesOverAYearOfTraining() throws {
        // A lifter whose capacity drifts up slowly, with a six-session dip in the middle —
        // illness, a bad month. The rules must follow it down and back up.
        let report = simulate(sessions: 120, startingAt: 60, capacity: { index in
            let base = 70 + Double(index) * 0.25
            return (40...46).contains(index) ? base * 0.7 : base
        })
        let anchors = report.anchors

        print("\n--- a year of training ---\n" + report.trace(dimension: .load))

        for anchor in anchors {
            XCTAssertGreaterThan(anchor, 0, "nothing the coach emits is ever zero or negative")
            XCTAssertLessThan(anchor, 200, "and nothing runs away")
        }
        let final = try XCTUnwrap(anchors.last)
        XCTAssertGreaterThan(final, 80, "a year of progress should show up")
        XCTAssertLessThan(final, 115, "but not more than the lifter earned")
    }

    func testALifterWhoNeverOpensThePhoneStillTrainsSafely() {
        // Deloads hold for review, so this lifter just repeats a weight they cannot lift.
        // That is the intended failure mode — it is safe, merely unproductive — and it must
        // not silently keep adding load.
        let report = simulate(
            sessions: 30, startingAt: 60, capacity: { _ in 70 },
            acceptance: .automaticOnly
        )
        let anchors = report.anchors

        XCTAssertLessThanOrEqual(anchors.max() ?? 0, 72.5,
                                 "an unapproved deload must never become an increase")
        XCTAssertEqual(report.count(of: .increase), 5)
        XCTAssertGreaterThan(report.count(of: .deload), 0,
                             "the proposal is still made every session — it is just never applied")
    }

    func testABodyweightLiftClimbsRepsAndThenAsksAHuman() {
        var targets = Array(repeating: TargetSnapshot(reps: 10), count: 3)
        var sessions: [SessionSnapshot] = []

        for index in 0..<30 {
            let target = targets[0]
            let performed = (0..<3).map { setIndex in
                PerformedSnapshot(
                    id: UUID(uuidString: String(format: "00000000-0000-0000-0C%02d-%012d", setIndex, index))!,
                    exerciseID: benchID, exerciseName: "Push-up",
                    exerciseIndex: 0, setIndex: setIndex, orderIndex: setIndex,
                    reps: target.reps, completedAt: day(index),
                    target: target, plannedSetCount: 3
                )
            }
            sessions.append(SessionSnapshot(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0D00-%012d", index))!,
                workoutID: workoutID, workoutName: "Push Day",
                startedAt: day(index), endedAt: day(index).addingTimeInterval(3_600),
                sets: performed
            ))
            let report = CoachBacktest.replay(
                slot: slot(targets: targets), sessions: sessions, acceptance: .acceptsEverything
            )
            if let last = report.steps.last, last.applied {
                targets = last.output.proposedTargets
            }
        }

        XCTAssertEqual(targets[0].reps, 30,
                       "reps climb one at a time and then stop — 30 a set is where the coach hands over")
    }
}
