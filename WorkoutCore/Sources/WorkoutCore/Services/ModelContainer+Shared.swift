import Foundation
import SwiftData

public enum WorkoutModelContainer {
    public static func makeShared(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: WorkoutSchemaV2.self)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: WorkoutMigrationPlan.self,
            configurations: [config]
        )
    }
}
