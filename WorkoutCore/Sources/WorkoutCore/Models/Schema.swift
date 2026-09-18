import Foundation
import SwiftData

public enum WorkoutMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [WorkoutSchemaV1.self, WorkoutSchemaV2.self, WorkoutSchemaV3.self]
    }

    public static var stages: [MigrationStage] {
        [v1ToV2, v2ToV3]
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

    /// Every attribute V3 adds is optional and `ProposedTarget` is a brand-new entity, so
    /// the schema diff itself migrates lightly. The stage is `.custom` only because the
    /// backfill below needs to run code — hence `willMigrate: nil`.
    ///
    /// Unlike V1→V2, no stash is needed. That stage had to capture `PlannedSet.restOverrideSec`
    /// in `willMigrate` because the attribute ceased to exist in V2. Here nothing is
    /// removed: `PerformedSet.exerciseName` and `Exercise.id`/`name` are present on both
    /// sides, so `didMigrate` can read everything it needs after the diff has been applied.
    private static let v2ToV3 = MigrationStage.custom(
        fromVersion: WorkoutSchemaV2.self,
        toVersion: WorkoutSchemaV3.self,
        willMigrate: nil,
        didMigrate: { context in
            // Backfill Lift Identity on existing performed history by matching the name
            // recorded at the time against the exercise library. This is only reliable
            // while stores are small, and it cannot be redone later — see
            // docs/adr/0001-exercise-identity-in-performed-history.md.
            let exercises = try context.fetch(FetchDescriptor<WorkoutSchemaV3.Exercise>())
            guard !exercises.isEmpty else { return }

            var idsByName: [String: UUID] = [:]
            var ambiguousNames: Swift.Set<String> = []
            for exercise in exercises {
                let key = MigrationNameKey.normalize(exercise.name)
                if idsByName[key] != nil {
                    ambiguousNames.insert(key)
                } else {
                    idsByName[key] = exercise.id
                }
            }
            // A name shared by two exercises resolves to neither. Picking one arbitrarily
            // would assert a Lift Identity that is wrong for roughly half the rows; a null
            // identity instead falls back to name matching, which is exactly the behaviour
            // these rows already had.
            for name in ambiguousNames {
                idsByName.removeValue(forKey: name)
            }
            guard !idsByName.isEmpty else { return }

            let performedSets = try context.fetch(FetchDescriptor<WorkoutSchemaV3.PerformedSet>())
            var didChange = false
            for performedSet in performedSets where performedSet.exerciseID == nil {
                guard let id = idsByName[MigrationNameKey.normalize(performedSet.exerciseName)] else {
                    continue
                }
                performedSet.exerciseID = id
                didChange = true
            }
            if didChange {
                try context.save()
            }
        }
    )
}

/// Name matching for the V2→V3 identity backfill. Trimmed and case-folded so "bench press"
/// and "Bench Press " resolve to the same library exercise.
enum MigrationNameKey {
    static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
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
