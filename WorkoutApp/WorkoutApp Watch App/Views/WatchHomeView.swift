import SwiftUI

struct WatchHomeView: View {
    var body: some View {
        TabView {
            TemplateListView()
                .tabItem {
                    Label("Workouts", systemImage: "list.bullet.clipboard")
                }

            HistoryListView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
        }
    }
}
