import SwiftUI
import WatchKit
import WorkoutCore

struct InSetView: View {
    @Bindable var engine: SessionEngine
    let cursor: SetCursor
    let setStartedAt: Date
    let isLuminanceReduced: Bool

    @State private var weightKg: Double = 0
    @State private var reps: Int = 0
    @State private var rpe: Int = 7

    /// Visual + crown ownership for the weight row.
    /// `false` → ScrollView owns the crown; weight row appears locked.
    /// `true`  → weight row is highlighted and owns the crown.
    @State private var weightActive: Bool = false
    @State private var ignoreNextContainerTap: Bool = false
    @FocusState private var weightHasFocus: Bool

    private var set: SessionPlan.Set? { engine.plan.set(at: cursor) }
    private var exercise: SessionPlan.Exercise? { engine.plan.exercise(at: cursor) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let exercise {
                    Text(exercise.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text("Set \(cursor.setIndex + 1) of \(exercise.sets.count)  ·  \(engine.setNumber(of: cursor)) of \(engine.totalSets)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                elapsedRow

                if let set, exercise?.kind == .reps {
                    weightRow(target: set.targetWeightKg)
                    repsRow
                    rpeRow
                } else if exercise?.kind == .timed {
                    Text(set?.targetDurationSec.map { "Target: \($0)s" } ?? "Hold")
                        .font(.caption)
                    rpeRow
                } else if exercise?.kind == .distance {
                    Text(set?.targetDistanceM.map { "Target: \(Int($0))m" } ?? "Distance")
                        .font(.caption)
                    rpeRow
                }

                doneButton
                    .padding(.top, 4)
            }
            .padding(.horizontal, 6)
        }
        .scrollDisabled(weightActive)
        .onAppear {
            primeFromTargets()
            releaseWeight()
        }
        .onChange(of: cursor) { _, _ in
            primeFromTargets()
            releaseWeight()
        }
        // If focus is lost (e.g. the user taps away), make sure the visual matches.
        .onChange(of: weightHasFocus) { _, hasFocus in
            if !hasFocus { weightActive = false }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if ignoreNextContainerTap {
                ignoreNextContainerTap = false
            } else if weightActive {
                releaseWeight()
            }
        }
    }

    private func releaseWeight() {
        weightActive = false
        weightHasFocus = false
    }

    private func toggleWeight() {
        if weightActive {
            releaseWeight()
        } else {
            ignoreNextContainerTap = true
            weightActive = true
            Task { @MainActor in
                await Task.yield()
                weightHasFocus = true
                ignoreNextContainerTap = false
            }
        }
        WKInterfaceDevice.current().play(.click)
    }

    // MARK: - Sub-views

    private var elapsedRow: some View {
        TimelineView(.periodic(from: setStartedAt, by: 1)) { ctx in
            let secs = max(0, Int(ctx.date.timeIntervalSince(setStartedAt)))
            Text(formatMMSS(secs))
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isLuminanceReduced ? .white : .primary)
        }
    }

    private func weightRow(target: Double?) -> some View {
        Button(action: toggleWeight) {
            HStack(spacing: 6) {
                Text("Weight")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text("\(weightKg, specifier: "%.1f") kg")
                    .font(.system(.body, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(weightActive ? .yellow : .primary)
                Image(systemName: weightActive
                      ? "digitalcrown.arrow.clockwise"
                      : "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(weightActive ? .yellow : .secondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(weightActive ? Color.yellow.opacity(0.18) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(weightActive ? Color.yellow : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .focusable(weightActive)
        .focused($weightHasFocus)
        .digitalCrownRotation(
            $weightKg,
            from: 0, through: 500, by: 0.5,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
    }

    private var repsRow: some View {
        counterRow(label: "Reps", value: reps, range: 0...100) { reps = $0 }
    }

    private var rpeRow: some View {
        counterRow(label: "RPE", value: rpe, range: 1...10) { rpe = $0 }
    }

    /// Compact +/- row that doesn't auto-claim the Digital Crown.
    @ViewBuilder
    private func counterRow(
        label: String,
        value: Int,
        range: ClosedRange<Int>,
        onChange: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            stepperButton(systemImage: "minus",
                          enabled: value > range.lowerBound) {
                let next = max(range.lowerBound, value - 1)
                if next != value { onChange(next) }
            }
            stepperButton(systemImage: "plus",
                          enabled: value < range.upperBound) {
                let next = min(range.upperBound, value + 1)
                if next != value { onChange(next) }
            }
        }
        .padding(.vertical, 6)
    }

    private func stepperButton(
        systemImage: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.bold))
                .frame(width: 36, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(enabled ? 0.18 : 0.06))
                )
                .foregroundStyle(enabled ? .primary : .tertiary)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var doneButton: some View {
        Button {
            releaseWeight()
            engine.completeSet(
                weightKg: exercise?.kind == .reps ? weightKg : nil,
                reps: exercise?.kind == .reps ? reps : nil,
                durationSec: exercise?.kind == .timed
                    ? Int(Date().timeIntervalSince(setStartedAt))
                    : nil,
                rpe: rpe
            )
        } label: {
            Text("Done").font(.headline).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
    }

    private func primeFromTargets() {
        guard let set else { return }
        if let w = set.targetWeightKg { weightKg = w }
        if let r = set.targetReps { reps = r }
    }
}

private func formatMMSS(_ s: Int) -> String {
    let m = s / 60, r = s % 60
    return String(format: "%d:%02d", m, r)
}
