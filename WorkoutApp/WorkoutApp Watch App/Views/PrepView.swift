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

    private var nextCursor: SetCursor? {
        guard case let .prep(_, next) = engine.phase else { return nil }
        return next
    }

    private var nextSet: SessionPlan.Set? {
        guard let nextCursor else { return nil }
        return engine.plan.set(at: nextCursor)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Up next").font(.caption2).foregroundStyle(.secondary)
                if let name = nextExerciseName {
                    Text(name)
                        .font(.headline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.center)
                }
                if let nextCursor,
                   let exercise = engine.plan.exercise(at: nextCursor),
                   let set = nextSet {
                    VStack(spacing: 2) {
                        Text("Set \(nextCursor.setIndex + 1) of \(exercise.sets.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(plannedTargetText(for: set, kind: exercise.kind))
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        Text(plannedRestText(set.restSec))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                TimelineView(.periodic(from: startedAt, by: 1)) { ctx in
                    let secs = max(0, Int(ctx.date.timeIntervalSince(startedAt)))
                    Text(formatMMSS(secs))
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isLuminanceReduced ? .white : .primary)
                }
                Button {
                    engine.startNextExercise()
                } label: {
                    Text("Start exercise").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .padding(.horizontal)
            .padding(.top, 18)
        }
    }
}

private func formatMMSS(_ s: Int) -> String {
    let m = s / 60, r = s % 60
    return String(format: "%d:%02d", m, r)
}
