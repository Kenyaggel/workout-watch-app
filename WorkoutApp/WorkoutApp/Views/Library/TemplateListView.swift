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
                NavigationLink(value: template) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.name)
                        Text("\(template.plannedExercises.count) exercises")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete(perform: deleteTemplates)
        }
        .navigationTitle("Library")
        .navigationDestination(for: WorkoutTemplate.self) { template in
            TemplateDetailView(template: template)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let template = WorkoutTemplate(name: "New Template")
                    modelContext.insert(template)
                    navigateTo = template
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .navigationDestination(item: $navigateTo) { template in
            TemplateDetailView(template: template)
        }
    }

    private func deleteTemplates(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(templates[index])
        }
    }
}
