import Foundation

public enum HapticEvent: Sendable {
    case setStart
    case restWarning
    case restEnd
    case workoutComplete
}

public protocol Haptics: Sendable {
    func play(_ event: HapticEvent)
}

public struct NoopHaptics: Haptics {
    public init() {}
    public func play(_ event: HapticEvent) {}
}
