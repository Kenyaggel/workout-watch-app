import SwiftUI
import WorkoutCore

struct PlanSummaryView: View {
    let plan: SessionPlan
    let onStart: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.templateName)
                        .font(.headline)
                        .lineLimit(2)
                    Text("\(plan.exercises.count) exercises · \(totalSets) sets")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(plan.exercises.enumerated()), id: \.offset) { _, exercise in
                    ExerciseSummaryRow(exercise: exercise)
                }

                Button(action: onStart) {
                    Text("Show up next")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .padding(.top, 2)
            }
            .padding(.horizontal, 6)
        }
    }

    private var totalSets: Int {
        plan.exercises.reduce(0) { $0 + $1.sets.count }
    }
}

private struct ExerciseSummaryRow: View {
    let exercise: SessionPlan.Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(exercise.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(summaryText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.06))
        )
    }

    private var summaryText: String {
        guard !exercise.sets.isEmpty else { return "No planned sets" }

        let grouped = Dictionary(grouping: exercise.sets) { set in
            plannedTargetText(for: set, kind: exercise.kind)
        }

        if grouped.count == 1, let target = grouped.keys.first {
            return "\(exercise.sets.count) sets · \(target)"
        }

        return exercise.sets.enumerated()
            .map { index, set in
                "S\(index + 1) \(plannedTargetText(for: set, kind: exercise.kind))"
            }
            .joined(separator: " · ")
    }
}
