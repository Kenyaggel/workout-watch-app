import Foundation
import SwiftData

@Model
public final class Exercise {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var kindRaw: String
    public var defaultRestSec: Int
    public var defaultTargetReps: Int?
    public var defaultTargetDurationSec: Int?
    public var defaultTargetDistanceM: Double?

    public var kind: ExerciseKind {
        get { ExerciseKind(rawValue: kindRaw) ?? .reps }
        set { kindRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        name: String,
        kind: ExerciseKind,
        defaultRestSec: Int,
        defaultTargetReps: Int? = nil,
        defaultTargetDurationSec: Int? = nil,
        defaultTargetDistanceM: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.defaultRestSec = defaultRestSec
        self.defaultTargetReps = defaultTargetReps
        self.defaultTargetDurationSec = defaultTargetDurationSec
        self.defaultTargetDistanceM = defaultTargetDistanceM
    }
}
