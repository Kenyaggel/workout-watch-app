import SwiftUI
import SwiftData
import WorkoutCore

@main
struct WorkoutAppApp: App {
    let container: ModelContainer
    @StateObject private var watchConnectivity: WatchConnectivityManager

    init() {
        do {
            let container = try WorkoutModelContainer.makeShared()
            self.container = container
            _watchConnectivity = StateObject(
                wrappedValue: WatchConnectivityManager(modelContainer: container)
            )
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(watchConnectivity)
                .task {
                    watchConnectivity.activate()
                }
        }
        .modelContainer(container)
    }
}
