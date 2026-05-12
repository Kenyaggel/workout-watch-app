import SwiftData
import XCTest
@testable import WorkoutCore

@MainActor
final class SessionSyncTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let container = try WorkoutModelContainer.makeShared(inMemory: true)
        return ModelContext(container)
    }

    func testSessionSnapshotRoundTripsCompletedSets() throws {
        let session = WorkoutSession(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 10),
            templateName: "Push"
        )
        session.endedAt = Date(timeIntervalSince1970: 1_210)

        let first = PerformedSet(
            orderIndex: 0,
            exerciseName: "Bench Press",
            exerciseIndex: 0,
            setIndex: 0,
            weightKg: 80,
            reps: 8,
            rpe: nil,
            completedAt: Date(timeIntervalSince1970: 100)
        )
        first.session = session

        let second = PerformedSet(
            orderIndex: 1,
            exerciseName: "Bench Press",
            exerciseIndex: 0,
            setIndex: 1,
            weightKg: 82.5,
            reps: 6,
            rpe: 8,
            completedAt: Date(timeIntervalSince1970: 220)
        )
        second.session = session
        session.performedSets = [first, second]

        let templateID = UUID()
        let snapshot = SessionSyncSnapshot(session: session, templateID: templateID)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionSyncSnapshot.self, from: data)

        XCTAssertEqual(decoded.session.id, session.id)
        XCTAssertEqual(decoded.session.templateID, templateID)
        XCTAssertEqual(decoded.session.performedSets.count, 2)
        XCTAssertNil(decoded.session.performedSets[0].rpe)
        XCTAssertEqual(decoded.session.performedSets[1].rpe, 8)
    }

    func testImporterUpsertsSessionAndLinksTemplate() throws {
        let context = try makeContext()
        let templateID = UUID()
        let template = WorkoutTemplate(
            id: templateID,
            name: "Phone Push",
            createdAt: Date(timeIntervalSince1970: 0)
        )
        context.insert(template)
        try context.save()

        let sessionID = UUID()
        let setID = UUID()
        let snapshot = SessionSyncSnapshot(session: WorkoutSessionSyncDTO(
            id: sessionID,
            startedAt: Date(timeIntervalSince1970: 10),
            endedAt: Date(timeIntervalSince1970: 610),
            templateID: templateID,
            templateName: "Phone Push",
            healthKitWorkoutUUID: nil,
            performedSets: [
                PerformedSetSyncDTO(
                    id: setID,
                    orderIndex: 0,
                    exerciseName: "Bench Press",
                    exerciseIndex: 0,
                    setIndex: 0,
                    weightKg: 80,
                    reps: 8,
                    durationSec: nil,
                    distanceM: nil,
                    rpe: 7,
                    completedAt: Date(timeIntervalSince1970: 120)
                )
            ]
        ))

        try SessionSyncImporter.upsert(snapshot, in: context)

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].id, sessionID)
        XCTAssertEqual(sessions[0].template?.id, templateID)
        XCTAssertEqual(sessions[0].totalVolumeKg, 640, accuracy: 0.001)
        XCTAssertEqual(sessions[0].orderedPerformedSets.first?.id, setID)
    }

    func testImporterReplacesExistingSetsForSameSession() throws {
        let context = try makeContext()
        let sessionID = UUID()

        try SessionSyncImporter.upsert(
            SessionSyncSnapshot(session: WorkoutSessionSyncDTO(
                id: sessionID,
                startedAt: Date(timeIntervalSince1970: 10),
                endedAt: Date(timeIntervalSince1970: 610),
                templateID: nil,
                templateName: "Push",
                healthKitWorkoutUUID: nil,
                performedSets: [
                    PerformedSetSyncDTO(
                        id: UUID(),
                        orderIndex: 0,
                        exerciseName: "Bench Press",
                        exerciseIndex: 0,
                        setIndex: 0,
                        weightKg: 80,
                        reps: 8,
                        durationSec: nil,
                        distanceM: nil,
                        rpe: nil,
                        completedAt: Date(timeIntervalSince1970: 120)
                    )
                ]
            )),
            in: context
        )

        try SessionSyncImporter.upsert(
            SessionSyncSnapshot(session: WorkoutSessionSyncDTO(
                id: sessionID,
                startedAt: Date(timeIntervalSince1970: 10),
                endedAt: Date(timeIntervalSince1970: 910),
                templateID: nil,
                templateName: "Push",
                healthKitWorkoutUUID: nil,
                performedSets: [
                    PerformedSetSyncDTO(
                        id: UUID(),
                        orderIndex: 0,
                        exerciseName: "Bench Press",
                        exerciseIndex: 0,
                        setIndex: 0,
                        weightKg: 90,
                        reps: 5,
                        durationSec: nil,
                        distanceM: nil,
                        rpe: 8,
                        completedAt: Date(timeIntervalSince1970: 200)
                    ),
                    PerformedSetSyncDTO(
                        id: UUID(),
                        orderIndex: 1,
                        exerciseName: "Bench Press",
                        exerciseIndex: 0,
                        setIndex: 1,
                        weightKg: 90,
                        reps: 4,
                        durationSec: nil,
                        distanceM: nil,
                        rpe: nil,
                        completedAt: Date(timeIntervalSince1970: 300)
                    )
                ]
            )),
            in: context
        )

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].durationSec, 900)
        XCTAssertEqual(sessions[0].orderedPerformedSets.count, 2)
        XCTAssertEqual(sessions[0].totalVolumeKg, 810, accuracy: 0.001)
    }
}
