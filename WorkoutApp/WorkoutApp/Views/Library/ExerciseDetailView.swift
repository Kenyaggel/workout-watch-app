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
    @State private var loadProgressionStep: Double?

    init(exercise: Exercise? = nil) {
        self.exercise = exercise
        _name = State(initialValue: exercise?.name ?? "")
        _kind = State(initialValue: exercise?.kind ?? .reps)
        _defaultRestSec = State(initialValue: exercise?.defaultRestSec ?? 90)
        _defaultTargetReps = State(initialValue: exercise?.defaultTargetReps)
        _defaultTargetDurationSec = State(initialValue: exercise?.defaultTargetDurationSec)
        _defaultTargetDistanceM = State(initialValue: exercise?.defaultTargetDistanceM)
        _progressionStep = State(initialValue: exercise?.progressionStep)
        _loadProgressionStep = State(initialValue: exercise?.loadProgressionStepKg)
    }

    /// The exercise's kind-natural axis — what it progresses on when no weight is in play.
    private var naturalDimension: ProgressionDimension {
        ProgressionDimension.resolve(kind: kind, hasTargetWeight: false)
    }

    /// A reps exercise has two axes, and which one applies is a property of the *slot*, not
    /// of the exercise: weighted pull-ups progress on load, bodyweight pull-ups on reps. The
    /// same exercise can appear both ways in different workouts, so both steps are offered
    /// here rather than guessed.
    private var showsLoadStep: Bool { kind == .reps }

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
                progressionStepFields
            } header: {
                Text("Progression")
            } footer: {
                Text(progressionFooter)
            }
        }
        .onChange(of: kind) { _, _ in
            // Each step is read in its own axis's unit, so a value typed as 50 metres would
            // be read as 50 seconds after a switch to Timed — and 50 is inside the
            // sanitizer's tolerance for a 5 second default, so it would auto-apply.
            // Clearing falls back to the new dimension's own default.
            progressionStep = nil
            loadProgressionStep = nil
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
    private var progressionStepFields: some View {
        if showsLoadStep {
            stepRow(
                title: "Weight step",
                dimension: .load,
                value: $loadProgressionStep
            )
            stepRow(
                title: "Reps step",
                dimension: .reps,
                value: $progressionStep
            )
        } else if naturalDimension == .duration {
            VStack(alignment: .leading, spacing: 8) {
                Text("Duration step")
                OptionalDurationField(value: durationStepBinding)
            }
        } else {
            stepRow(
                title: "Distance step",
                dimension: naturalDimension,
                value: $progressionStep
            )
        }
    }

    private func stepRow(
        title: String,
        dimension: ProgressionDimension,
        value: Binding<Double?>
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            // Placeholder is the default rather than the unit, so the trailing unit label
            // does not read as "reps reps".
            OptionalDoubleField(
                label: formattedStep(dimension.defaultStep),
                value: value,
                width: 90
            )
            Text(dimension.unitLabel)
                .foregroundStyle(.secondary)
        }
    }

    private var durationStepBinding: Binding<Int?> {
        Binding(
            get: { progressionStep.map { Int($0) } },
            set: { progressionStep = $0.map(Double.init) }
        )
    }

    private var progressionFooter: String {
        switch kind {
        case .reps:
            return "Sets that carry a weight progress on load, adding \(phrase(loadProgressionStep, .load)). Sets with no weight progress on reps, adding \(phrase(progressionStep, .reps))."
        case .timed:
            return "Adds \(phrase(progressionStep, .duration)) when every set hits its target. A weighted hold still progresses on time, never on the plate."
        case .distance:
            return "Adds \(phrase(progressionStep, .distance)) when every set hits its target."
        }
    }

    private func phrase(_ stored: Double?, _ dimension: ProgressionDimension) -> String {
        let step = stored ?? dimension.defaultStep
        let value = formattedStep(step)
        let suffix = stored == nil ? " by default" : ""
        switch dimension {
        case .reps:
            return (step == 1 ? "1 rep" : "\(value) reps") + suffix
        case .load:
            return "\(value) kg" + suffix
        case .duration:
            return (step == 1 ? "1 second" : "\(value) seconds") + suffix
        case .distance:
            return "\(value) m" + suffix
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
            existing.loadProgressionStepKg = showsLoadStep ? loadProgressionStep : nil
        } else {
            let ex = Exercise(
                name: trimmed,
                kind: kind,
                defaultRestSec: defaultRestSec,
                defaultTargetReps: kind == .reps ? defaultTargetReps : nil,
                defaultTargetDurationSec: kind == .timed ? defaultTargetDurationSec : nil,
                defaultTargetDistanceM: kind == .distance ? defaultTargetDistanceM : nil,
                progressionStep: progressionStep,
                loadProgressionStepKg: showsLoadStep ? loadProgressionStep : nil
            )
            modelContext.insert(ex)
        }
    }
}
