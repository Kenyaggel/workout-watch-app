import SwiftUI
import WorkoutCore

struct ContentView: View {
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
    }
}

#Preview {
    ContentView()
}
