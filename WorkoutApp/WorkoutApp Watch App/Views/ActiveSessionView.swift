import SwiftUI
import SwiftData
import WorkoutCore

struct ActiveSessionView: View {
    let plan: SessionPlan

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    @State private var engine: SessionEngine?
    @State private var recorder: SwiftDataRecorder?
    @State private var lifecycle: any WorkoutLifecycle = makeLifecycle()
    @State private var hasStarted = false

    var body: some View {
        Group {
            if let engine {
                phaseView(engine: engine)
            } else {
                ProgressView().task { await prepareEngine() }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("End") { Task { await endWorkout() } }
            }
        }
    }

    @ViewBuilder
    private func phaseView(engine: SessionEngine) -> some View {
        switch engine.phase {
        case .idle:
            PlanSummaryView(plan: engine.plan) {
                engine.start()
            }
        case let .inSet(cursor, startedAt):
            InSetView(
                engine: engine,
                cursor: cursor,
                setStartedAt: startedAt,
                isLuminanceReduced: isLuminanceReduced
            )
        case let .rest(endsAt, _, _):
            RestView(
                engine: engine,
                endsAt: endsAt,
                isLuminanceReduced: isLuminanceReduced
            )
        case let .prep(startedAt, _):
            PrepView(
                engine: engine,
                startedAt: startedAt,
                isLuminanceReduced: isLuminanceReduced
            )
        case .complete:
            SessionSummaryView(session: recorder?.currentSession) {
                dismiss()
            }
        }
    }

    private func prepareEngine() async {
        guard !hasStarted else { return }
        hasStarted = true
        let recorder = SwiftDataRecorder(context: modelContext)
        let engine = SessionEngine(
            plan: plan,
            recorder: recorder,
            haptics: WatchHaptics()
        )
        self.recorder = recorder
        self.engine = engine
        do {
            try await lifecycle.requestAuthorization()
            try await lifecycle.startWorkout(at: Date())
        } catch {
            // Authorization or workout start failed — continue without HealthKit recording.
        }
    }

    private func endWorkout() async {
        engine?.endWorkout()
        _ = try? await lifecycle.endWorkout(at: Date())
        dismiss()
    }
}

private func makeLifecycle() -> any WorkoutLifecycle {
    #if canImport(HealthKit) && os(watchOS)
    return HealthKitManager()
    #else
    return NoopWorkoutLifecycle()
    #endif
}
