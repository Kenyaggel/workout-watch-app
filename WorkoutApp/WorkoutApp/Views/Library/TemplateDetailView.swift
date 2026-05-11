import SwiftUI
import SwiftData
import WorkoutCore

struct TemplateDetailView: View {
    @Bindable var template: WorkoutTemplate
    @Environment(\.modelContext) private var modelContext
    @State private var showExercisePicker = false

    var body: some View {
        List {
            Section {
                TextField("Template name", text: $template.name)
            }
            Section {
                ForEach(template.orderedExercises) { pe in
                    NavigationLink(value: pe) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pe.exercise?.name ?? "Unknown")
                            Text(summary(for: pe))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteExercises)
                .onMove(perform: moveExercises)
            }
        }
        .navigationTitle(template.name)
        .navigationDestination(for: PlannedExercise.self) { pe in
            PlannedExerciseDetailView(plannedExercise: pe)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showExercisePicker = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showExercisePicker) {
            NavigationStack {
                ExerciseLibraryView(isPickMode: true) { picked in
                    let pe = PlannedExercise(
                        orderIndex: template.orderedExercises.count,
                        exercise: picked
                    )
                    pe.template = template
                    modelContext.insert(pe)
                    for i in 0..<3 {
                        let ps = makeDefaultSet(for: picked, orderIndex: i)
                        ps.plannedExercise = pe
                        modelContext.insert(ps)
                    }
                    showExercisePicker = false
                }
            }
        }
    }

    private func makeDefaultSet(for exercise: Exercise, orderIndex: Int) -> PlannedSet {
        switch exercise.kind {
        case .reps:
            return PlannedSet(orderIndex: orderIndex, targetReps: exercise.defaultTargetReps)
        case .timed:
            return PlannedSet(orderIndex: orderIndex, targetDurationSec: exercise.defaultTargetDurationSec)
        case .distance:
            return PlannedSet(orderIndex: orderIndex, targetDistanceM: exercise.defaultTargetDistanceM)
        }
    }

    private func summary(for pe: PlannedExercise) -> String {
        let setCount = pe.sets.count
        let kind = pe.exercise?.kind ?? .reps
        let first = pe.orderedSets.first

        var parts: [String] = ["\(setCount) set\(setCount == 1 ? "" : "s")"]
        let weightStr = first?.targetWeightKg.map { String(format: "%.4g kg", $0) }

        switch kind {
        case .reps:
            if let w = weightStr, let r = first?.targetReps {
                parts.append("\(w) × \(r)")
            } else if let w = weightStr {
                parts.append(w)
            } else if let r = first?.targetReps {
                parts.append("\(r) reps")
            }
        case .timed:
            if let d = first?.targetDurationSec {
                var s = "\(d)s"
                if let w = weightStr { s += " @ \(w)" }
                parts.append(s)
            } else if let w = weightStr {
                parts.append(w)
            }
        case .distance:
            if let dist = first?.targetDistanceM {
                parts.append(String(format: "%.0f m", dist))
            }
        }

        return parts.joined(separator: " · ")
    }

    private func deleteExercises(at offsets: IndexSet) {
        let ordered = template.orderedExercises
        for index in offsets {
            modelContext.delete(ordered[index])
        }
    }

    private func moveExercises(from source: IndexSet, to destination: Int) {
        var ordered = template.orderedExercises
        ordered.move(fromOffsets: source, toOffset: destination)
        for (newIndex, pe) in ordered.enumerated() {
            pe.orderIndex = newIndex
        }
    }
}
