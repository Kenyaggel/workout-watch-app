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

    // MARK: - Lift Identity across the wire

    func testSnapshotCarriesLiftIdentityAndTheTargetThatWasInEffect() throws {
        let benchID = UUID()
        let session = WorkoutSession(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 10),
            templateName: "Push"
        )
        let performed = PerformedSet(
            orderIndex: 0,
            exerciseName: "Bench Press",
            exerciseID: benchID,
            exerciseIndex: 0,
            setIndex: 0,
            weightKg: 82.5,
            reps: 7,
            completedAt: Date(timeIntervalSince1970: 100),
            targetWeightKg: 80,
            targetReps: 8
        )
        performed.session = session
        session.performedSets = [performed]

        let snapshot = SessionSyncSnapshot(session: session)
        let decoded = try JSONDecoder().decode(
            SessionSyncSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )

        let set = try XCTUnwrap(decoded.session.performedSets.first)
        XCTAssertEqual(set.exerciseID, benchID)
        XCTAssertEqual(set.targetWeightKg, 80)
        XCTAssertEqual(set.targetReps, 8)
        XCTAssertEqual(set.weightKg, 82.5, "the actual stays distinct from the target")
        XCTAssertEqual(set.reps, 7)
    }

    /// A watch still on the previous build sends JSON without any of the V3 keys. The phone
    /// must accept it rather than dropping the whole session.
    func testImporterAcceptsASnapshotFromAWatchThatPredatesV3() throws {
        let context = try makeContext()
        let sessionID = UUID()
        let legacyJSON = """
        {
          "session": {
            "id": "\(sessionID.uuidString)",
            "startedAt": 10,
            "templateName": "Push",
            "performedSets": [
              {
                "id": "\(UUID().uuidString)",
                "orderIndex": 0,
                "exerciseName": "Bench Press",
                "exerciseIndex": 0,
                "setIndex": 0,
                "weightKg": 60,
                "reps": 8,
                "completedAt": 100
              }
            ]
          }
        }
        """
        let snapshot = try JSONDecoder().decode(
            SessionSyncSnapshot.self,
            from: Data(legacyJSON.utf8)
        )
        XCTAssertNil(snapshot.session.performedSets[0].exerciseID)
        XCTAssertNil(snapshot.session.performedSets[0].targetWeightKg)

        try SessionSyncImporter.upsert(snapshot, in: context)
        let stored = try context.fetch(FetchDescriptor<PerformedSet>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.weightKg, 60)
    }

    /// Identity-less sets from an older watch get resolved on arrival by the same
    /// unambiguous-name rule the V2→V3 migration uses.
    func testImporterResolvesIdentityByNameForSetsThatArriveWithout() throws {
        let context = try makeContext()
        let benchID = UUID()
        context.insert(Exercise(id: benchID, name: "Bench Press", kind: .reps, defaultRestSec: 120))
        try context.save()

        let dto = PerformedSetSyncDTO(
            id: UUID(),
            orderIndex: 0,
            exerciseName: "bench press",
            exerciseID: nil,
            exerciseIndex: 0,
            setIndex: 0,
            weightKg: 60,
            reps: 8,
            durationSec: nil,
            distanceM: nil,
            rpe: nil,
            completedAt: Date(timeIntervalSince1970: 100)
        )
        try SessionSyncImporter.upsert(
            SessionSyncSnapshot(session: WorkoutSessionSyncDTO(
                id: UUID(),
                startedAt: Date(timeIntervalSince1970: 10),
                endedAt: Date(timeIntervalSince1970: 1_000),
                templateID: nil,
                templateName: "Push",
                healthKitWorkoutUUID: nil,
                performedSets: [dto]
            )),
            in: context
        )

        let stored = try XCTUnwrap(try context.fetch(FetchDescriptor<PerformedSet>()).first)
        XCTAssertEqual(stored.exerciseID, benchID)
    }

    func testImporterLeavesIdentityNilWhenTheNameIsAmbiguous() throws {
        let context = try makeContext()
        context.insert(Exercise(id: UUID(), name: "Row", kind: .reps, defaultRestSec: 90))
        context.insert(Exercise(id: UUID(), name: "Row", kind: .reps, defaultRestSec: 60))
        try context.save()

        let dto = PerformedSetSyncDTO(
            id: UUID(),
            orderIndex: 0,
            exerciseName: "Row",
            exerciseID: nil,
            exerciseIndex: 0,
            setIndex: 0,
            weightKg: 40,
            reps: 12,
            durationSec: nil,
            distanceM: nil,
            rpe: nil,
            completedAt: Date(timeIntervalSince1970: 100)
        )
        try SessionSyncImporter.upsert(
            SessionSyncSnapshot(session: WorkoutSessionSyncDTO(
                id: UUID(),
                startedAt: Date(timeIntervalSince1970: 10),
                endedAt: nil,
                templateID: nil,
                templateName: "Pull",
                healthKitWorkoutUUID: nil,
                performedSets: [dto]
            )),
            in: context
        )

        let stored = try XCTUnwrap(try context.fetch(FetchDescriptor<PerformedSet>()).first)
        XCTAssertNil(stored.exerciseID)
    }
}
