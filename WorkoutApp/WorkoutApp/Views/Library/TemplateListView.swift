import SwiftUI
import SwiftData
import WorkoutCore

struct TemplateListView: View {
    @Query(sort: \WorkoutTemplate.createdAt) var templates: [WorkoutTemplate]
    @Query private var sessions: [WorkoutSession]
    @Environment(\.modelContext) private var modelContext
    @State private var navigateTo: WorkoutTemplate?
    @State private var pendingCount = 0

    var body: some View {
        List {
            // Costs nothing at zero pending, which is most weeks — the section simply is not
            // in the list. Review by exception only works if the lifter is told, so it sits
            // on the first tab rather than inside each workout.
            if pendingCount > 0 {
                Section {
                    NavigationLink {
                        ProposalReviewView()
                    } label: {
                        Label(
                            "\(pendingCount) target\(pendingCount == 1 ? "" : "s") to review",
                            systemImage: "arrow.up.arrow.down.circle"
                        )
                    }
                }
            }
            ForEach(templates) { template in
                Button {
                    navigateTo = template
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.name)
                        Text(summary(for: template))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                }
            }
            .onDelete(perform: deleteTemplates)
        }
        .navigationTitle("Workouts")
        .task { refreshPendingCount() }
        .onChange(of: sessions.count) { _, _ in refreshPendingCount() }
        .onChange(of: templates.count) { _, _ in refreshPendingCount() }
        .navigationDestination(item: $navigateTo) { template in
            TemplateDetailView(template: template)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let template = WorkoutTemplate(name: "New Workout")
                    modelContext.insert(template)
                    navigateTo = template
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    private func refreshPendingCount() {
        pendingCount = (try? CoachStore.pendingProposals(in: modelContext, asOf: Date()).count) ?? 0
    }

    private func deleteTemplates(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(templates[index])
        }
    }

    private func summary(for template: WorkoutTemplate) -> String {
        let exercises = template.orderedExercises
        let exerciseCount = exercises.count
        let setCount = exercises.reduce(0) { $0 + $1.orderedSets.count }
        return "\(exerciseCount) exercise\(exerciseCount == 1 ? "" : "s") · \(setCount) set\(setCount == 1 ? "" : "s")"
    }
}
