import SwiftUI
import SwiftData
import WorkoutCore

struct SessionListView: View {
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) var sessions: [WorkoutSession]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if sessions.isEmpty {
                ContentUnavailableView("No Workouts", systemImage: "dumbbell")
            } else {
                List {
                    ForEach(sessions) { session in
                        NavigationLink(destination: SessionDetailView(session: session)) {
                            SessionRowView(session: session)
                        }
                    }
                    .onDelete(perform: deleteSessions)
                }
            }
        }
        .navigationTitle("History")
    }

    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(sessions[index])
        }
    }
}

private struct SessionRowView: View {
    let session: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.templateName)
                    .font(.headline)
                Spacer()
                durationLabel
                    .font(.subheadline)
                    .foregroundStyle(session.isFinished ? .primary : .orange)
            }
            HStack {
                Text(formattedDate(session.startedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(session.orderedPerformedSets.count) sets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var durationLabel: some View {
        if let end = session.endedAt {
            return Text(formatDuration(session.startedAt, end))
        } else {
            return Text("In progress")
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }
}

private func formatDuration(_ start: Date, _ end: Date) -> String {
    let minutes = Int(end.timeIntervalSince(start) / 60)
    if minutes < 60 { return "\(minutes)m" }
    return "\(minutes / 60)h \(minutes % 60)m"
}
