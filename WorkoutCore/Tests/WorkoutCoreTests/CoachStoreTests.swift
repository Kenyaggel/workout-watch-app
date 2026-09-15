import XCTest
import SwiftData
@testable import WorkoutCore

/// End-to-end through SwiftData: build the input from a real store, run the rules, write the
/// result back onto the workout.
@MainActor
final class CoachStoreTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try WorkoutModelContainer.makeShared(inMemory: true))
    }

    private func day(_ n: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000).addingTimeInterval(TimeInterval(n) * 86_400)
    }

    /// A Push Day workout with one bench slot of three sets at `weight` × 8.
    @discardableResult
    private func seedWorkout(
        _ context: ModelContext,
        weight: Double = 60,
        reps: Int = 8,
        setCount: Int = 3,
        step: Double? = nil
    ) -> (template: WorkoutTemplate, exercise: Exercise, slot: PlannedExercise) {
        let exercise = Exercise(
            name: "Bench Press", kind: .reps, defaultRestSec: 120,
            defaultTargetReps: reps, progressionStep: step
        )
        context.insert(exercise)
        let template = WorkoutTemplate(name: "Push Day")
        context.insert(template)
        let slot = PlannedExercise(orderIndex: 0, exercise: exercise, restSec: 120)
        slot.template = template
        context.insert(slot)
        for index in 0..<setCount {
            let set = PlannedSet(orderIndex: index, targetWeightKg: weight, targetReps: reps)
            set.plannedExercise = slot
            context.insert(set)
        }
        try? context.save()
        return (template, exercise, slot)
    }

    @discardableResult
    private func recordSession(
        _ context: ModelContext,
        template: WorkoutTemplate,
        exercise: Exercise,
        on dayIndex: Int,
        weight: Double = 60,
        reps: Int = 8,
        targetWeight: Double = 60,
        targetReps: Int = 8,
        setCount: Int = 3,
        rpe: Int? = nil
    ) -> WorkoutSession {
        let session = WorkoutSession(
            startedAt: day(dayIndex), templateName: template.name, template: template
        )
        session.endedAt = day(dayIndex).addingTimeInterval(3_600)
        context.insert(session)
        for index in 0..<setCount {
            let performed = PerformedSet(
                orderIndex: index,
                exerciseName: exercise.name,
                exerciseID: exercise.id,
                exerciseIndex: 0,
                setIndex: index,
                weightKg: weight,
                reps: reps,
                rpe: rpe,
                completedAt: day(dayIndex).addingTimeInterval(Double(index) * 120),
                plannedSetCount: setCount,
                targetWeightKg: targetWeight,
                targetReps: targetReps
            )
            performed.session = session
            context.insert(performed)
        }
        try? context.save()
        return session
    }

    // MARK: - Auto-apply

    func testACompletedSessionWritesTheNextTargetsOntoTheWorkout() throws {
        let context = try makeContext()
        let seed = seedWorkout(context)
        let session = recordSession(context, template: seed.template, exercise: seed.exercise, on: 0)

        let applied = try CoachStore.ingest(session: session, in: context, asOf: day(1))

        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(applied.first?.output.outcome, .increase)
        XCTAssertEqual(seed.slot.orderedSets.map(\.targetWeightKg), [62.5, 62.5, 62.5],
                       "the single-step move applies itself so the watch is never stale")
    }

    func testADeloadIsNeverWrittenWithoutAHuman() throws {
        let context = try makeContext()
        let seed = seedWorkout(context)
        recordSession(context, template: seed.template, exercise: seed.exercise, on: 0, reps: 5)
        let second = recordSession(context, template: seed.template, exercise: seed.exercise, on: 1, reps: 5)

        let applied = try CoachStore.ingest(session: second, in: context, asOf: day(2))
        XCTAssertTrue(applied.isEmpty)
        XCTAssertEqual(seed.slot.orderedSets.map(\.targetWeightKg), [60, 60, 60],
                       "targets are untouched until the lifter approves")

        let pending = try CoachStore.pendingProposals(in: context, asOf: day(2))
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.output.outcome, .deload)
    }

    func testTheSameSessionIngestedTwiceDoesNotStackTwoIncreases() throws {
        let context = try makeContext()
        let seed = seedWorkout(context)
        let session = recordSession(context, template: seed.template, exercise: seed.exercise, on: 0)

        try CoachStore.ingest(session: session, in: context, asOf: day(1))
        try CoachStore.ingest(session: session, in: context, asOf: day(1))

        XCTAssertEqual(seed.slot.orderedSets.map(\.targetWeightKg), [62.5, 62.5, 62.5],
                       "the second run sees a session run against the old prescription and holds")
    }

    // MARK: - Accepting and dismissing

    func testAcceptingAProposalWritesItAndRecordsTheDecision() throws {
        let context = try makeContext()
        let seed = seedWorkout(context)
        recordSession(context, template: seed.template, exercise: seed.exercise, on: 0, reps: 5)
        recordSession(context, template: seed.template, exercise: seed.exercise, on: 1, reps: 5)

        let pending = try CoachStore.pendingProposals(in: context, asOf: day(2))
        let deload = try XCTUnwrap(pending.first)
        try CoachStore.accept(deload, in: context, at: day(2))

        XCTAssertEqual(seed.slot.orderedSets.map(\.targetWeightKg), [55, 55, 55])
        let decisions = try context.fetch(FetchDescriptor<CoachDecision>())
        XCTAssertEqual(decisions.count, 1)
        XCTAssertTrue(decisions.first?.wasAccepted == true)
        XCTAssertEqual(decisions.first?.outcomeRaw, CoachOutcome.deload.rawValue)
    }

    func testADismissedProposalStopsAppearing() throws {
        let context = try makeContext()
        let seed = seedWorkout(context)
        recordSession(context, template: seed.template, exercise: seed.exercise, on: 0, reps: 5)
        recordSession(context, template: seed.template, exercise: seed.exercise, on: 1, reps: 5)

        let deload = try XCTUnwrap(try CoachStore.pendingProposals(in: context, asOf: day(2)).first)
        try CoachStore.dismiss(deload, in: context, at: day(2))

        XCTAssertTrue(try CoachStore.pendingProposals(in: context, asOf: day(2)).isEmpty)
        XCTAssertEqual(seed.slot.orderedSets.map(\.targetWeightKg), [60, 60, 60],
                       "dismissing changes nothing about the workout")
    }

    func testADismissedProposalComesBackOnNewEvidence() throws {
        let context = try makeContext()
        let seed = seedWorkout(context)
        recordSession(context, template: seed.template, exercise: seed.exercise, on: 0, reps: 5)
        recordSession(context, template: seed.template, exercise: seed.exercise, on: 1, reps: 5)

        let deload = try XCTUnwrap(try CoachStore.pendingProposals(in: context, asOf: day(2)).first)
        try CoachStore.dismiss(deload, in: context, at: day(2))
        XCTAssertTrue(try CoachStore.pendingProposals(in: context, asOf: day(2)).isEmpty)

        // Stall again at the same weight.
        recordSession(context, template: seed.template, exercise: seed.exercise, on: 3, reps: 5)

        let resurfaced = try CoachStore.pendingProposals(in: context, asOf: day(4))
        XCTAssertEqual(resurfaced.count, 1,
                       "dismissing means 'not on that evidence', not 'never again'")
        XCTAssertEqual(resurfaced.first?.output.outcome, .deload)
    }

    // MARK: - The deviation signal

    func testASessionRecordsThePendingProposalItWasRunAgainst() throws {
        let context = try makeContext()
        let seed = seedWorkout(context)

        // Two stalls put a deload on the review screen. It is never applied, so the workout
        // still says 60.
        recordSession(context, template: seed.template, exercise: seed.exercise, on: 0, reps: 5)
        recordSession(context, template: seed.template, exercise: seed.exercise, on: 1, reps: 5)
        XCTAssertEqual(seed.slot.orderedSets.first?.targetWeightKg, 60)

        // The lifter trains through it at the old weight anyway.
        let third = recordSession(context, template: seed.template, exercise: seed.exercise, on: 2, reps: 5)
        try CoachStore.ingest(session: third, in: context, asOf: day(3))

        let stamped = third.orderedPerformedSets
        XCTAssertEqual(stamped.compactMap(\.suggestedWeightKg), [55, 55, 55],
                       "the coach wanted 55; the lifter ran 60, and that gap is the whole signal")
        XCTAssertEqual(stamped.compactMap(\.targetWeightKg), [60, 60, 60])
    }

    /// An applied proposal needs no separate record: once it is written to the workout it
    /// *is* the target, and `target*` already captures what the set was run against.
    func testAnAppliedProposalIsNotDuplicatedIntoTheSuggestionFields() throws {
        let context = try makeContext()
        let seed = seedWorkout(context)
        let first = recordSession(context, template: seed.template, exercise: seed.exercise, on: 0)
        try CoachStore.ingest(session: first, in: context, asOf: day(1))
        XCTAssertEqual(seed.slot.orderedSets.first?.targetWeightKg, 62.5)

        let second = recordSession(
            context, template: seed.template, exercise: seed.exercise, on: 2,
            weight: 62.5, targetWeight: 62.5
        )
        try CoachStore.ingest(session: second, in: context, asOf: day(3))

        XCTAssertTrue(second.orderedPerformedSets.allSatisfy { $0.suggestedWeightKg == nil })
        XCTAssertEqual(second.orderedPerformedSets.compactMap(\.targetWeightKg), [62.5, 62.5, 62.5])
    }

    // MARK: - Scope

    func testASlotInAnUnrelatedWorkoutIsNotTouched() throws {
        let context = try makeContext()
        let seed = seedWorkout(context)

        let otherTemplate = WorkoutTemplate(name: "Pull Day")
        context.insert(otherTemplate)
        let otherSlot = PlannedExercise(orderIndex: 0, exercise: seed.exercise, restSec: 120)
        otherSlot.template = otherTemplate
        context.insert(otherSlot)
        let otherSet = PlannedSet(orderIndex: 0, targetWeightKg: 40, targetReps: 12)
        otherSet.plannedExercise = otherSlot
        context.insert(otherSet)
        try context.save()

        let session = recordSession(context, template: seed.template, exercise: seed.exercise, on: 0)
        try CoachStore.ingest(session: session, in: context, asOf: day(1))

        XCTAssertEqual(otherSlot.orderedSets.map(\.targetWeightKg), [40],
                       "heavy 5s must never contaminate volume 12s in another workout")
    }

    func testAnUnfinishedSessionIsIgnored() throws {
        let context = try makeContext()
        let seed = seedWorkout(context)
        let session = recordSession(context, template: seed.template, exercise: seed.exercise, on: 0)
        session.endedAt = nil
        try context.save()

        try CoachStore.ingest(session: session, in: context, asOf: day(1))
        XCTAssertEqual(seed.slot.orderedSets.map(\.targetWeightKg), [60, 60, 60])
    }

    func testAnExerciseLevelStepOverrideIsHonouredEndToEnd() throws {
        let context = try makeContext()
        let seed = seedWorkout(context, step: 5)
        let session = recordSession(context, template: seed.template, exercise: seed.exercise, on: 0)

        try CoachStore.ingest(session: session, in: context, asOf: day(1))
        XCTAssertEqual(seed.slot.orderedSets.map(\.targetWeightKg), [65, 65, 65])
    }

    // MARK: - Proposals that report a situation rather than propose a number

    /// `.holdAtFloor`, `.holdAdvisoryCeiling` and `.holdChronicPartialSession` hold for
    /// review but leave the numbers alone. Acting on one has to retire it: it re-derives
    /// identically from unchanged history, so if only dismissals suppressed proposals it
    /// would sit on the review screen forever and every tap would insert another decision.
    func testAcknowledgingAProposalThatChangesNothingClearsIt() throws {
        let context = try makeContext()
        // 5 kg with a 2.5 kg step: a deload would land on 2.5, which is under the floor.
        let seed = seedWorkout(context, weight: 5)
        recordSession(context, template: seed.template, exercise: seed.exercise,
                      on: 0, weight: 5, reps: 5, targetWeight: 5)
        recordSession(context, template: seed.template, exercise: seed.exercise,
                      on: 1, weight: 5, reps: 5, targetWeight: 5)

        let pending = try CoachStore.pendingProposals(in: context, asOf: day(2))
        let stuck = try XCTUnwrap(pending.first)
        XCTAssertEqual(stuck.output.outcome, .holdAtFloor)
        XCTAssertFalse(stuck.changesTargets, "there is nothing to write — the lifter is only being told")

        try CoachStore.accept(stuck, in: context, at: day(2))

        XCTAssertTrue(try CoachStore.pendingProposals(in: context, asOf: day(2)).isEmpty,
                      "acknowledging it must retire it, not re-derive it unchanged")
        XCTAssertEqual(seed.slot.orderedSets.map(\.targetWeightKg), [5, 5, 5],
                       "and must not have written anything")
        XCTAssertEqual(try context.fetch(FetchDescriptor<CoachDecision>()).count, 1)
    }

    func testAnAcknowledgedSituationStillComesBackOnNewEvidence() throws {
        let context = try makeContext()
        let seed = seedWorkout(context, weight: 5)
        recordSession(context, template: seed.template, exercise: seed.exercise,
                      on: 0, weight: 5, reps: 5, targetWeight: 5)
        recordSession(context, template: seed.template, exercise: seed.exercise,
                      on: 1, weight: 5, reps: 5, targetWeight: 5)

        let stuck = try XCTUnwrap(try CoachStore.pendingProposals(in: context, asOf: day(2)).first)
        try CoachStore.accept(stuck, in: context, at: day(2))
        XCTAssertTrue(try CoachStore.pendingProposals(in: context, asOf: day(2)).isEmpty)

        recordSession(context, template: seed.template, exercise: seed.exercise,
                      on: 3, weight: 5, reps: 5, targetWeight: 5)

        XCTAssertEqual(try CoachStore.pendingProposals(in: context, asOf: day(4)).count, 1,
                       "a fresh session is fresh evidence, so the coach says so again")
    }

    func testAProposalThatMovesTheNumbersStillReportsThatItDoes() throws {
        let context = try makeContext()
        let seed = seedWorkout(context)
        recordSession(context, template: seed.template, exercise: seed.exercise, on: 0, reps: 5)
        recordSession(context, template: seed.template, exercise: seed.exercise, on: 1, reps: 5)

        let deload = try XCTUnwrap(try CoachStore.pendingProposals(in: context, asOf: day(2)).first)
        XCTAssertTrue(deload.changesTargets)
        XCTAssertEqual(deload.changeSummary, "3×60 kg → 3×55 kg")
    }
}
