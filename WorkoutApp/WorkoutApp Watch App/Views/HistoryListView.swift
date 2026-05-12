import SwiftUI
import SwiftData
import WorkoutCore

struct HistoryListView: View {
    @Query(sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]

    private var recentSessions: [WorkoutSession] {
        Array(sessions.prefix(10))
    }

    var body: some View {
        NavigationStack {
            Group {
                if recentSessions.isEmpty {
                    ContentUnavailableView("No History", systemImage: "clock.arrow.circlepath")
                } else {
                    List(recentSessions) { session in
                        SessionHistoryRow(session: session)
                    }
                }
            }
            .navigationTitle("History")
        }
    }
}

private struct SessionHistoryRow: View {
    let session: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(session.templateName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(durationText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(durationStyle)
                    .lineLimit(1)
            }

            Text(dateText)
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text("\(session.orderedPerformedSets.count) sets")
                Text(volumeText)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.vertical, 3)
    }

    private var dateText: String {
        session.startedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private var durationText: String {
        guard let durationSec = session.durationSec else { return "In progress" }
        return formatDuration(durationSec)
    }

    private var volumeText: String {
        "\(formatVolume(session.totalVolumeKg)) kg"
    }

    private var durationStyle: AnyShapeStyle {
        session.isFinished ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange)
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume.rounded() == volume {
            return String(format: "%.0f", volume)
        }
        return String(format: "%.1f", volume)
    }
}
