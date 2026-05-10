import Foundation
import WatchKit
import WorkoutCore

struct WatchHaptics: Haptics {
    func play(_ event: HapticEvent) {
        let device = WKInterfaceDevice.current()
        let type: WKHapticType
        switch event {
        case .setStart: type = .start
        case .restWarning: type = .notification
        case .restEnd: type = .success
        case .workoutComplete: type = .success
        }
        Task { @MainActor in
            device.play(type)
            if event == .workoutComplete {
                try? await Task.sleep(nanoseconds: 250_000_000)
                device.play(.success)
            }
        }
    }
}
