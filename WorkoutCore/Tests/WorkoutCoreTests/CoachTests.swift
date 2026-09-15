import XCTest
@testable import WorkoutCore

/// The Coach is a pure function, so every case here is plain Swift with synthetic history
/// and an injected `asOf` — no SwiftData, no clock.
final class CoachTests: XCTestCase {

    // MARK: - Builders

    private let workoutID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private let benchID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
    private let slotID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!

    private func day(_ n: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000).addingTimeInterval(TimeInterval(n) * 86_400)
    }

    private func slot(
        kind: ExerciseKind? = .reps,
        step: Double? = nil,
        targets: [TargetSnapshot],
        orderIndex: Int = 0,
        peers: [Int] = []
    ) -> SlotSnapshot {
        SlotSnapshot(
            slotID: slotID,
            workoutID: workoutID,
            workoutName: "Push Day",
            exerciseID: benchID,
            exerciseName: "Bench Press",
            kind: kind,
            progressionStep: step,
            targets: targets,
            orderIndex: orderIndex,
            peerSlotOrderIndexes: peers
        )
    }

    private func session(
        _ n: Int,
        sets: [PerformedSnapshot],
        workoutID: UUID? = nil,
        id: UUID? = nil
    ) -> SessionSnapshot {
        SessionSnapshot(
            id: id ?? UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n + 1))!,
            workoutID: workoutID ?? self.workoutID,
            workoutName: "Push Day",
            startedAt: day(n),
            endedAt: day(n).addingTimeInterval(3_600),
            sets: sets
        )
    }

    /// One performed set that hit its target exactly, unless overridden.
    private func perf(
        _ setIndex: Int,
        weight: Double? = nil,
        reps: Int? = nil,
        duration: Int? = nil,
        distance: Double? = nil,
        rpe: Int? = nil,
        target: TargetSnapshot? = nil,
        plannedSetCount: Int? = nil,
        exerciseID: UUID? = nil,
        exerciseName: String = "Bench Press",
        exerciseIndex: Int = 0,
        orderIndex: Int? = nil,
        day n: Int = 0
    ) -> PerformedSnapshot {
        PerformedSnapshot(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0001-%03d%09d", exerciseIndex, setIndex + 1))!,
            exerciseID: exerciseID ?? benchID,
            exerciseName: exerciseName,
            exerciseIndex: exerciseIndex,
            setIndex: setIndex,
            orderIndex: orderIndex ?? setIndex,
            weightKg: weight,
            reps: reps,
            durationSec: duration,
            distanceM: distance,
            rpe: rpe,
            completedAt: day(n),
            target: target,
            plannedSetCount: plannedSetCount
        )
    }

    private func propose(
        slot: SlotSnapshot,
        sessions: [SessionSnapshot],
        asOf: Int = 1,
        config: CoachConfig = CoachConfig()
    ) -> CoachOutput {
        Coach.propose(CoachInput(slot: slot, sessions: sessions, asOf: day(asOf), config: config))
    }

    /// Three sets of 60 kg × 8, all met.
    private func metSession(_ n: Int, weight: Double = 60, reps: Int = 8, rpe: Int? = nil, count: Int = 3) -> SessionSnapshot {
        let target = TargetSnapshot(weightKg: weight, reps: reps)
        return session(n, sets: (0..<count).map {
            perf($0, weight: weight, reps: reps, rpe: rpe, target: target, plannedSetCount: count, day: n)
        })
    }

    private func missedSession(_ n: Int, weight: Double = 60, reps: Int = 8, missedReps: Int = 6, rpe: Int? = nil) -> SessionSnapshot {
        let target = TargetSnapshot(weightKg: weight, reps: reps)
        return session(n, sets: [
            perf(0, weight: weight, reps: reps, rpe: rpe, target: target, plannedSetCount: 3, day: n),
            perf(1, weight: weight, reps: reps, rpe: rpe, target: target, plannedSetCount: 3, day: n),
            perf(2, weight: weight, reps: missedReps, rpe: rpe, target: target, plannedSetCount: 3, day: n)
        ])
    }

    private var threeByEight: [TargetSnapshot] {
        Array(repeating: TargetSnapshot(weightKg: 60, reps: 8), count: 3)
    }

    // MARK: - Double progression baseline

    func testEveryTargetMetProposesExactlyOneStepUp() {
        let out = propose(slot: slot(targets: threeByEight), sessions: [metSession(0)])

        XCTAssertEqual(out.outcome, .increase)
        XCTAssertEqual(out.dimension, .load)
        XCTAssertEqual(out.delta, 2.5)
        XCTAssertEqual(out.proposedTargets.map(\.weightKg), [62.5, 62.5, 62.5])
        XCTAssertEqual(out.applyClass, .automatic, "a single step in the usual direction applies itself")
    }

    func testMissingAnySetRepeatsTheSameTargets() {
        let out = propose(slot: slot(targets: threeByEight), sessions: [missedSession(0)])

        XCTAssertEqual(out.outcome, .holdFirstStall)
        XCTAssertEqual(out.delta, 0)
        XCTAssertEqual(out.proposedTargets, threeByEight, "a hold returns the current targets unchanged")
        XCTAssertEqual(out.applyClass, .noOp, "the rows already hold these numbers — nothing to write")
    }

    func testTwoConsecutiveStallsProposeADeloadForReview() {
        let out = propose(slot: slot(targets: threeByEight), sessions: [missedSession(1), missedSession(0)], asOf: 2)

        XCTAssertEqual(out.outcome, .deload)
        XCTAssertEqual(out.evidence.consecutiveStalls, 2)
        XCTAssertEqual(out.applyClass, .pendingReview, "cutting someone's load unasked is a larger claim than adding 2.5 kg")
    }

    func testDoingMoreThanTargetStillEarnsExactlyOneStep() {
        let target = TargetSnapshot(weightKg: 60, reps: 8)
        let s = session(0, sets: (0..<3).map { perf($0, weight: 60, reps: 12, target: target, plannedSetCount: 3) })

        let out = propose(slot: slot(targets: threeByEight), sessions: [s])
        XCTAssertEqual(out.outcome, .increase)
        XCTAssertEqual(out.delta, 2.5, "step size is fixed; beating the target does not earn a bigger jump")
    }

    func testRepsAtALighterLoadIsAMissNotAHit() {
        let target = TargetSnapshot(weightKg: 60, reps: 8)
        let s = session(0, sets: (0..<3).map { perf($0, weight: 55, reps: 8, target: target, plannedSetCount: 3) })

        let out = propose(slot: slot(targets: threeByEight), sessions: [s])
        XCTAssertEqual(out.outcome, .holdFirstStall, "8 reps at 55 against a 60x8 target is not the prescribed set")
    }

    // MARK: - Deload arithmetic

    func testDeloadRoundsToTheNearestWholeNumberOfSteps() {
        // 10% of 60 is 6.0; at a 2.5 step that is 2.4 steps, nearest 2 -> -5.0 -> 55.0 (-8.3%).
        // Rounding up would give 52.5, a 12.5% cut presented to the lifter as "about ten percent".
        let out = propose(slot: slot(targets: threeByEight), sessions: [missedSession(1), missedSession(0)], asOf: 2)

        XCTAssertEqual(out.outcome, .deload)
        XCTAssertEqual(out.delta, -5.0)
        XCTAssertEqual(out.proposedTargets.map(\.weightKg), [55.0, 55.0, 55.0])
    }

    func testDeloadIsNeverANoOpEvenWhenTenPercentIsBelowOneStep() {
        let targets = Array(repeating: TargetSnapshot(weightKg: 20, reps: 8), count: 3)
        let sessions = [
            missedSession(1, weight: 20), missedSession(0, weight: 20)
        ]
        let out = propose(slot: slot(targets: targets), sessions: sessions, asOf: 2)

        XCTAssertEqual(out.outcome, .deload)
        XCTAssertEqual(out.delta, -2.5, "10% of 20 is 2.0, under one step — it still moves a full step")
    }

    func testDeloadRefusesWhenTheLadderIsTooCoarseToHelp() {
        let targets = [TargetSnapshot(weightKg: 7.5, reps: 8)]
        let sessions = [missedSession(1, weight: 7.5), missedSession(0, weight: 7.5)]
        let out = propose(slot: slot(targets: targets), sessions: sessions, asOf: 2)

        XCTAssertEqual(out.outcome, .holdAtFloor)
        XCTAssertEqual(out.proposedTargets.map(\.weightKg), [7.5], "targets are left alone")
        XCTAssertEqual(out.applyClass, .pendingReview, "the coach says out loud that it is jammed")
    }

    func testNothingTheCoachEmitsIsEverZeroOrNegative() {
        // A shallow backoff set must not be driven through the floor by the anchor's delta.
        let targets = [
            TargetSnapshot(weightKg: 100, reps: 5),
            TargetSnapshot(weightKg: 5, reps: 12)
        ]
        let target100 = TargetSnapshot(weightKg: 100, reps: 5)
        let target5 = TargetSnapshot(weightKg: 5, reps: 12)
        let stall = { (n: Int) in
            self.session(n, sets: [
                self.perf(0, weight: 100, reps: 3, target: target100, plannedSetCount: 2, day: n),
                self.perf(1, weight: 5, reps: 12, target: target5, plannedSetCount: 2, day: n)
            ])
        }
        let out = propose(slot: slot(targets: targets), sessions: [stall(1), stall(0)], asOf: 2)

        XCTAssertEqual(out.outcome, .deload)
        for weight in out.proposedTargets.compactMap(\.weightKg) {
            XCTAssertGreaterThan(weight, 0)
            XCTAssertTrue(weight.isFinite)
        }
    }

    // MARK: - RPE is a veto on direction, never a throttle on size

    func testRPENineOnASuccessfulSessionTurnsIncreaseIntoHold() {
        let out = propose(slot: slot(targets: threeByEight), sessions: [metSession(0, rpe: 9)])

        XCTAssertEqual(out.outcome, .holdRPEVeto)
        XCTAssertEqual(out.delta, 0)
        XCTAssertEqual(out.applyClass, .noOp)
    }

    func testRPETenOnAFirstStallEscalatesToDeload() {
        let out = propose(slot: slot(targets: threeByEight), sessions: [missedSession(0, rpe: 10)])

        XCTAssertEqual(out.outcome, .deload)
        XCTAssertEqual(out.applyClass, .pendingReview)
    }

    func testRPEBelowNineChangesNothing() {
        let out = propose(slot: slot(targets: threeByEight), sessions: [metSession(0, rpe: 8)])
        XCTAssertEqual(out.outcome, .increase)
    }

    func testAbsentRPEChangesNothing() {
        let out = propose(slot: slot(targets: threeByEight), sessions: [metSession(0, rpe: nil)])
        XCTAssertEqual(out.outcome, .increase, "most sessions carry no RPE at all and the rules must work on them")
        XCTAssertNil(out.evidence.maxRPE)
    }

    func testTheVetoReadsTheMaximumRPEAcrossTheSlotNotTheLastOne() {
        let target = TargetSnapshot(weightKg: 60, reps: 8)
        let s = session(0, sets: [
            perf(0, weight: 60, reps: 8, rpe: 10, target: target, plannedSetCount: 3),
            perf(1, weight: 60, reps: 8, rpe: 7, target: target, plannedSetCount: 3),
            perf(2, weight: 60, reps: 8, rpe: 7, target: target, plannedSetCount: 3)
        ])
        let out = propose(slot: slot(targets: threeByEight), sessions: [s])

        XCTAssertEqual(out.evidence.maxRPE, 10)
        XCTAssertEqual(out.outcome, .holdRPEVeto, "a mean of 8.0 would have let this through")
    }

    func testRPEIsReadOnlyFromTheSetsThatCarryIt() {
        let target = TargetSnapshot(weightKg: 60, reps: 8)
        let s = session(0, sets: [
            perf(0, weight: 60, reps: 8, rpe: nil, target: target, plannedSetCount: 3),
            perf(1, weight: 60, reps: 8, rpe: nil, target: target, plannedSetCount: 3),
            perf(2, weight: 60, reps: 8, rpe: 9, target: target, plannedSetCount: 3)
        ])
        let out = propose(slot: slot(targets: threeByEight), sessions: [s])

        XCTAssertEqual(out.evidence.maxRPE, 9, "nil is 'not recorded', never 'easy' — it is not imputed")
        XCTAssertEqual(out.outcome, .holdRPEVeto)
    }

    // MARK: - Dimensions

    func testABodyweightRepsSlotProgressesRepsNotLoad() {
        let targets = Array(repeating: TargetSnapshot(reps: 10), count: 3)
        let target = TargetSnapshot(reps: 10)
        let s = session(0, sets: (0..<3).map {
            perf($0, reps: 10, target: target, plannedSetCount: 3, exerciseName: "Push-up")
        })
        let out = propose(
            slot: slot(targets: targets),
            sessions: [s]
        )

        XCTAssertEqual(out.dimension, .reps)
        XCTAssertEqual(out.delta, 1)
        XCTAssertEqual(out.proposedTargets.map(\.reps), [11, 11, 11])
    }

    func testATimedSlotProgressesDurationEvenWhenItCarriesAWeight() {
        // A weighted plank must never switch to the load axis: Exercise.progressionStep is
        // one scalar, so a step of 5 authored as seconds would start adding 5 kilograms.
        let targets = [TargetSnapshot(weightKg: 10, durationSec: 45)]
        let target = targets[0]
        let s = session(0, sets: [
            perf(0, weight: 10, duration: 45, target: target, plannedSetCount: 1, exerciseName: "Plank")
        ])
        let out = propose(slot: slot(kind: .timed, targets: targets), sessions: [s])

        XCTAssertEqual(out.dimension, .duration)
        XCTAssertEqual(out.delta, 5)
        XCTAssertEqual(out.proposedTargets.map(\.durationSec), [50])
        XCTAssertEqual(out.proposedTargets.map(\.weightKg), [10], "the plate is left exactly where it was")
    }

    func testSheddingThePlateOnAWeightedPlankIsAMiss() {
        let targets = [TargetSnapshot(weightKg: 20, durationSec: 60)]
        let s = session(0, sets: [
            perf(0, weight: 10, duration: 60, target: targets[0], plannedSetCount: 1, exerciseName: "Plank")
        ])
        let out = propose(slot: slot(kind: .timed, targets: targets), sessions: [s])

        XCTAssertEqual(out.outcome, .holdFirstStall, "60s at 10 kg does not meet 60s at 20 kg")
    }

    func testADistanceSlotProgressesDistance() {
        let targets = [TargetSnapshot(distanceM: 1_000)]
        let s = session(0, sets: [
            perf(0, distance: 1_000, target: targets[0], plannedSetCount: 1, exerciseName: "Row")
        ])
        let out = propose(slot: slot(kind: .distance, targets: targets), sessions: [s])

        XCTAssertEqual(out.dimension, .distance)
        XCTAssertEqual(out.proposedTargets.map(\.distanceM), [1_100])
    }

    // MARK: - Partial and abandoned sessions

    func testAShortSessionWithNoMissIsInvisibleAndTheWalkPassesThroughIt() {
        let target = TargetSnapshot(weightKg: 60, reps: 8)
        let cutShort = session(1, sets: [
            perf(0, weight: 60, reps: 8, target: target, plannedSetCount: 3, day: 1),
            perf(1, weight: 60, reps: 8, target: target, plannedSetCount: 3, day: 1)
        ])
        let out = propose(slot: slot(targets: threeByEight), sessions: [cutShort, metSession(0)], asOf: 2)

        XCTAssertEqual(out.outcome, .increase, "two perfect sets then the fire alarm says nothing about set four")
    }

    func testAShortSessionThatContainsAMissIsAFullStall() {
        let target = TargetSnapshot(weightKg: 60, reps: 8)
        let bailed = session(1, sets: [
            perf(0, weight: 60, reps: 4, target: target, plannedSetCount: 3, day: 1)
        ])
        let out = propose(slot: slot(targets: threeByEight), sessions: [bailed, metSession(0)], asOf: 2)

        XCTAssertEqual(out.outcome, .holdFirstStall, "the load beat you and you left because of it")
    }

    func testTheSlotIsInvisibleWhenItWasNotTrainedAtAll() {
        let other = session(0, sets: [
            perf(0, weight: 40, reps: 10, plannedSetCount: 1, exerciseID: UUID(), exerciseName: "Curl")
        ])
        let out = propose(slot: slot(targets: threeByEight), sessions: [other])

        XCTAssertEqual(out.outcome, .insufficientData)
        XCTAssertEqual(out.applyClass, .noOp)
    }

    func testTheHistoricalPlannedSetCountIsUsedNotTodays() {
        // Run as 3 of 4 with no miss. If the slot's *current* 3 sets were used, this would
        // read as a complete session and silently earn an increase.
        let target = TargetSnapshot(weightKg: 60, reps: 8)
        let s = session(0, sets: (0..<3).map {
            perf($0, weight: 60, reps: 8, target: target, plannedSetCount: 4)
        })
        let out = propose(slot: slot(targets: threeByEight), sessions: [s])

        XCTAssertNotEqual(out.outcome, .increase)
        XCTAssertEqual(out.outcome, .holdNoComparableHistory)
    }

    // MARK: - Slot scope and lift identity

    func testHistorySurvivesTheSlotBeingReordered() {
        // The session recorded exerciseIndex 0; the slot now sits at orderIndex 3.
        let out = propose(
            slot: slot(targets: threeByEight, orderIndex: 3, peers: [3]),
            sessions: [metSession(0)]
        )
        XCTAssertEqual(out.outcome, .increase, "scope is (workout, exercise) — never position")
    }

    func testTwoSlotsOfTheSameExerciseInOneWorkoutKeepSeparateHistories() {
        let heavyTarget = TargetSnapshot(weightKg: 100, reps: 5)
        let backoffTarget = TargetSnapshot(weightKg: 70, reps: 12)
        let s = session(0, sets: [
            perf(0, weight: 100, reps: 5, target: heavyTarget, plannedSetCount: 1, exerciseIndex: 0),
            perf(0, weight: 70, reps: 10, target: backoffTarget, plannedSetCount: 1, exerciseIndex: 1)
        ])

        let heavy = propose(
            slot: slot(targets: [heavyTarget], orderIndex: 0, peers: [0, 1]),
            sessions: [s]
        )
        let backoff = propose(
            slot: slot(targets: [backoffTarget], orderIndex: 1, peers: [0, 1]),
            sessions: [s]
        )

        XCTAssertEqual(heavy.outcome, .increase, "the heavy single was met")
        XCTAssertEqual(backoff.outcome, .holdFirstStall, "the backoff set missed 12 reps and must not read the heavy set's success")
    }

    func testASetCarryingADifferentIdentityIsNeverNameMatched() {
        let target = TargetSnapshot(weightKg: 60, reps: 8)
        let impostor = session(0, sets: (0..<3).map {
            perf($0, weight: 60, reps: 8, target: target, plannedSetCount: 3, exerciseID: UUID())
        })
        let out = propose(slot: slot(targets: threeByEight), sessions: [impostor])

        XCTAssertEqual(out.outcome, .insufficientData, "same name, different lift — pooling them is what the ADR removes")
    }

    func testIdentitylessLegacyRowsFallBackToTheNameAndForceReview() {
        let target = TargetSnapshot(weightKg: 60, reps: 8)
        let legacy = session(0, sets: (0..<3).map {
            PerformedSnapshot(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0009-%012d", $0))!,
                exerciseID: nil, exerciseName: "Bench Press",
                exerciseIndex: 0, setIndex: $0, orderIndex: $0,
                weightKg: 60, reps: 8, completedAt: day(0),
                target: target, plannedSetCount: 3
            )
        })
        let out = propose(slot: slot(targets: threeByEight), sessions: [legacy])

        XCTAssertEqual(out.outcome, .increase)
        XCTAssertTrue(out.flags.contains(.identityMatchedByNameOnly))
        XCTAssertEqual(out.applyClass, .pendingReview, "a name-only match is not confident enough to write itself")
    }

    // MARK: - Walk terminators

    func testThreeSessionsSyncingAtOnceDoNotStackThreeIncreases() {
        // All three were run at 60. After the first apply the slot reads 62.5, so every one
        // of them is now a session against a different prescription.
        let out = propose(
            slot: slot(targets: Array(repeating: TargetSnapshot(weightKg: 62.5, reps: 8), count: 3)),
            sessions: [metSession(2), metSession(1), metSession(0)],
            asOf: 3
        )
        XCTAssertEqual(out.outcome, .holdNoComparableHistory)
        XCTAssertEqual(out.delta, 0)
    }

    func testAHitAgainstALighterPrescriptionNeverEarnsAnIncreaseAtTheHeavierOne() {
        let out = propose(
            slot: slot(targets: threeByEight),
            sessions: [metSession(0, weight: 55)],
            asOf: 1
        )
        XCTAssertEqual(out.outcome, .holdNoComparableHistory)
    }

    // MARK: - The e1RM seed

    func testABlankSlotIsSeededFromTheBestEstimatedMaxElsewhere() {
        let otherWorkout = UUID()
        let heavy = SessionSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-000E-000000000001")!,
            workoutID: otherWorkout, workoutName: "Heavy Day",
            startedAt: day(-10), endedAt: day(-10).addingTimeInterval(3_600),
            sets: [perf(0, weight: 100, reps: 5, plannedSetCount: 1, day: -10)]
        )
        let targets = [
            TargetSnapshot(reps: 5), TargetSnapshot(reps: 8), TargetSnapshot(reps: 12)
        ]
        let out = propose(slot: slot(targets: targets), sessions: [heavy])

        XCTAssertEqual(out.outcome, .seedFromE1RM)
        XCTAssertEqual(out.dimension, .load)
        XCTAssertEqual(out.applyClass, .pendingReview, "a human confirms the first number; the ladder earns every one after it")
        // e1RM = 100 * (1 + 5/30) = 116.667, held back 10%, inverse-Epley per set, floored to 2.5.
        XCTAssertEqual(out.proposedTargets.map(\.weightKg), [90.0, 82.5, 75.0],
                       "each set uses its own rep target, so the seed lands as a descending shape")
    }

    func testTheSeedRefusesToOverwriteAnAuthoredWeight() {
        let otherWorkout = UUID()
        let heavy = SessionSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-000E-000000000002")!,
            workoutID: otherWorkout, workoutName: "Heavy Day",
            startedAt: day(-10), endedAt: day(-10).addingTimeInterval(3_600),
            sets: [perf(0, weight: 100, reps: 5, plannedSetCount: 1, day: -10)]
        )
        let out = propose(slot: slot(targets: threeByEight), sessions: [heavy])

        XCTAssertEqual(out.outcome, .insufficientData)
        XCTAssertEqual(out.proposedTargets, threeByEight, "if the lifter typed 60 kg, leave it alone")
    }

    func testAHighRepSetNeverSeedsAnEstimatedMax() {
        // Epley is fitted near a true single; a 30-rep set implies a 2x inflation the safety
        // factor cannot absorb.
        let otherWorkout = UUID()
        let highRep = SessionSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-000E-000000000003")!,
            workoutID: otherWorkout, workoutName: "Conditioning",
            startedAt: day(-10), endedAt: day(-10).addingTimeInterval(3_600),
            sets: [perf(0, weight: 40, reps: 30, plannedSetCount: 1, day: -10)]
        )
        let out = propose(slot: slot(targets: [TargetSnapshot(reps: 5)]), sessions: [highRep])

        XCTAssertEqual(out.outcome, .insufficientData)
    }

    func testWithNoHistoryAnywhereTheCoachInventsNothing() {
        let out = propose(slot: slot(targets: [TargetSnapshot(reps: 5)]), sessions: [])

        XCTAssertEqual(out.outcome, .insufficientData)
        XCTAssertEqual(out.applyClass, .noOp)
        XCTAssertEqual(out.delta, 0)
    }

    // MARK: - Sanitization and ceilings

    func testAFatFingeredProgressionStepIsRejectedNotClamped() {
        let out = propose(slot: slot(step: 500, targets: threeByEight), sessions: [metSession(0)])

        XCTAssertEqual(out.delta, 2.5, "500 falls back to the dimension default, it is not honoured at a bound")
        XCTAssertTrue(out.flags.contains(.stepSanitized))
        XCTAssertEqual(out.applyClass, .pendingReview, "a value that nonsensical must not reach the bar unattended")
    }

    func testAReasonableStepOverrideIsHonoured() {
        let out = propose(slot: slot(step: 1.25, targets: threeByEight), sessions: [metSession(0)])

        XCTAssertEqual(out.delta, 1.25)
        XCTAssertEqual(out.proposedTargets.map(\.weightKg), [61.25, 61.25, 61.25])
        XCTAssertEqual(out.applyClass, .automatic)
    }

    func testACorruptStoredTargetIsLeftAloneRatherThanProgressed() {
        let targets = [TargetSnapshot(weightKg: -5, reps: 8), TargetSnapshot(weightKg: 60, reps: 8)]
        let t1 = targets[1]
        let s = session(0, sets: [
            perf(0, reps: 8, target: targets[0], plannedSetCount: 2),
            perf(1, weight: 60, reps: 8, target: t1, plannedSetCount: 2)
        ])
        let out = propose(slot: slot(targets: targets), sessions: [s])

        XCTAssertEqual(out.proposedTargets[0].weightKg, -5, "a negative stored target is never turned into a slightly less negative one")
        for weight in out.proposedTargets.compactMap(\.weightKg) where weight > 0 {
            XCTAssertTrue(weight.isFinite)
        }
    }

    func testRepsStopClimbingPastThePointTheyAreAStrengthStimulus() {
        let targets = Array(repeating: TargetSnapshot(reps: 30), count: 3)
        let target = targets[0]
        let s = session(0, sets: (0..<3).map {
            perf($0, reps: 30, target: target, plannedSetCount: 3, exerciseName: "Push-up")
        })
        let out = propose(slot: slot(targets: targets), sessions: [s])

        XCTAssertEqual(out.outcome, .holdAdvisoryCeiling)
        XCTAssertEqual(out.applyClass, .pendingReview, "the answer is a harder variation, which only a human can pick")
    }

    func testALayoffBlocksAnIncrease() {
        let out = propose(slot: slot(targets: threeByEight), sessions: [metSession(0)], asOf: 60)

        XCTAssertEqual(out.outcome, .holdLayoff, "adding a step to a weight last touched two months ago is how people get hurt")
        XCTAssertEqual(out.delta, 0)
    }

    func testALayoffStillAllowsADeload() {
        let out = propose(
            slot: slot(targets: threeByEight),
            sessions: [missedSession(1), missedSession(0)],
            asOf: 60
        )
        XCTAssertEqual(out.outcome, .deload, "the veto is on adding load, not on backing it off")
    }

    // MARK: - Multi-set shape

    func testAnIncreaseMovesEverySetAndPreservesTheBackoffShape() {
        let targets = [
            TargetSnapshot(weightKg: 60, reps: 8),
            TargetSnapshot(weightKg: 60, reps: 8),
            TargetSnapshot(weightKg: 55, reps: 8)
        ]
        let s = session(0, sets: [
            perf(0, weight: 60, reps: 8, target: targets[0], plannedSetCount: 3),
            perf(1, weight: 60, reps: 8, target: targets[1], plannedSetCount: 3),
            perf(2, weight: 55, reps: 8, target: targets[2], plannedSetCount: 3)
        ])
        let out = propose(slot: slot(targets: targets), sessions: [s])

        XCTAssertEqual(out.proposedTargets.map(\.weightKg), [62.5, 62.5, 57.5],
                       "an absolute delta keeps the gap at a round 5 kg; a ratio would land on 57.29")
    }

    func testASetCarryingNoWeightIsLeftUntouched() {
        let targets = [
            TargetSnapshot(weightKg: 60, reps: 8),
            TargetSnapshot(reps: 8)
        ]
        let s = session(0, sets: [
            perf(0, weight: 60, reps: 8, target: targets[0], plannedSetCount: 2),
            perf(1, reps: 8, target: targets[1], plannedSetCount: 2)
        ])
        let out = propose(slot: slot(targets: targets), sessions: [s])

        XCTAssertEqual(out.proposedTargets[0].weightKg, 62.5)
        XCTAssertNil(out.proposedTargets[1].weightKg, "you cannot add 2.5 kg to 'no weight'")
        XCTAssertTrue(out.flags.contains(.missingTargetOnDimension))
    }

    func testProposedTargetsAreAlwaysACompleteVector() {
        for out in [
            propose(slot: slot(targets: threeByEight), sessions: [metSession(0)]),
            propose(slot: slot(targets: threeByEight), sessions: [missedSession(0)]),
            propose(slot: slot(targets: threeByEight), sessions: [])
        ] {
            XCTAssertEqual(out.proposedTargets.count, 3, "the writer never has to reason about which sets to touch")
        }
    }

    // MARK: - Baseline reconciliation

    func testLoadingHeavierThanProgrammedAndCompletingItMovesTheProgram() {
        let target = TargetSnapshot(weightKg: 60, reps: 8)
        let s = session(0, sets: (0..<3).map {
            perf($0, weight: 70, reps: 8, target: target, plannedSetCount: 3)
        })
        let out = propose(slot: slot(targets: threeByEight), sessions: [s])

        XCTAssertEqual(out.proposedTargets.map(\.weightKg), [72.5, 72.5, 72.5],
                       "the program is at 70 — anchoring on 60 would fight the lifter every session")
        XCTAssertTrue(out.flags.contains(.baselineExceededTarget))
        XCTAssertEqual(out.applyClass, .pendingReview, "a jump the plan never made is a human's call")
    }

    // MARK: - Determinism and drift

    func testTenConsecutiveIncreasesLandExactlyOnEightyFive() {
        var targets = threeByEight
        for day in 0..<10 {
            let target = targets[0]
            let weight = target.weightKg!
            let s = session(day, sets: (0..<3).map {
                perf($0, weight: weight, reps: 8, target: target, plannedSetCount: 3, day: day)
            })
            let out = propose(slot: slot(targets: targets), sessions: [s], asOf: day + 1)
            XCTAssertEqual(out.outcome, .increase, "session \(day)")
            targets = out.proposedTargets
        }
        XCTAssertEqual(targets[0].weightKg, 85.0)
        XCTAssertTrue(targets[0].weightKg == 85.0, "bit for bit, with zero tolerance")
    }

    func testAMicroLoadingStepDoesNotAccumulateFloatingPointError() {
        var targets = [TargetSnapshot(weightKg: 20, reps: 8)]
        for day in 0..<10 {
            let target = targets[0]
            let weight = target.weightKg!
            let s = session(day, sets: [
                perf(0, weight: weight, reps: 8, target: target, plannedSetCount: 1, day: day)
            ])
            let out = propose(slot: slot(step: 0.3, targets: targets), sessions: [s], asOf: day + 1)
            targets = out.proposedTargets
        }
        XCTAssertEqual(targets[0].weightKg, 23.0)
        XCTAssertTrue(targets[0].weightKg == 23.0, "naive addition reaches 23.000000000000007 and compares unequal")
    }

    func testTheSameInputAlwaysProducesTheSameFingerprint() {
        let a = propose(slot: slot(targets: threeByEight), sessions: [metSession(0)])
        let b = propose(slot: slot(targets: threeByEight), sessions: [metSession(0)])

        XCTAssertEqual(a.fingerprint, b.fingerprint)
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.fingerprint.contains("increase"))
        XCTAssertFalse(a.fingerprint.isEmpty)
    }

    func testADifferentProposalProducesADifferentFingerprint() {
        let increase = propose(slot: slot(targets: threeByEight), sessions: [metSession(0)])
        let deload = propose(slot: slot(targets: threeByEight), sessions: [missedSession(1), missedSession(0)], asOf: 2)

        XCTAssertNotEqual(increase.fingerprint, deload.fingerprint,
                          "dismissing one proposal must not suppress a genuinely different one")
    }

    func testDuplicateRowsFromAReimportDoNotShiftThePairing() {
        let target = TargetSnapshot(weightKg: 60, reps: 8)
        var sets = (0..<3).map { perf($0, weight: 60, reps: 8, target: target, plannedSetCount: 3) }
        // The same set arriving twice, as re-import and crash recovery both produce.
        sets.append(PerformedSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-00DD-000000000001")!,
            exerciseID: benchID, exerciseName: "Bench Press",
            exerciseIndex: 0, setIndex: 1, orderIndex: 9,
            weightKg: 60, reps: 8, completedAt: day(0),
            target: target, plannedSetCount: 3
        ))
        let out = propose(slot: slot(targets: threeByEight), sessions: [session(0, sets: sets)])

        XCTAssertEqual(out.outcome, .increase)
        XCTAssertEqual(out.proposedTargets.count, 3)
    }

    // MARK: - Degenerate slots

    func testASlotWithNoSetsProducesNothing() {
        let out = propose(slot: slot(targets: []), sessions: [])
        XCTAssertEqual(out.outcome, .noTargets)
        XCTAssertEqual(out.applyClass, .noOp)
    }

    func testADeletedExerciseInfersItsDimensionAndForcesReview() {
        let target = TargetSnapshot(weightKg: 60, reps: 8)
        let s = session(0, sets: (0..<3).map {
            perf($0, weight: 60, reps: 8, target: target, plannedSetCount: 3)
        })
        let out = propose(slot: slot(kind: nil, targets: threeByEight), sessions: [s])

        XCTAssertEqual(out.dimension, .load)
        XCTAssertTrue(out.flags.contains(.exerciseMissingFromLibrary))
        XCTAssertEqual(out.applyClass, .pendingReview)
    }

    func testEveryOutcomeCarriesAReasonWrittenByTheCoach() {
        for out in [
            propose(slot: slot(targets: threeByEight), sessions: [metSession(0)]),
            propose(slot: slot(targets: threeByEight), sessions: [missedSession(0)]),
            propose(slot: slot(targets: threeByEight), sessions: [missedSession(1), missedSession(0)], asOf: 2),
            propose(slot: slot(targets: threeByEight), sessions: [metSession(0, rpe: 9)]),
            propose(slot: slot(targets: []), sessions: [])
        ] {
            XCTAssertFalse(out.reason.isEmpty, "\(out.outcome) must explain itself without a language model")
        }
    }
}
