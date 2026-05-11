import SwiftUI
import SwiftData
import UIKit
import WorkoutCore

struct TemplateDetailView: View {
    @Bindable var template: WorkoutTemplate
    @Environment(\.modelContext) private var modelContext
    @State private var activeSheet: TemplateDetailSheet?

    var body: some View {
        List {
            Section {
                TextField("Workout name", text: $template.name)
            }
            Section {
                ForEach(template.orderedExercises) { pe in
                    NavigationLink {
                        PlannedExerciseDetailView(plannedExercise: pe)
                    } label: {
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
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    activeSheet = .exercisePicker
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .exercisePicker:
                NavigationStack {
                    ExerciseLibraryView(isPickMode: true) { picked in
                        activeSheet = .exerciseSetup(picked)
                    }
                }
            case .exerciseSetup(let exercise):
                NavigationStack {
                    AddExerciseSetupView(exercise: exercise) { setup in
                        addExercise(exercise, setup: setup)
                        activeSheet = nil
                    }
                }
            }
        }
    }

    private func addExercise(_ exercise: Exercise, setup: ExerciseSetup) {
        let pe = PlannedExercise(
            orderIndex: template.orderedExercises.count,
            exercise: exercise,
            restSec: setup.restSec
        )
        pe.template = template
        modelContext.insert(pe)

        for index in 0..<setup.setCount {
            let set = PlannedSet(
                orderIndex: index,
                targetWeightKg: setup.targetWeightKg,
                targetReps: exercise.kind == .reps ? setup.targetReps : nil,
                targetDurationSec: exercise.kind == .timed ? setup.targetDurationSec : nil,
                targetDistanceM: exercise.kind == .distance ? setup.targetDistanceM : nil
            )
            set.plannedExercise = pe
            modelContext.insert(set)
        }
    }

    private func summary(for pe: PlannedExercise) -> String {
        let setCount = pe.orderedSets.count
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
        parts.append("\(pe.resolvedRestSec)s rest")

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

private enum TemplateDetailSheet: Identifiable {
    case exercisePicker
    case exerciseSetup(Exercise)

    var id: String {
        switch self {
        case .exercisePicker:
            return "exercisePicker"
        case .exerciseSetup(let exercise):
            return "exerciseSetup-\(exercise.id)"
        }
    }
}

private struct ExerciseSetup {
    var setCount: Int
    var targetWeightKg: Double?
    var targetReps: Int?
    var targetDurationSec: Int?
    var targetDistanceM: Double?
    var restSec: Int
}

private struct AddExerciseSetupView: View {
    let exercise: Exercise
    let onSave: (ExerciseSetup) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var setCount: Int
    @State private var weightText: String
    @State private var repsText: String
    @State private var durationText: String
    @State private var distanceText: String
    @State private var restText: String

    init(exercise: Exercise, onSave: @escaping (ExerciseSetup) -> Void) {
        self.exercise = exercise
        self.onSave = onSave
        _setCount = State(initialValue: Self.defaultSetCount(for: exercise.kind))
        _weightText = State(initialValue: "")
        _repsText = State(initialValue: String(exercise.defaultTargetReps ?? 10))
        _durationText = State(initialValue: String(exercise.defaultTargetDurationSec ?? 30))
        _distanceText = State(initialValue: String(format: "%.4g", exercise.defaultTargetDistanceM ?? 1000))
        _restText = State(initialValue: String(exercise.defaultRestSec))
    }

    var body: some View {
        Form {
            Section("Exercise") {
                LabeledContent("Name", value: exercise.name)
                LabeledContent("Type", value: exercise.kind.displayName)
            }
            Section("Sets") {
                Stepper(value: $setCount, in: 1...12) {
                    LabeledContent("Number of sets", value: "\(setCount)")
                }
                if exercise.kind == .reps || exercise.kind == .timed {
                    setupTextField("Weight", text: $weightText, unit: "kg", keyboard: .decimalPad)
                }
                switch exercise.kind {
                case .reps:
                    setupTextField("Reps", text: $repsText, unit: "reps", keyboard: .numberPad)
                case .timed:
                    setupTextField("Duration", text: $durationText, unit: "sec", keyboard: .numberPad)
                case .distance:
                    setupTextField("Distance", text: $distanceText, unit: "m", keyboard: .decimalPad)
                }
            }
            Section("Rest") {
                setupTextField("Rest between sets", text: $restText, unit: "sec", keyboard: .numberPad)
            }
        }
        .navigationTitle("Add to Workout")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Add") {
                    guard let setup else { return }
                    onSave(setup)
                }
                .disabled(setup == nil)
            }
        }
    }

    private var setup: ExerciseSetup? {
        guard let restSec = Int(restText), restSec >= 0 else { return nil }
        guard let targetWeightKg = validOptionalDouble(from: weightText) else { return nil }
        guard let targetReps = validOptionalInt(from: repsText) else { return nil }
        guard let targetDurationSec = validOptionalInt(from: durationText) else { return nil }
        guard let targetDistanceM = validOptionalDouble(from: distanceText) else { return nil }

        return ExerciseSetup(
            setCount: setCount,
            targetWeightKg: targetWeightKg,
            targetReps: targetReps,
            targetDurationSec: targetDurationSec,
            targetDistanceM: targetDistanceM,
            restSec: restSec
        )
    }

    @ViewBuilder
    private func setupTextField(
        _ title: String,
        text: Binding<String>,
        unit: String,
        keyboard: UIKeyboardType
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(unit, text: text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }

    private func validOptionalInt(from text: String) -> Int?? {
        text.isEmpty ? .some(nil) : Int(text).map(Optional.some)
    }

    private func validOptionalDouble(from text: String) -> Double?? {
        text.isEmpty ? .some(nil) : Double(text).map(Optional.some)
    }

    private static func defaultSetCount(for kind: ExerciseKind) -> Int {
        switch kind {
        case .reps, .timed:
            return 3
        case .distance:
            return 1
        }
    }
}
