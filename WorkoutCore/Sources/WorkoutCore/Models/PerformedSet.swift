import Foundation
import SwiftData

@Model
public final class PerformedSet {
    @Attribute(.unique) public var id: UUID
    public var orderIndex: Int
    public var exerciseName: String
    public var exerciseIndex: Int
    public var setIndex: Int
    public var weightKg: Double?
    public var reps: Int?
    public var durationSec: Int?
    public var distanceM: Double?
    public var rpe: Int?
    public var completedAt: Date
    public var session: WorkoutSession?

    public init(
        id: UUID = UUID(),
        orderIndex: Int,
        exerciseName: String,
        exerciseIndex: Int,
        setIndex: Int,
        weightKg: Double? = nil,
        reps: Int? = nil,
        durationSec: Int? = nil,
        distanceM: Double? = nil,
        rpe: Int? = nil,
        completedAt: Date
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.exerciseName = exerciseName
        self.exerciseIndex = exerciseIndex
        self.setIndex = setIndex
        self.weightKg = weightKg
        self.reps = reps
        self.durationSec = durationSec
        self.distanceM = distanceM
        self.rpe = rpe
        self.completedAt = completedAt
    }
}
