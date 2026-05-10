import Foundation

#if canImport(HealthKit) && os(watchOS)
import HealthKit

public enum HealthKitError: Error {
    case notAvailable
    case sessionAlreadyRunning
    case noActiveSession
}

@MainActor
public final class HealthKitManager: NSObject, WorkoutLifecycle {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private let configuration: HKWorkoutConfiguration = {
        let cfg = HKWorkoutConfiguration()
        cfg.activityType = .traditionalStrengthTraining
        cfg.locationType = .indoor
        return cfg
    }()

    public override init() { super.init() }

    public func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthKitError.notAvailable }
        let typesToShare: Set<HKSampleType> = [
            HKQuantityType.workoutType()
        ]
        let typesToRead: Set<HKObjectType> = [
            HKQuantityType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned)
        ]
        try await store.requestAuthorization(toShare: typesToShare, read: typesToRead)
    }

    public func startWorkout(at date: Date) async throws {
        guard session == nil else { throw HealthKitError.sessionAlreadyRunning }
        let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
        session.delegate = self
        builder.delegate = self

        self.session = session
        self.builder = builder

        session.startActivity(with: date)
        try await builder.beginCollection(at: date)
    }

    public func endWorkout(at date: Date) async throws -> UUID? {
        guard let session, let builder else { throw HealthKitError.noActiveSession }
        session.end()
        try await builder.endCollection(at: date)
        let workout = try await builder.finishWorkout()
        self.session = nil
        self.builder = nil
        return workout?.uuid
    }

    public func discard() async {
        session?.end()
        builder?.discardWorkout()
        session = nil
        builder = nil
    }
}

extension HealthKitManager: HKWorkoutSessionDelegate {
    nonisolated public func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    nonisolated public func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {}
}

extension HealthKitManager: HKLiveWorkoutBuilderDelegate {
    nonisolated public func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {}

    nonisolated public func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

#endif
