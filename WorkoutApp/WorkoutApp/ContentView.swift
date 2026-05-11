import SwiftUI
import SwiftData
import WorkoutCore

struct ContentView: View {
    @EnvironmentObject private var watchConnectivity: WatchConnectivityManager
    @Query(sort: \WorkoutTemplate.createdAt) private var templates: [WorkoutTemplate]

    var body: some View {
        TabView {
            NavigationStack { TemplateListView() }
                .tabItem { Label("Workouts", systemImage: "list.bullet.clipboard") }
            NavigationStack { ExerciseLibraryView() }
                .tabItem { Label("Exercises", systemImage: "figure.strengthtraining.traditional") }
            NavigationStack { SessionListView() }
                .tabItem { Label("History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") }
            NavigationStack { AnalyticsDashboardView() }
                .tabItem { Label("Analytics", systemImage: "chart.line.uptrend.xyaxis") }
        }
        .task {
            syncTemplatesToWatch()
        }
        .onChange(of: templateSyncSnapshot) { _, _ in
            syncTemplatesToWatch()
        }
    }

    private var templateSyncSnapshot: TemplateSyncSnapshot {
        TemplateSyncSnapshot(templates: templates)
    }

    private func syncTemplatesToWatch() {
        watchConnectivity.sendTemplateSnapshot(templates: templates)
    }
}

#Preview {
    ContentView()
        .environmentObject(
            WatchConnectivityManager(
                modelContainer: try! WorkoutModelContainer.makeShared(inMemory: true)
            )
        )
}
