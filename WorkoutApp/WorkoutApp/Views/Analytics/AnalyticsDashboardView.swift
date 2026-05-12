import SwiftUI
import SwiftData
import Charts
import WorkoutCore

struct AnalyticsDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \PerformedSet.completedAt, order: .reverse) private var performedSets: [PerformedSet]

    @State private var selectedExerciseID: PersistentIdentifier?
    @State private var weeklyVolumes: [WeeklyVolume] = []
    @State private var frequencyPoints: [FrequencyPoint] = []
    @State private var progressionPoints: [ExerciseDataPoint] = []
    @State private var e1rmPoints: [E1RMDataPoint] = []

    private var selectedExercise: Exercise? {
        guard let selectedExerciseID else { return nil }
        return exercises.first { $0.persistentModelID == selectedExerciseID }
    }

    private var exerciseLibraryVersion: [ExerciseVersion] {
        exercises.map { ExerciseVersion(id: $0.id, name: $0.name) }
    }

    private var analyticsDataVersion: AnalyticsDataVersion {
        AnalyticsDataVersion(
            sessions: sessions.map {
                SessionVersion(
                    id: $0.id,
                    startedAt: $0.startedAt,
                    endedAt: $0.endedAt,
                    templateName: $0.templateName
                )
            },
            performedSets: performedSets.map {
                PerformedSetVersion(
                    id: $0.id,
                    exerciseName: $0.exerciseName,
                    weightKg: $0.weightKg,
                    reps: $0.reps,
                    durationSec: $0.durationSec,
                    distanceM: $0.distanceM,
                    completedAt: $0.completedAt
                )
            }
        )
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
            refreshAllAnalytics()
        }
        .onChange(of: selectedExerciseID) { _, _ in
            refreshExerciseAnalytics()
        }
        .onChange(of: analyticsDataVersion) { _, _ in
            refreshAllAnalytics()
        }
        .onChange(of: exerciseLibraryVersion) { _, _ in
            ensureSelectedExercise()
            refreshExerciseAnalytics()
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

    private func ensureSelectedExercise() {
        if let selectedExerciseID,
           exercises.contains(where: { $0.persistentModelID == selectedExerciseID }) {
            return
        }
        selectedExerciseID = exercises.first?.persistentModelID
    }

    private func refreshAllAnalytics() {
        ensureSelectedExercise()
        refreshOverviewAnalytics()
        refreshExerciseAnalytics()
    }

    private func refreshOverviewAnalytics() {
        let engine = AnalyticsEngine(modelContext: modelContext)
        weeklyVolumes = engine.weeklyVolume(last: 12)
        frequencyPoints = engine.workoutFrequency(last: 3)
    }

    private func refreshExerciseAnalytics() {
        guard let name = selectedExercise?.name else {
            progressionPoints = []
            e1rmPoints = []
            return
        }

        let analytics = AnalyticsEngine(modelContext: modelContext)
            .exerciseAnalytics(name: name, last: 20)
        progressionPoints = analytics.progression
        e1rmPoints = analytics.e1rm
    }
}

private struct ExerciseVersion: Equatable {
    let id: UUID
    let name: String
}

private struct AnalyticsDataVersion: Equatable {
    let sessions: [SessionVersion]
    let performedSets: [PerformedSetVersion]
}

private struct SessionVersion: Equatable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date?
    let templateName: String
}

private struct PerformedSetVersion: Equatable {
    let id: UUID
    let exerciseName: String
    let weightKg: Double?
    let reps: Int?
    let durationSec: Int?
    let distanceM: Double?
    let completedAt: Date
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
