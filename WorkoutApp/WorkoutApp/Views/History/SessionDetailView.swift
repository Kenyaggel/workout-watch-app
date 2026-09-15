import SwiftUI
import WorkoutCore

struct SessionDetailView: View {
    let session: WorkoutSession

    var body: some View {
        let groups = exerciseGroups(from: session.orderedPerformedSets)

        List {
            Section {
                LabeledContent("Started", value: formattedDate(session.startedAt))
                LabeledContent("Duration", value: durationText)
                LabeledContent("Sets", value: "\(session.orderedPerformedSets.count)")
                LabeledContent("Volume", value: volumeText)
            }

            if groups.isEmpty {
                ContentUnavailableView("No Sets Recorded", systemImage: "list.bullet.clipboard")
            } else {
                ForEach(groups, id: \.exerciseIndex) { group in
                    Section(header: ExerciseSectionHeader(group: group)) {
                        ForEach(group.sets.sorted { $0.setIndex < $1.setIndex }, id: \.id) { set in
                            SetRowView(set: set, session: session)
                        }
                    }
                }
            }
        }
        .navigationTitle(session.templateName)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(subtitleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var subtitleText: String {
        let date = formattedDate(session.startedAt)
        if let end = session.endedAt {
            return "\(date) · \(formatDuration(session.startedAt, end))"
        }
        return "\(date) · In progress"
    }

    private var durationText: String {
        guard let end = session.endedAt else { return "In progress" }
        return formatDuration(session.startedAt, end)
    }

    private var volumeText: String {
        let volume = session.totalVolumeKg
        if volume.rounded() == volume {
            return String(format: "%.0f kg", volume)
        }
        return String(format: "%.1f kg", volume)
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

            if let coachDeviationText {
                HStack {
                    Text("Coach")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: 48, alignment: .leading)
                    Text(coachDeviationText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

    /// Prefers the Target recorded on the set itself. Reading the workout's current
    /// `PlannedSet` instead would be wrong: the Coach moves a workout's targets over time,
    /// so a session from six weeks ago would re-render its plan against today's numbers and
    /// quietly show a lifter that they hit targets they never had. The live template is
    /// consulted only for sets performed before V3, which carry no recorded target.
    private var plannedText: String {
        if let text = targetText(
            weightKg: set.targetWeightKg,
            reps: set.targetReps,
            durationSec: set.targetDurationSec,
            distanceM: set.targetDistanceM
        ) {
            return text
        }

        guard let template = session.template else { return "—" }
        let exercises = template.orderedExercises
        guard let plannedExercise = exercises[safe: set.exerciseIndex] else { return "—" }
        guard let plannedSet = plannedExercise.orderedSets[safe: set.setIndex] else { return "—" }

        return targetText(
            weightKg: plannedSet.targetWeightKg,
            reps: plannedSet.targetReps,
            durationSec: plannedSet.targetDurationSec,
            distanceM: plannedSet.targetDistanceM
        ) ?? "—"
    }

    /// Nil when nothing was targeted at all, which is what lets `plannedText` tell "no
    /// recorded target" apart from "a target of nothing".
    private func targetText(
        weightKg: Double?,
        reps: Int?,
        durationSec: Int?,
        distanceM: Double?
    ) -> String? {
        var parts: [String] = []
        if let weightKg {
            parts.append(String(format: "%.1f kg", weightKg))
        }
        if let reps {
            parts.append("\(reps) reps")
        }
        if let durationSec {
            parts.append(formatSeconds(durationSec))
        }
        if let distanceM {
            parts.append(String(format: "%.0f m", distanceM))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// What the Coach proposed for this set, shown only when it differs from the Target
    /// that was actually run — that gap is the signal for whether the coach is any good.
    private var coachDeviationText: String? {
        guard let suggested = targetText(
            weightKg: set.suggestedWeightKg,
            reps: set.suggestedReps,
            durationSec: set.suggestedDurationSec,
            distanceM: set.suggestedDistanceM
        ) else { return nil }
        let ran = targetText(
            weightKg: set.targetWeightKg,
            reps: set.targetReps,
            durationSec: set.targetDurationSec,
            distanceM: set.targetDistanceM
        )
        return suggested == ran ? nil : suggested
    }

    private func formatSeconds(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        let s = seconds % 60
        return s == 0 ? "\(m)m" : "\(m)m \(s)s"
    }
}
