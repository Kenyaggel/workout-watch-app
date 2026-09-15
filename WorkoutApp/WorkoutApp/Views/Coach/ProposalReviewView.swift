import SwiftUI
import SwiftData
import WorkoutCore

/// Review by exception. Single-step moves in the usual direction have already applied
/// themselves, so everything here is something the coach declined to decide alone: a deload,
/// a second consecutive stall, a first starting weight, or a reading it is not confident in.
struct ProposalReviewView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var proposals: [CoachProposal] = []
    @State private var failure: String?

    var body: some View {
        List {
            if let failure {
                Section {
                    Text(failure)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(proposals) { proposal in
                Section {
                    ProposalRow(proposal: proposal)
                    HStack {
                        Button("Apply") { accept(proposal) }
                            .buttonStyle(.borderedProminent)
                        Spacer()
                        Button("Not now") { dismiss(proposal) }
                            .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("\(proposal.exerciseName) · \(proposal.workoutName)")
                }
            }
        }
        .navigationTitle("To Review")
        .overlay {
            if proposals.isEmpty && failure == nil {
                ContentUnavailableView("Nothing to Review", systemImage: "checkmark.circle")
            }
        }
        .task { reload() }
    }

    private func reload() {
        do {
            // Recomputed rather than read back: a proposal is a view of history, so this is
            // always current even if a session synced since the screen was last open.
            proposals = try CoachStore.pendingProposals(in: modelContext, asOf: Date())
            failure = nil
        } catch {
            proposals = []
            failure = "Could not work out what to propose: \(error.localizedDescription)"
        }
    }

    private func accept(_ proposal: CoachProposal) {
        try? CoachStore.accept(proposal, in: modelContext, at: Date())
        reload()
    }

    private func dismiss(_ proposal: CoachProposal) {
        try? CoachStore.dismiss(proposal, in: modelContext, at: Date())
        reload()
    }
}

private struct ProposalRow: View {
    let proposal: CoachProposal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(proposal.headline)
                    .font(.headline)
                Spacer()
                if let change = proposal.changeSummary {
                    Text(change)
                        .font(.subheadline)
                        .monospacedDigit()
                } else {
                    Text(proposal.currentSummary)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            // Written by the deterministic coach. No language model is involved in any
            // number here, or in the sentence explaining it.
            Text(proposal.output.reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !caveats.isEmpty {
                Label(caveats, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    /// Why this one needed a human at all, when a plain step would have applied itself.
    private var caveats: String {
        proposal.output.flags.compactMap { flag -> String? in
            switch flag {
            case .identityMatchedByNameOnly:
                return "matched on the exercise name, not its identity"
            case .workoutMatchedByNameOnly:
                return "matched on the workout name, not its identity"
            case .exerciseMissingFromLibrary:
                return "this exercise is no longer in the library"
            case .stepSanitized:
                return "the stored progression step was out of range and the default was used"
            case .setCountChanged:
                return "the number of sets changed since the last comparable session"
            case .missingTargetOnDimension:
                return "some sets carry no target on this axis"
            case .implausibleValue:
                return "the resulting number looks implausible"
            case .baselineExceededTarget:
                return "you trained heavier than the plan and completed it"
            case .legacyRowsWithoutRecordedTarget:
                return nil
            }
        }
        .joined(separator: " · ")
    }
}
