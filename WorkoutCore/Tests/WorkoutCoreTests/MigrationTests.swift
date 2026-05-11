import XCTest
import SwiftData
@testable import WorkoutCore

@MainActor
final class MigrationTests: XCTestCase {

    private func tempStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("workoutcore-migration-\(UUID().uuidString).store")
    }

    func testV1ToV2MigrationLiftsRestOverrideToPlannedExerciseRest() throws {
        let storeURL = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let exerciseID = UUID()

        // 1. Open the store on V1 only, write a PlannedExercise with one set
        // that carries restOverrideSec = 120 (the legacy per-set rest).
        try autoreleasepool {
            let v1Schema = Schema(versionedSchema: WorkoutSchemaV1.self)
            let v1Config = ModelConfiguration(schema: v1Schema, url: storeURL)
            let v1Container = try ModelContainer(for: v1Schema, configurations: [v1Config])
            let v1Context = ModelContext(v1Container)

            let pe = WorkoutSchemaV1.PlannedExercise(id: exerciseID, orderIndex: 0)
            v1Context.insert(pe)
            let ps = WorkoutSchemaV1.PlannedSet(orderIndex: 0, restOverrideSec: 120)
            ps.plannedExercise = pe
            v1Context.insert(ps)
            try v1Context.save()
        }

        // 2. Reopen the same on-disk store with V2 + the migration plan.
        let v2Schema = Schema(versionedSchema: WorkoutSchemaV2.self)
        let v2Config = ModelConfiguration(schema: v2Schema, url: storeURL)
        let v2Container = try ModelContainer(
            for: v2Schema,
            migrationPlan: WorkoutMigrationPlan.self,
            configurations: [v2Config]
        )
        let v2Context = ModelContext(v2Container)

        let exercises = try v2Context.fetch(FetchDescriptor<PlannedExercise>())
        XCTAssertEqual(exercises.count, 1)
        XCTAssertEqual(exercises.first?.id, exerciseID)
        XCTAssertEqual(exercises.first?.restSec, 120,
                       "Migration should lift PlannedSet.restOverrideSec onto PlannedExercise.restSec")
    }

    func testV1ToV2MigrationWithNoLegacyRestLeavesPlannedExerciseRestNil() throws {
        let storeURL = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let exerciseID = UUID()

        try autoreleasepool {
            let v1Schema = Schema(versionedSchema: WorkoutSchemaV1.self)
            let v1Config = ModelConfiguration(schema: v1Schema, url: storeURL)
            let v1Container = try ModelContainer(for: v1Schema, configurations: [v1Config])
            let v1Context = ModelContext(v1Container)

            let pe = WorkoutSchemaV1.PlannedExercise(id: exerciseID, orderIndex: 0)
            v1Context.insert(pe)
            // No sets — nothing to lift.
            try v1Context.save()
        }

        let v2Schema = Schema(versionedSchema: WorkoutSchemaV2.self)
        let v2Config = ModelConfiguration(schema: v2Schema, url: storeURL)
        let v2Container = try ModelContainer(
            for: v2Schema,
            migrationPlan: WorkoutMigrationPlan.self,
            configurations: [v2Config]
        )
        let v2Context = ModelContext(v2Container)

        let exercises = try v2Context.fetch(FetchDescriptor<PlannedExercise>())
        XCTAssertEqual(exercises.count, 1)
        XCTAssertNil(exercises.first?.restSec,
                     "With no legacy rest data, PlannedExercise.restSec should remain nil and fall back via resolvedRestSec")
    }

    func testMigrationPlanDeclaresV2AndStage() {
        XCTAssertTrue(
            WorkoutMigrationPlan.schemas.contains { $0 == WorkoutSchemaV2.self },
            "Migration plan must include WorkoutSchemaV2"
        )
        XCTAssertFalse(
            WorkoutMigrationPlan.stages.isEmpty,
            "Migration plan must declare at least one stage for the V1→V2 transition"
        )
    }
}
