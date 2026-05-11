import SwiftData
import XCTest
@testable import WorkoutCore

@MainActor
final class TemplateSyncTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let container = try WorkoutModelContainer.makeShared(inMemory: true)
        return ModelContext(container)
    }

    func testSnapshotRoundTripsTemplateGraph() throws {
        let context = try makeContext()
        let template = makeTemplate(
            name: "Upper",
            exerciseName: "Bench Press",
            kind: .reps,
            restSec: 120,
            context: context
        )
        try context.save()

        let snapshot = TemplateSyncSnapshot(templates: [template])
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(TemplateSyncSnapshot.self, from: data)

        XCTAssertEqual(decoded.templates.count, 1)
        XCTAssertEqual(decoded.templates[0].name, "Upper")
        XCTAssertEqual(decoded.templates[0].plannedExercises[0].exercise.name, "Bench Press")
        XCTAssertEqual(decoded.templates[0].plannedExercises[0].restSec, 120)
        XCTAssertEqual(decoded.templates[0].plannedExercises[0].sets[0].targetWeightKg, 80)
        XCTAssertEqual(decoded.templates[0].plannedExercises[0].sets[0].targetReps, 8)
    }

    func testImporterReplacesLocalTemplatesWithPhoneSnapshot() throws {
        let context = try makeContext()
        _ = makeTemplate(
            name: "Watch Seed",
            exerciseName: "Old Exercise",
            kind: .reps,
            restSec: 90,
            context: context
        )
        try context.save()

        let phoneTemplateID = UUID()
        let exerciseID = UUID()
        let snapshot = TemplateSyncSnapshot(templates: [
            WorkoutTemplateSyncDTO(
                id: phoneTemplateID,
                name: "Phone Push",
                createdAt: Date(timeIntervalSince1970: 10),
                plannedExercises: [
                    PlannedExerciseSyncDTO(
                        id: UUID(),
                        orderIndex: 0,
                        restSec: 150,
                        exercise: ExerciseSyncDTO(
                            id: exerciseID,
                            name: "Incline Press",
                            kind: .reps,
                            defaultRestSec: 120,
                            defaultTargetReps: 10,
                            defaultTargetDurationSec: nil,
                            defaultTargetDistanceM: nil
                        ),
                        sets: [
                            PlannedSetSyncDTO(
                                id: UUID(),
                                orderIndex: 0,
                                targetWeightKg: 32.5,
                                targetReps: 10,
                                targetDurationSec: nil,
                                targetDistanceM: nil
                            )
                        ]
                    )
                ]
            )
        ])

        try TemplateSyncImporter.replaceTemplates(with: snapshot, in: context)

        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        XCTAssertEqual(templates.count, 1)
        XCTAssertEqual(templates[0].id, phoneTemplateID)
        XCTAssertEqual(templates[0].name, "Phone Push")
        XCTAssertEqual(templates[0].orderedExercises.first?.exercise?.id, exerciseID)
        XCTAssertEqual(templates[0].orderedExercises.first?.resolvedRestSec, 150)
        XCTAssertEqual(templates[0].orderedExercises.first?.orderedSets.first?.targetWeightKg, 32.5)
    }

    func testImporterUpdatesExistingExerciseDefaults() throws {
        let context = try makeContext()
        let exerciseID = UUID()
        let exercise = Exercise(
            id: exerciseID,
            name: "Old Name",
            kind: .reps,
            defaultRestSec: 60,
            defaultTargetReps: 5
        )
        context.insert(exercise)
        try context.save()

        let snapshot = TemplateSyncSnapshot(templates: [
            WorkoutTemplateSyncDTO(
                id: UUID(),
                name: "Updated",
                createdAt: Date(timeIntervalSince1970: 20),
                plannedExercises: [
                    PlannedExerciseSyncDTO(
                        id: UUID(),
                        orderIndex: 0,
                        restSec: 75,
                        exercise: ExerciseSyncDTO(
                            id: exerciseID,
                            name: "New Name",
                            kind: .timed,
                            defaultRestSec: 75,
                            defaultTargetReps: nil,
                            defaultTargetDurationSec: 45,
                            defaultTargetDistanceM: nil
                        ),
                        sets: []
                    )
                ]
            )
        ])

        try TemplateSyncImporter.replaceTemplates(with: snapshot, in: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let updated = try XCTUnwrap(exercises.first { $0.id == exerciseID })
        XCTAssertEqual(updated.name, "New Name")
        XCTAssertEqual(updated.kind, .timed)
        XCTAssertEqual(updated.defaultRestSec, 75)
        XCTAssertEqual(updated.defaultTargetDurationSec, 45)
    }

    @discardableResult
    private func makeTemplate(
        name: String,
        exerciseName: String,
        kind: ExerciseKind,
        restSec: Int,
        context: ModelContext
    ) -> WorkoutTemplate {
        let exercise = Exercise(
            name: exerciseName,
            kind: kind,
            defaultRestSec: restSec,
            defaultTargetReps: kind == .reps ? 8 : nil,
            defaultTargetDurationSec: kind == .timed ? 45 : nil,
            defaultTargetDistanceM: kind == .distance ? 1000 : nil
        )
        context.insert(exercise)

        let template = WorkoutTemplate(name: name)
        context.insert(template)

        let plannedExercise = PlannedExercise(
            orderIndex: 0,
            exercise: exercise,
            restSec: restSec
        )
        plannedExercise.template = template
        context.insert(plannedExercise)

        let set = PlannedSet(
            orderIndex: 0,
            targetWeightKg: kind == .distance ? nil : 80,
            targetReps: kind == .reps ? 8 : nil,
            targetDurationSec: kind == .timed ? 45 : nil,
            targetDistanceM: kind == .distance ? 1000 : nil
        )
        set.plannedExercise = plannedExercise
        context.insert(set)

        return template
    }
}
