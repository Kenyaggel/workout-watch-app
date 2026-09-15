import XCTest
import SwiftData
@testable import WorkoutCore

@MainActor
final class MigrationTests: XCTestCase {

    private func tempStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("workoutcore-migration-\(UUID().uuidString).store")
    }

    /// Opens the on-disk store at the current schema with the full migration plan, which is
    /// what the apps do via `WorkoutModelContainer.makeShared`.
    private func openAtCurrentSchema(_ storeURL: URL) throws -> ModelContext {
        let schema = Schema(versionedSchema: WorkoutSchemaV3.self)
        let config = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: WorkoutMigrationPlan.self,
            configurations: [config]
        )
        return ModelContext(container)
    }

    private func writeV1Store(_ storeURL: URL, _ body: (ModelContext) throws -> Void) throws {
        try autoreleasepool {
            let schema = Schema(versionedSchema: WorkoutSchemaV1.self)
            let config = ModelConfiguration(schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)
            try body(context)
            try context.save()
        }
    }

    private func writeV2Store(_ storeURL: URL, _ body: (ModelContext) throws -> Void) throws {
        try autoreleasepool {
            let schema = Schema(versionedSchema: WorkoutSchemaV2.self)
            let config = ModelConfiguration(schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)
            try body(context)
            try context.save()
        }
    }

    // MARK: - V1 → V3 (chained)

    /// A store created on the very first shipped build must still open today. This exercises
    /// both stages in sequence, not just the newest one.
    func testV1StoreMigratesAllTheWayToV3AndStillLiftsRestOverride() throws {
        let storeURL = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let plannedExerciseID = UUID()

        try writeV1Store(storeURL) { context in
            let pe = WorkoutSchemaV1.PlannedExercise(id: plannedExerciseID, orderIndex: 0)
            context.insert(pe)
            let ps = WorkoutSchemaV1.PlannedSet(orderIndex: 0, restOverrideSec: 120)
            ps.plannedExercise = pe
            context.insert(ps)
        }

        let context = try openAtCurrentSchema(storeURL)
        let exercises = try context.fetch(FetchDescriptor<PlannedExercise>())
        XCTAssertEqual(exercises.count, 1)
        XCTAssertEqual(exercises.first?.id, plannedExerciseID)
        XCTAssertEqual(exercises.first?.restSec, 120,
                       "The V1→V2 stage must still lift PlannedSet.restOverrideSec onto PlannedExercise.restSec when chained through V3")
    }

    func testV1ToV3MigrationWithNoLegacyRestLeavesPlannedExerciseRestNil() throws {
        let storeURL = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let plannedExerciseID = UUID()

        try writeV1Store(storeURL) { context in
            context.insert(WorkoutSchemaV1.PlannedExercise(id: plannedExerciseID, orderIndex: 0))
            // No sets — nothing to lift.
        }

        let context = try openAtCurrentSchema(storeURL)
        let exercises = try context.fetch(FetchDescriptor<PlannedExercise>())
        XCTAssertEqual(exercises.count, 1)
        XCTAssertNil(exercises.first?.restSec,
                     "With no legacy rest data, PlannedExercise.restSec should remain nil and fall back via resolvedRestSec")
    }

    // MARK: - V2 → V3 identity backfill

    func testV2ToV3BackfillsExerciseIDFromName() throws {
        let storeURL = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let benchID = UUID()

        try writeV2Store(storeURL) { context in
            context.insert(WorkoutSchemaV2.Exercise(
                id: benchID, name: "Bench Press", kind: .reps, defaultRestSec: 120
            ))
            context.insert(WorkoutSchemaV2.PerformedSet(
                orderIndex: 0,
                exerciseName: "Bench Press",
                exerciseIndex: 0,
                setIndex: 0,
                weightKg: 60,
                reps: 8,
                completedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ))
        }

        let context = try openAtCurrentSchema(storeURL)
        let performed = try context.fetch(FetchDescriptor<PerformedSet>())
        XCTAssertEqual(performed.count, 1)
        XCTAssertEqual(performed.first?.exerciseID, benchID,
                       "The V2→V3 stage should backfill Lift Identity by matching the recorded name against the library")
        XCTAssertEqual(performed.first?.exerciseName, "Bench Press",
                       "exerciseName is kept deliberately — it records what the exercise was called at the time")
    }

    func testV2ToV3BackfillIgnoresCaseAndSurroundingWhitespace() throws {
        let storeURL = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let squatID = UUID()

        try writeV2Store(storeURL) { context in
            context.insert(WorkoutSchemaV2.Exercise(
                id: squatID, name: "Back Squat", kind: .reps, defaultRestSec: 180
            ))
            context.insert(WorkoutSchemaV2.PerformedSet(
                orderIndex: 0,
                exerciseName: "  back squat ",
                exerciseIndex: 0,
                setIndex: 0,
                weightKg: 100,
                reps: 5,
                completedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ))
        }

        let context = try openAtCurrentSchema(storeURL)
        let performed = try context.fetch(FetchDescriptor<PerformedSet>())
        XCTAssertEqual(performed.first?.exerciseID, squatID)
    }

    func testV2ToV3LeavesIdentityNilWhenNoExerciseMatchesTheName() throws {
        let storeURL = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        try writeV2Store(storeURL) { context in
            context.insert(WorkoutSchemaV2.Exercise(
                id: UUID(), name: "Bench Press", kind: .reps, defaultRestSec: 120
            ))
            // Performed under a name the library no longer has — renamed or deleted before
            // the migration. The ADR says these rows keep a null identity.
            context.insert(WorkoutSchemaV2.PerformedSet(
                orderIndex: 0,
                exerciseName: "Decline Press",
                exerciseIndex: 0,
                setIndex: 0,
                weightKg: 50,
                reps: 10,
                completedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ))
        }

        let context = try openAtCurrentSchema(storeURL)
        let performed = try context.fetch(FetchDescriptor<PerformedSet>())
        XCTAssertEqual(performed.count, 1)
        XCTAssertNil(performed.first?.exerciseID,
                     "A performed set whose exercise was renamed or deleted before the migration cannot be resolved and must stay name-matched")
    }

    func testV2ToV3LeavesIdentityNilWhenTwoExercisesShareAName() throws {
        let storeURL = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        try writeV2Store(storeURL) { context in
            context.insert(WorkoutSchemaV2.Exercise(
                id: UUID(), name: "Row", kind: .reps, defaultRestSec: 90
            ))
            context.insert(WorkoutSchemaV2.Exercise(
                id: UUID(), name: "Row", kind: .reps, defaultRestSec: 60
            ))
            context.insert(WorkoutSchemaV2.PerformedSet(
                orderIndex: 0,
                exerciseName: "Row",
                exerciseIndex: 0,
                setIndex: 0,
                weightKg: 40,
                reps: 12,
                completedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ))
        }

        let context = try openAtCurrentSchema(storeURL)
        let performed = try context.fetch(FetchDescriptor<PerformedSet>())
        XCTAssertEqual(performed.count, 1)
        XCTAssertNil(performed.first?.exerciseID,
                     "Two exercises sharing a name resolve to neither — guessing would assert an identity that is wrong for half the rows")
    }

    func testV2ToV3AddsNilCoachFieldsWithoutDisturbingExistingData() throws {
        let storeURL = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        try writeV2Store(storeURL) { context in
            context.insert(WorkoutSchemaV2.Exercise(
                id: UUID(), name: "Plank", kind: .timed, defaultRestSec: 60, defaultTargetDurationSec: 45
            ))
            context.insert(WorkoutSchemaV2.PerformedSet(
                orderIndex: 0,
                exerciseName: "Plank",
                exerciseIndex: 0,
                setIndex: 0,
                durationSec: 45,
                rpe: 7,
                completedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ))
        }

        let context = try openAtCurrentSchema(storeURL)

        let exercise = try XCTUnwrap(try context.fetch(FetchDescriptor<Exercise>()).first)
        XCTAssertNil(exercise.progressionStep,
                     "progressionStep starts nil on migrated rows and falls back to the dimension default")
        XCTAssertEqual(exercise.defaultTargetDurationSec, 45)

        let performed = try XCTUnwrap(try context.fetch(FetchDescriptor<PerformedSet>()).first)
        XCTAssertEqual(performed.durationSec, 45)
        XCTAssertEqual(performed.rpe, 7)
        XCTAssertNil(performed.targetWeightKg)
        XCTAssertNil(performed.targetReps)
        XCTAssertNil(performed.targetDurationSec)
        XCTAssertNil(performed.targetDistanceM)
        XCTAssertNil(performed.suggestedWeightKg)
        XCTAssertNil(performed.suggestedReps)
        XCTAssertNil(performed.suggestedDurationSec)
        XCTAssertNil(performed.suggestedDistanceM)

        XCTAssertTrue(try context.fetch(FetchDescriptor<ProposedTarget>()).isEmpty,
                      "ProposedTarget is a new entity and starts empty")
    }

    // MARK: - Plan shape

    func testMigrationPlanDeclaresEverySchemaAndStage() {
        XCTAssertTrue(
            WorkoutMigrationPlan.schemas.contains { $0 == WorkoutSchemaV2.self },
            "Migration plan must include WorkoutSchemaV2"
        )
        XCTAssertTrue(
            WorkoutMigrationPlan.schemas.contains { $0 == WorkoutSchemaV3.self },
            "Migration plan must include WorkoutSchemaV3"
        )
        XCTAssertEqual(
            WorkoutMigrationPlan.stages.count, 2,
            "Migration plan must declare a stage for V1→V2 and for V2→V3"
        )
    }
}
