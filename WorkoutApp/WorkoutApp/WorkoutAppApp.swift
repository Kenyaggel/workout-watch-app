import SwiftUI
import SwiftData
import WorkoutCore

@main
struct WorkoutAppApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try WorkoutModelContainer.makeShared()
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
