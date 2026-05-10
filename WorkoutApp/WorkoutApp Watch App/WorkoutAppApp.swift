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
        let context = ModelContext(container)
        SeedData.seedIfEmpty(context: context)
    }

    var body: some Scene {
        WindowGroup {
            TemplateListView()
        }
        .modelContainer(container)
    }
}
