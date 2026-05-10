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
                            Text("\(pe.sets.count) sets")
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
                    showExercisePicker = false
                }
            }
        }
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
