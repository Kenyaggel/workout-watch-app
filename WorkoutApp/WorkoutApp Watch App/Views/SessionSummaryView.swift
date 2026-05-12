import SwiftUI
import WorkoutCore

struct SessionSummaryView: View {
    let session: WorkoutSession?
    let onDone: () -> Void

    private var durationString: String {
        guard let secs = session?.durationSec else { return "—" }
        let m = secs / 60, s = secs % 60
        return String(format: "%dm %02ds", m, s)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Workout complete").font(.headline)
                if let session {
                    LabelRow(label: "Template", value: session.templateName)
                    LabelRow(label: "Sets", value: "\(session.performedSets.count)")
                    LabelRow(label: "Volume", value: volumeString(for: session))
                    LabelRow(label: "Duration", value: durationString)
                }
                Button(action: onDone) {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 6)
            }
            .padding(.horizontal, 6)
        }
    }

    private func volumeString(for session: WorkoutSession) -> String {
        let volume = session.totalVolumeKg
        if volume.rounded() == volume {
            return String(format: "%.0f kg", volume)
        }
        return String(format: "%.1f kg", volume)
    }
}

private struct LabelRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption).monospacedDigit()
        }
    }
}
