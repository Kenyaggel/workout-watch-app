import Foundation
import SwiftData

public enum WorkoutMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [WorkoutSchemaV1.self, WorkoutSchemaV2.self]
    }

    public static var stages: [MigrationStage] {
        [v1ToV2]
    }

    private static let v1ToV2 = MigrationStage.custom(
        fromVersion: WorkoutSchemaV1.self,
        toVersion: WorkoutSchemaV2.self,
        willMigrate: { context in
            // V1 stored rest per-set on PlannedSet.restOverrideSec. V2 owns rest
            // on PlannedExercise.restSec. Capture the first non-nil per-set
            // override for each parent exercise so didMigrate can lift it onto
            // PlannedExercise after the schema diff has been applied.
            let sets = try context.fetch(FetchDescriptor<WorkoutSchemaV1.PlannedSet>())
            var liftedRest: [UUID: Int] = [:]
            for set in sets {
                guard
                    let parentID = set.plannedExercise?.id,
                    let rest = set.restOverrideSec,
                    liftedRest[parentID] == nil
                else { continue }
                liftedRest[parentID] = rest
            }
            MigrationRestStash.shared.values = liftedRest
        },
        didMigrate: { context in
            let liftedRest = MigrationRestStash.shared.values
            MigrationRestStash.shared.values = [:]
            guard !liftedRest.isEmpty else { return }
            let exercises = try context.fetch(FetchDescriptor<WorkoutSchemaV2.PlannedExercise>())
            for exercise in exercises {
                if let rest = liftedRest[exercise.id] {
                    exercise.restSec = rest
                }
            }
            try context.save()
        }
    )
}

private final class MigrationRestStash: @unchecked Sendable {
    static let shared = MigrationRestStash()
    private let lock = NSLock()
    private var _values: [UUID: Int] = [:]
    var values: [UUID: Int] {
        get { lock.lock(); defer { lock.unlock() }; return _values }
        set { lock.lock(); defer { lock.unlock() }; _values = newValue }
    }
}
