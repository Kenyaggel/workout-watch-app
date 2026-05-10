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
                Button {
                    if isPickMode {
                        onPick?(exercise)
                        dismiss()
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                                .foregroundStyle(.primary)
                            Text(exercise.kind.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isPickMode {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: isPickMode ? nil : deleteExercises)
        }
        .navigationTitle("Exercises")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateExercise = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            if isPickMode {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
