import Foundation
import SwiftData

@Model
public final class PlannedExercise {
    @Attribute(.unique) public var id: UUID
    public var orderIndex: Int
    public var restSec: Int?
    public var exercise: Exercise?
    public var template: WorkoutTemplate?

    @Relationship(deleteRule: .cascade, inverse: \PlannedSet.plannedExercise)
    public var sets: [PlannedSet] = []

    public init(
        id: UUID = UUID(),
        orderIndex: Int,
        exercise: Exercise? = nil,
        restSec: Int? = nil
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.restSec = restSec ?? exercise?.defaultRestSec ?? 90
        self.exercise = exercise
    }

    public var orderedSets: [PlannedSet] {
        sets.sorted { $0.orderIndex < $1.orderIndex }
    }

    public var resolvedRestSec: Int {
        restSec ?? exercise?.defaultRestSec ?? 90
    }
}
