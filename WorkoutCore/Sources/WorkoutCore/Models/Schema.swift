import Foundation
import SwiftData

public enum WorkoutSchemaV1: VersionedSchema {
    public static var versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            Exercise.self,
            PlannedSet.self,
            PlannedExercise.self,
            WorkoutTemplate.self,
            WorkoutSession.self,
            PerformedSet.self
        ]
    }
}

public enum WorkoutMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [WorkoutSchemaV1.self]
    }

    public static var stages: [MigrationStage] { [] }
}
