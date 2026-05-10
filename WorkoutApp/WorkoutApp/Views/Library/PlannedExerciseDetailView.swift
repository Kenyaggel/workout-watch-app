import SwiftUI
import SwiftData
import WorkoutCore

struct PlannedExerciseDetailView: View {
    @Bindable var plannedExercise: PlannedExercise
    @Environment(\.modelContext) private var modelContext

    private var exerciseKind: ExerciseKind {
        plannedExercise.exercise?.kind ?? .reps
    }

    var body: some View {
        List {
            ForEach(plannedExercise.orderedSets) { ps in
                PlannedSetRow(plannedSet: ps, kind: exerciseKind)
            }
            .onDelete(perform: deleteSets)
            .onMove(perform: moveSets)
        }
        .navigationTitle(plannedExercise.exercise?.name ?? "Exercise")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let ps = PlannedSet(orderIndex: plannedExercise.orderedSets.count)
                    ps.plannedExercise = plannedExercise
                    modelContext.insert(ps)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
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
            HStack {
                Text("Rest override (sec)")
                    .foregroundStyle(.secondary)
                Spacer()
                OptionalIntField(
                    label: "sec",
                    value: $plannedSet.restOverrideSec
                )
            }
        }
        .font(.subheadline)
    }
}

private struct OptionalDoubleField: View {
    let label: String
    @Binding var value: Double?
    @State private var text: String = ""

    var body: some View {
        TextField(label, text: $text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 80)
            .onAppear {
                if let v = value { text = String(v) }
            }
            .onChange(of: text) { _, newValue in
                value = Double(newValue)
            }
    }
}

private struct OptionalIntField: View {
    let label: String
    @Binding var value: Int?
    @State private var text: String = ""

    var body: some View {
        TextField(label, text: $text)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 80)
            .onAppear {
                if let v = value { text = String(v) }
            }
            .onChange(of: text) { _, newValue in
                value = Int(newValue)
            }
    }
}
