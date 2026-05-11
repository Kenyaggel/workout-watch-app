import SwiftUI
import SwiftData
import Charts
import WorkoutCore

struct AnalyticsDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @State private var selectedExerciseID: PersistentIdentifier?
    @State private var weeklyVolumes: [WeeklyVolume] = []
    @State private var frequencyPoints: [FrequencyPoint] = []
    @State private var progressionPoints: [ExerciseDataPoint] = []
    @State private var e1rmPoints: [E1RMDataPoint] = []

    private var selectedExercise: Exercise? {
        guard let selectedExerciseID else { return nil }
        return exercises.first { $0.persistentModelID == selectedExerciseID }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                frequencySection
                weeklyVolumeSection
                exercisePickerSection
                progressionSection
                e1rmSection
            }
        }
        .navigationTitle("Analytics")
        .task {
            let engine = AnalyticsEngine(modelContext: modelContext)
            weeklyVolumes = engine.weeklyVolume(last: 12)
            frequencyPoints = engine.workoutFrequency(last: 3)
        }
        .task(id: selectedExerciseID) {
            guard let name = selectedExercise?.name else {
                progressionPoints = []
                e1rmPoints = []
                return
            }
            let engine = AnalyticsEngine(modelContext: modelContext)
            progressionPoints = engine.exerciseProgression(exerciseName: name, last: 20)
            e1rmPoints = engine.estimated1RM(exerciseName: name, last: 20)
        }
        .onChange(of: exercises) { _, newValue in
            if selectedExerciseID == nil, let first = newValue.first {
                selectedExerciseID = first.persistentModelID
            } else if let id = selectedExerciseID,
                      !newValue.contains(where: { $0.persistentModelID == id }) {
                selectedExerciseID = newValue.first?.persistentModelID
            }
        }
    }

    // MARK: - Section 1: Workout Frequency

    private var frequencySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Workout Frequency")
                .font(.headline)
                .padding(.horizontal)

            if frequencyPoints.isEmpty {
                noDataPlaceholder
            } else {
                Chart(frequencyPoints, id: \.weekStart) { point in
                    BarMark(
                        x: .value("Week", point.weekStart, unit: .weekOfYear),
                        y: .value("Sessions", point.sessionCount)
                    )
                    .foregroundStyle(Color.accentColor)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 160)
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Section 2: Weekly Volume

    private var weeklyVolumeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weekly Volume")
                .font(.headline)
                .padding(.horizontal)

            if weeklyVolumes.isEmpty {
                noDataPlaceholder
            } else {
                Chart(weeklyVolumes, id: \.weekStart) { point in
                    AreaMark(
                        x: .value("Week", point.weekStart, unit: .weekOfYear),
                        y: .value("Volume (kg)", point.totalVolumeKg)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.15))

                    LineMark(
                        x: .value("Week", point.weekStart, unit: .weekOfYear),
                        y: .value("Volume (kg)", point.totalVolumeKg)
                    )
                    .foregroundStyle(Color.accentColor)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 160)
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Exercise Picker

    private var exercisePickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if exercises.isEmpty {
                Text("No exercises")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                Picker("Exercise", selection: $selectedExerciseID) {
                    ForEach(exercises, id: \.persistentModelID) { exercise in
                        Text(exercise.name).tag(exercise.persistentModelID as PersistentIdentifier?)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Section 3: Exercise Progression

    private var progressionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Exercise Progression")
                .font(.headline)
                .padding(.horizontal)

            if progressionPoints.isEmpty {
                noDataPlaceholder
            } else {
                Chart(progressionPoints, id: \.sessionDate) { point in
                    LineMark(
                        x: .value("Date", point.sessionDate),
                        y: .value("Max Weight (kg)", point.maxWeightKg)
                    )
                    .foregroundStyle(Color.accentColor)

                    PointMark(
                        x: .value("Date", point.sessionDate),
                        y: .value("Max Weight (kg)", point.maxWeightKg)
                    )
                    .foregroundStyle(Color.accentColor)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 160)
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Section 4: Estimated 1RM

    private var e1rmSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Estimated 1RM")
                .font(.headline)
                .padding(.horizontal)

            if e1rmPoints.isEmpty {
                noDataPlaceholder
            } else {
                Chart(e1rmPoints, id: \.sessionDate) { point in
                    LineMark(
                        x: .value("Date", point.sessionDate),
                        y: .value("e1RM (kg)", point.estimatedMax)
                    )
                    .foregroundStyle(Color.accentColor)

                    PointMark(
                        x: .value("Date", point.sessionDate),
                        y: .value("e1RM (kg)", point.estimatedMax)
                    )
                    .foregroundStyle(Color.accentColor)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 160)
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private var noDataPlaceholder: some View {
        Text("No data")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 160)
            .padding(.horizontal)
    }
}

#Preview {
    NavigationStack {
        AnalyticsDashboardView()
    }
    .modelContainer(
        try! ModelContainer(
            for: Schema(versionedSchema: WorkoutSchemaV2.self),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    )
}
