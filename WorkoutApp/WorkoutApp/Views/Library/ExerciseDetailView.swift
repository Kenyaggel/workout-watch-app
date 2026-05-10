import SwiftUI
import SwiftData
import WorkoutCore

struct ExerciseDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var exercise: Exercise? = nil

    @State private var name: String
    @State private var kind: ExerciseKind
    @State private var defaultRestSec: Int

    init(exercise: Exercise? = nil) {
        self.exercise = exercise
        _name = State(initialValue: exercise?.name ?? "")
        _kind = State(initialValue: exercise?.kind ?? .reps)
        _defaultRestSec = State(initialValue: exercise?.defaultRestSec ?? 90)
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Exercise name", text: $name)
            }
            Section("Type") {
                Picker("Kind", selection: $kind) {
                    ForEach(ExerciseKind.allCases, id: \.self) { k in
                        Text(k.displayName).tag(k)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("Default Rest") {
                Stepper("\(defaultRestSec) seconds", value: $defaultRestSec, in: 0...600, step: 15)
            }
        }
        .navigationTitle(exercise == nil ? "New Exercise" : "Edit Exercise")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save") {
                    save()
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let existing = exercise {
            existing.name = trimmed
            existing.kind = kind
            existing.defaultRestSec = defaultRestSec
        } else {
            let ex = Exercise(name: trimmed, kind: kind, defaultRestSec: defaultRestSec)
            modelContext.insert(ex)
        }
    }
}
