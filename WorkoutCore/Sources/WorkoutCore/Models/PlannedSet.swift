import Foundation
import SwiftData

@Model
public final class PlannedSet {
    @Attribute(.unique) public var id: UUID
    public var orderIndex: Int
    public var targetWeightKg: Double?
    public var targetReps: Int?
    public var targetDurationSec: Int?
    public var targetDistanceM: Double?
    public var plannedExercise: PlannedExercise?

    public init(
        id: UUID = UUID(),
        orderIndex: Int,
        targetWeightKg: Double? = nil,
        targetReps: Int? = nil,
        targetDurationSec: Int? = nil,
        targetDistanceM: Double? = nil
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.targetWeightKg = targetWeightKg
        self.targetReps = targetReps
        self.targetDurationSec = targetDurationSec
        self.targetDistanceM = targetDistanceM
    }
}
