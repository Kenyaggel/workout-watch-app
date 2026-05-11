import SwiftUI
import SwiftData
import WorkoutCore

struct TemplateListView: View {
    @Query(sort: \WorkoutTemplate.createdAt) var templates: [WorkoutTemplate]
    @Environment(\.modelContext) private var modelContext
    @State private var navigateTo: WorkoutTemplate?

    var body: some View {
        List {
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
