import SwiftUI
import WorkoutCore

struct PrepView: View {
    @Bindable var engine: SessionEngine
    let startedAt: Date
    let isLuminanceReduced: Bool

    private var nextExerciseName: String? {
        guard case let .prep(_, next) = engine.phase else { return nil }
        return engine.plan.exercise(at: next)?.name
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("Up next").font(.caption2).foregroundStyle(.secondary)
            if let name = nextExerciseName {
                Text(name).font(.headline).lineLimit(2).multilineTextAlignment(.center)
            }
            TimelineView(.periodic(from: startedAt, by: 1)) { ctx in
                let secs = max(0, Int(ctx.date.timeIntervalSince(startedAt)))
                Text(formatMMSS(secs))
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isLuminanceReduced ? .white : .primary)
            }
            Spacer(minLength: 0)
            Button {
                engine.startNextExercise()
            } label: {
                Text("Start exercise").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding()
    }
}

private func formatMMSS(_ s: Int) -> String {
    let m = s / 60, r = s % 60
    return String(format: "%d:%02d", m, r)
}
