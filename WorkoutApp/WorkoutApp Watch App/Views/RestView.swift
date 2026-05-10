import SwiftUI
import WorkoutCore

struct RestView: View {
    @Bindable var engine: SessionEngine
    let endsAt: Date
    let isLuminanceReduced: Bool

    private var totalDuration: TimeInterval {
        guard case let .rest(_, justCompleted, _) = engine.phase,
              let set = engine.plan.set(at: justCompleted) else { return 0 }
        return TimeInterval(set.restSec)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let remaining = max(0, endsAt.timeIntervalSince(ctx.date))
            let progress = totalDuration > 0
                ? min(1, max(0, 1 - remaining / totalDuration))
                : 1

            ZStack {
                Circle()
                    .stroke(.white.opacity(isLuminanceReduced ? 0.15 : 0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        remaining <= 10 ? Color.orange : Color.green,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: progress)

                VStack(spacing: 2) {
                    Text("Rest").font(.caption2).foregroundStyle(.secondary)
                    Text(formatMMSS(Int(ceil(remaining))))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            }
            .padding(8)
            .onChange(of: remaining) { _, newValue in
                if newValue == 0 { engine.restAutoExpired() }
            }
            .overlay(alignment: .bottom) {
                Button {
                    engine.skipRest()
                } label: {
                    Text("Skip")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 18)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 2)
            }
        }
    }
}

private func formatMMSS(_ s: Int) -> String {
    let m = s / 60, r = s % 60
    return String(format: "%d:%02d", m, r)
}
