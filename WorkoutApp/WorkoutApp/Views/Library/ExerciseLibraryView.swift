import SwiftUI
import SwiftData
import WorkoutCore

struct ExerciseLibraryView: View {
    @Query(sort: \Exercise.name) var exercises: [Exercise]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    var isPickMode: Bool = false
    var onPick: ((Exercise) -> Void)? = nil
    @State private var showCreateExercise = false

    var body: some View {
        List {
            ForEach(exercises) { exercise in
                ExerciseRow(exercise: exercise, isPickMode: isPickMode) {
                    onPick?(exercise)
                    dismiss()
                }
            }
            .onDelete { offsets in
                if !isPickMode { deleteExercises(at: offsets) }
            }
        }
        .navigationTitle("Exercises")
        .navigationDestination(for: Exercise.self) { exercise in
            ExerciseDetailView(exercise: exercise)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateExercise = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateExercise) {
            NavigationStack {
                ExerciseDetailView()
            }
        }
    }

    private func deleteExercises(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(exercises[index])
        }
    }
}

private struct ExerciseRow: View {
    let exercise: Exercise
    let isPickMode: Bool
    let onPick: () -> Void

    var body: some View {
        if isPickMode {
            Button(action: onPick) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name).foregroundStyle(.primary)
                        Text(exercise.kind.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: exercise) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                    Text(exercise.kind.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
