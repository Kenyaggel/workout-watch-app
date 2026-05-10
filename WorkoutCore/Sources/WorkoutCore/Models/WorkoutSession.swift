import Foundation
import SwiftData

@Model
public final class WorkoutSession {
    @Attribute(.unique) public var id: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var template: WorkoutTemplate?
    public var templateName: String
    public var healthKitWorkoutUUID: UUID?

    @Relationship(deleteRule: .cascade, inverse: \PerformedSet.session)
    public var performedSets: [PerformedSet] = []

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        templateName: String,
        template: WorkoutTemplate? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.templateName = templateName
        self.template = template
    }

    public var isFinished: Bool { endedAt != nil }

    public var orderedPerformedSets: [PerformedSet] {
        performedSets.sorted { $0.orderIndex < $1.orderIndex }
    }
}
