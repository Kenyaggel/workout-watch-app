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
    @State private var defaultTargetReps: Int?
    @State private var defaultTargetDurationSec: Int?
    @State private var defaultTargetDistanceM: Double?

    init(exercise: Exercise? = nil) {
        self.exercise = exercise
        _name = State(initialValue: exercise?.name ?? "")
        _kind = State(initialValue: exercise?.kind ?? .reps)
        _defaultRestSec = State(initialValue: exercise?.defaultRestSec ?? 90)
        _defaultTargetReps = State(initialValue: exercise?.defaultTargetReps)
        _defaultTargetDurationSec = State(initialValue: exercise?.defaultTargetDurationSec)
        _defaultTargetDistanceM = State(initialValue: exercise?.defaultTargetDistanceM)
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
            Section("Defaults") {
                Stepper(value: $defaultRestSec, in: 0...600, step: 15) {
                    LabeledContent("Rest", value: "\(defaultRestSec) sec")
                }
                switch kind {
                case .reps:
                    HStack {
                        Text("Reps")
                        Spacer()
                        OptionalIntField(label: "reps", value: $defaultTargetReps, width: 90)
                    }
                case .timed:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Duration")
                        OptionalDurationField(value: $defaultTargetDurationSec)
                    }
                case .distance:
                    HStack {
                        Text("Distance")
                        Spacer()
                        OptionalDoubleField(label: "m", value: $defaultTargetDistanceM, width: 90)
                    }
                }
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
            existing.defaultTargetReps = kind == .reps ? defaultTargetReps : nil
            existing.defaultTargetDurationSec = kind == .timed ? defaultTargetDurationSec : nil
            existing.defaultTargetDistanceM = kind == .distance ? defaultTargetDistanceM : nil
        } else {
            let ex = Exercise(
                name: trimmed,
                kind: kind,
                defaultRestSec: defaultRestSec,
                defaultTargetReps: kind == .reps ? defaultTargetReps : nil,
                defaultTargetDurationSec: kind == .timed ? defaultTargetDurationSec : nil,
                defaultTargetDistanceM: kind == .distance ? defaultTargetDistanceM : nil
            )
            modelContext.insert(ex)
        }
    }
}
