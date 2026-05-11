import SwiftUI
import SwiftData
import WorkoutCore

struct PlannedExerciseDetailView: View {
    @Bindable var plannedExercise: PlannedExercise
    @Environment(\.modelContext) private var modelContext

    private var exerciseKind: ExerciseKind {
        plannedExercise.exercise?.kind ?? .reps
    }

    private var restSecBinding: Binding<Int> {
        Binding(
            get: { plannedExercise.resolvedRestSec },
            set: { plannedExercise.restSec = $0 }
        )
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Rest between sets")
                    Spacer()
                    RequiredIntField(label: "sec", value: restSecBinding)
                }
            }
            Section("Sets") {
                ForEach(plannedExercise.orderedSets) { ps in
                    PlannedSetRow(plannedSet: ps, kind: exerciseKind)
                }
                .onDelete(perform: deleteSets)
                .onMove(perform: moveSets)
            }
        }
        .navigationTitle(plannedExercise.exercise?.name ?? "Exercise")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let ps = nextPlannedSet()
                    ps.plannedExercise = plannedExercise
                    modelContext.insert(ps)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    private func nextPlannedSet() -> PlannedSet {
        let orderedSets = plannedExercise.orderedSets
        let source = orderedSets.last
        let exercise = plannedExercise.exercise
        return PlannedSet(
            orderIndex: orderedSets.count,
            targetWeightKg: source?.targetWeightKg,
            targetReps: source?.targetReps ?? exercise?.defaultTargetReps ?? (exerciseKind == .reps ? 10 : nil),
            targetDurationSec: source?.targetDurationSec ?? exercise?.defaultTargetDurationSec ?? (exerciseKind == .timed ? 30 : nil),
            targetDistanceM: source?.targetDistanceM ?? exercise?.defaultTargetDistanceM ?? (exerciseKind == .distance ? 1000 : nil)
        )
    }

    private func deleteSets(at offsets: IndexSet) {
        let ordered = plannedExercise.orderedSets
        for index in offsets {
            modelContext.delete(ordered[index])
        }
    }

    private func moveSets(from source: IndexSet, to destination: Int) {
        var ordered = plannedExercise.orderedSets
        ordered.move(fromOffsets: source, toOffset: destination)
        for (newIndex, ps) in ordered.enumerated() {
            ps.orderIndex = newIndex
        }
    }
}

private struct PlannedSetRow: View {
    @Bindable var plannedSet: PlannedSet
    let kind: ExerciseKind

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if kind == .reps || kind == .timed {
                HStack {
                    Text("Weight (kg)")
                    Spacer()
                    OptionalDoubleField(
                        label: "kg",
                        value: $plannedSet.targetWeightKg
                    )
                }
            }
            if kind == .reps {
                HStack {
                    Text("Reps")
                    Spacer()
                    OptionalIntField(
                        label: "reps",
                        value: $plannedSet.targetReps
                    )
                }
            }
            if kind == .timed {
                HStack {
                    Text("Duration (sec)")
                    Spacer()
                    OptionalIntField(
                        label: "sec",
                        value: $plannedSet.targetDurationSec
                    )
                }
            }
            if kind == .distance {
                HStack {
                    Text("Distance (m)")
                    Spacer()
                    OptionalDoubleField(
                        label: "m",
                        value: $plannedSet.targetDistanceM
                    )
                }
            }
        }
        .font(.subheadline)
    }
}

