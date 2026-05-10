import Foundation

public protocol WorkoutLifecycle: Sendable {
    func requestAuthorization() async throws
    func startWorkout(at date: Date) async throws
    func endWorkout(at date: Date) async throws -> UUID?
    func discard() async
}

public struct NoopWorkoutLifecycle: WorkoutLifecycle {
    public init() {}
    public func requestAuthorization() async throws {}
    public func startWorkout(at date: Date) async throws {}
    public func endWorkout(at date: Date) async throws -> UUID? { nil }
    public func discard() async {}
}
