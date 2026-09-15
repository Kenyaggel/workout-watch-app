import Foundation

/// Replays history through the rules and reports what the Coach *would* have proposed,
/// session by session.
///
/// The point is to find out whether the rules stall or run away before they are wired to
/// anything — in a trace rather than under a barbell. It works on any history: a real store
/// (via `CoachStore.sessionSnapshots`) or a simulated lifter.
public enum CoachBacktest {

    /// What the lifter does with a proposal that needs review. The Coach itself never
    /// decides this; the backtest has to assume something, and says which.
    public enum Acceptance: Sendable {
        /// Approves everything, including deloads. The ladder moves as far as the rules let it.
        case acceptsEverything
        /// Only the moves that apply themselves. Shows what a lifter who never opens the
        /// phone would experience.
        case automaticOnly
    }

    public struct Step: Sendable {
        public var sessionIndex: Int
        public var date: Date
        public var targetsBefore: [TargetSnapshot]
        public var output: CoachOutput
        public var applied: Bool

        public var anchorBefore: Double? {
            targetsBefore.compactMap { $0.value(on: output.dimension) }.first
        }
        public var anchorAfter: Double? {
            applied
                ? output.proposedTargets.compactMap { $0.value(on: output.dimension) }.first
                : anchorBefore
        }
    }

    public struct Report: Sendable {
        public var steps: [Step]

        public var anchors: [Double] { steps.compactMap(\.anchorAfter) }
        public var outcomes: [CoachOutcome] { steps.map(\.output.outcome) }
        public func count(of outcome: CoachOutcome) -> Int {
            outcomes.filter { $0 == outcome }.count
        }

        /// One line per session, which is the whole deliverable of a backtest.
        public func trace(dimension: ProgressionDimension) -> String {
            steps.map { step in
                let before = step.anchorBefore.map { Coach.format($0, dimension) } ?? "—"
                let after = step.anchorAfter.map { Coach.format($0, dimension) } ?? "—"
                let mark = step.applied ? "→" : "·"
                return "\(String(format: "%3d", step.sessionIndex))  \(before.padded(8)) \(mark) \(after.padded(8))  \(step.output.outcome.rawValue)"
            }
            .joined(separator: "\n")
        }
    }

    /// Replays `sessions` against `slot`, carrying each accepted proposal forward so the
    /// next session is judged against the targets the previous one produced.
    ///
    /// `sessions` must already be ordered oldest-first, and each session's performed sets
    /// must carry the targets they were run against — which is what `PerformedSet.target*`
    /// records.
    public static func replay(
        slot: SlotSnapshot,
        sessions: [SessionSnapshot],
        acceptance: Acceptance = .acceptsEverything,
        config: CoachConfig = CoachConfig()
    ) -> Report {
        var slot = slot
        var steps: [Step] = []

        for (index, session) in sessions.enumerated() {
            let asOf = (session.endedAt ?? session.startedAt).addingTimeInterval(1)
            let output = Coach.propose(CoachInput(
                slot: slot,
                sessions: Array(sessions.prefix(index + 1)),
                asOf: asOf,
                config: config
            ))

            let applied: Bool
            switch (output.applyClass, acceptance) {
            case (.automatic, _): applied = true
            case (.pendingReview, .acceptsEverything): applied = true
            case (.pendingReview, .automaticOnly): applied = false
            case (.noOp, _): applied = false
            }

            steps.append(Step(
                sessionIndex: index,
                date: session.startedAt,
                targetsBefore: slot.targets,
                output: output,
                applied: applied
            ))

            if applied { slot.targets = output.proposedTargets }
        }

        return Report(steps: steps)
    }
}

private extension String {
    func padded(_ width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}
