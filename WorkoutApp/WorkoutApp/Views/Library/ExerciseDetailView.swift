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
    @State private var progressionStep: Double?

    init(exercise: Exercise? = nil) {
        self.exercise = exercise
        _name = State(initialValue: exercise?.name ?? "")
        _kind = State(initialValue: exercise?.kind ?? .reps)
        _defaultRestSec = State(initialValue: exercise?.defaultRestSec ?? 90)
        _defaultTargetReps = State(initialValue: exercise?.defaultTargetReps)
        _defaultTargetDurationSec = State(initialValue: exercise?.defaultTargetDurationSec)
        _defaultTargetDistanceM = State(initialValue: exercise?.defaultTargetDistanceM)
        _progressionStep = State(initialValue: exercise?.progressionStep)
    }

    /// The axis this exercise gets harder along. A weight on a reps exercise moves it from
    /// counting reps to adding load, which changes what the step below means — so the field
    /// is labelled in the resolved unit rather than in kilograms by default.
    private var dimension: ProgressionDimension {
        ProgressionDimension.resolve(kind: kind, hasTargetWeight: false)
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
            Section {
                progressionStepField
            } header: {
                Text("Progression")
            } footer: {
                Text(progressionFooter)
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

    @ViewBuilder
    private var progressionStepField: some View {
        if dimension == .duration {
            VStack(alignment: .leading, spacing: 8) {
                Text("Step")
                OptionalDurationField(value: durationStepBinding)
            }
        } else {
            HStack {
                Text("Step")
                Spacer()
                // Placeholder is the default rather than the unit, so the trailing unit
                // label does not read as "reps reps". The unit has to stay visible: it
                // changes with the exercise's type, and the same stored number means
                // kilograms on one and seconds on another.
                OptionalDoubleField(
                    label: formattedStep(dimension.defaultStep),
                    value: $progressionStep,
                    width: 90
                )
                Text(dimension.unitLabel)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var durationStepBinding: Binding<Int?> {
        Binding(
            get: { progressionStep.map { Int($0) } },
            set: { progressionStep = $0.map(Double.init) }
        )
    }

    private var progressionFooter: String {
        let amount = stepPhrase
        let source = progressionStep == nil ? " by default" : ""
        switch kind {
        case .reps:
            return "Adds \(amount)\(source) when every set hits its target. Putting a weight on this exercise's sets switches progression to load instead."
        case .timed:
            return "Adds \(amount)\(source) when every set hits its target. A weighted hold still progresses on time, never on the plate."
        case .distance:
            return "Adds \(amount)\(source) when every set hits its target."
        }
    }

    private var stepPhrase: String {
        let step = progressionStep ?? dimension.defaultStep
        let value = formattedStep(step)
        switch dimension {
        case .reps:
            return step == 1 ? "1 rep" : "\(value) reps"
        case .load:
            return "\(value) kg"
        case .duration:
            return step == 1 ? "1 second" : "\(value) seconds"
        case .distance:
            return "\(value) m"
        }
    }

    private func formattedStep(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.4g", value)
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
            existing.progressionStep = progressionStep
        } else {
            let ex = Exercise(
                name: trimmed,
                kind: kind,
                defaultRestSec: defaultRestSec,
                defaultTargetReps: kind == .reps ? defaultTargetReps : nil,
                defaultTargetDurationSec: kind == .timed ? defaultTargetDurationSec : nil,
                defaultTargetDistanceM: kind == .distance ? defaultTargetDistanceM : nil,
                progressionStep: progressionStep
            )
            modelContext.insert(ex)
        }
    }
}
