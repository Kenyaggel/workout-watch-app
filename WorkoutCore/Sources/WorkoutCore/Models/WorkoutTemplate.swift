import Foundation
import SwiftData

@Model
public final class WorkoutTemplate {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \PlannedExercise.template)
    public var plannedExercises: [PlannedExercise] = []

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }

    public var orderedExercises: [PlannedExercise] {
        plannedExercises.sorted { $0.orderIndex < $1.orderIndex }
    }
}
