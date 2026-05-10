import SwiftUI
import WorkoutCore

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack { TemplateListView() }
                .tabItem { Label("Library", systemImage: "books.vertical") }
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
