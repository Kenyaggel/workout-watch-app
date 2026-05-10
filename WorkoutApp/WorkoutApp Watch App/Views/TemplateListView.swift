import SwiftUI
import SwiftData
import WorkoutCore

struct TemplateListView: View {
    @Query(sort: \WorkoutTemplate.createdAt, order: .reverse)
    private var templates: [WorkoutTemplate]

    @State private var startedPlan: SessionPlan?

    var body: some View {
        NavigationStack {
            List {
                if templates.isEmpty {
                    Text("No templates yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(templates) { template in
                    Button {
                        startedPlan = SessionPlan.from(template: template)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(template.name).font(.headline)
                            Text("\(template.orderedExercises.count) exercises")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Workouts")
            .navigationDestination(item: $startedPlan) { plan in
                ActiveSessionView(plan: plan)
            }
        }
    }
}

extension SessionPlan: Identifiable, Hashable {
    public var id: String { templateName + "-" + String(exercises.count) }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(templateName)
        for ex in exercises {
            hasher.combine(ex.name)
            hasher.combine(ex.sets.count)
        }
    }
}
