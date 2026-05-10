import SwiftUI
import WorkoutCore

struct SessionDetailView: View {
    let session: WorkoutSession

    var body: some View {
        let groups = exerciseGroups(from: session.orderedPerformedSets)

        List {
            ForEach(groups, id: \.exerciseIndex) { group in
                Section(header: ExerciseSectionHeader(group: group, session: session)) {
                    ForEach(group.sets.sorted { $0.setIndex < $1.setIndex }, id: \.id) { set in
                        SetRowView(set: set, session: session)
                    }
                }
            }
        }
        .navigationTitle(session.templateName)
        .navigationSubtitle(subtitleText)
    }

    private var subtitleText: String {
        let date = formattedDate(session.startedAt)
        if let end = session.endedAt {
            return "\(date) · \(formatDuration(session.startedAt, end))"
        }
        return "\(date) · In progress"
    }
}

// MARK: - Exercise grouping

private struct ExerciseGroup {
    let exerciseIndex: Int
    let sets: [PerformedSet]
}

private func exerciseGroups(from sets: [PerformedSet]) -> [ExerciseGroup] {
    var seen: [Int: [PerformedSet]] = [:]
    var order: [Int] = []
    for set in sets {
        if seen[set.exerciseIndex] == nil {
            order.append(set.exerciseIndex)
        }
        seen[set.exerciseIndex, default: []].append(set)
    }
    return order.map { ExerciseGroup(exerciseIndex: $0, sets: seen[$0]!) }
}

// MARK: - Section header

private struct ExerciseSectionHeader: View {
    let group: ExerciseGroup
    let session: WorkoutSession

    var body: some View {
        HStack {
            Text(group.sets.first?.exerciseName ?? "Unknown")
            Spacer()
            if let volume = totalVolume {
                Text(String(format: "%.1f kg total", volume))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var totalVolume: Double? {
        let contributions = group.sets.compactMap { set -> Double? in
            guard let weight = set.weightKg, let reps = set.reps else { return nil }
            return weight * Double(reps)
        }
        guard !contributions.isEmpty else { return nil }
        return contributions.reduce(0, +)
    }
}

// MARK: - Set row

private struct SetRowView: View {
    let set: PerformedSet
    let session: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Actual row
            HStack {
                Text("Set \(set.setIndex + 1)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(width: 48, alignment: .leading)
                Text(actualText)
                    .font(.subheadline)
                Spacer()
                if let rpe = set.rpe {
                    Text("RPE \(rpe)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Planned row
            HStack {
                Text("Plan")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 48, alignment: .leading)
                Text(plannedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var actualText: String {
        var parts: [String] = []
        if let weight = set.weightKg {
            parts.append(String(format: "%.1f kg", weight))
        }
        if let reps = set.reps {
            parts.append("\(reps) reps")
        }
        if let duration = set.durationSec {
            parts.append(formatSeconds(duration))
        }
        if let distance = set.distanceM {
            parts.append(String(format: "%.0f m", distance))
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private var plannedText: String {
        guard let template = session.template else { return "—" }
        let exercises = template.orderedExercises
        guard let plannedExercise = exercises[safe: set.exerciseIndex] else { return "—" }
        guard let plannedSet = plannedExercise.orderedSets[safe: set.setIndex] else { return "—" }

        var parts: [String] = []
        if let weight = plannedSet.targetWeightKg {
            parts.append(String(format: "%.1f kg", weight))
        }
        if let reps = plannedSet.targetReps {
            parts.append("\(reps) reps")
        }
        if let duration = plannedSet.targetDurationSec {
            parts.append(formatSeconds(duration))
        }
        if let distance = plannedSet.targetDistanceM {
            parts.append(String(format: "%.0f m", distance))
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func formatSeconds(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        let s = seconds % 60
        return s == 0 ? "\(m)m" : "\(m)m \(s)s"
    }
}

// MARK: - Helpers

private func formattedDate(_ date: Date) -> String {
    date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
}
