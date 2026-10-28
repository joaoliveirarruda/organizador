import OrganizadorCore
import SwiftUI

/// One box that finds notes, objectives, areas and tasks by name (and notes by content).
struct SearchScreen: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        let text = query.trimmingCharacters(in: .whitespaces)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TextField("Buscar notas, objetivos, áreas e tarefas", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22))
                    .focused($focused)
                if !text.isEmpty {
                    results(text)
                }
            }
            .padding(48)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear { focused = true }
    }

    @ViewBuilder
    private func results(_ text: String) -> some View {
        let notes = model.notes.notes.filter {
            $0.title.localizedCaseInsensitiveContains(text) || $0.body.localizedCaseInsensitiveContains(text)
        }
        let goals = model.sortedGoals.filter { $0.title.localizedCaseInsensitiveContains(text) }
        let areas = model.data.activities.filter { $0.name.localizedCaseInsensitiveContains(text) }
        let tasks = model.data.tasks.filter { $0.title.localizedCaseInsensitiveContains(text) }

        if notes.isEmpty, goals.isEmpty, areas.isEmpty, tasks.isEmpty {
            Text("Nada encontrado.").foregroundStyle(Theme.secondaryText)
        }
        if !goals.isEmpty {
            PageSection(title: "Objetivos") {
                ForEach(goals) { goal in
                    row(goal.title, icon: IconView(icon: goal.icon, base: model.imagesFolder, fallback: "flag")) {
                        model.route = .goal(goal.id)
                    }
                }
            }
        }
        if !areas.isEmpty {
            PageSection(title: "Áreas") {
                ForEach(areas) { area in
                    row(area.name, icon: IconView(icon: area.icon, base: model.imagesFolder, fallback: "circle.fill")) {
                        model.route = .area(area.id)
                    }
                }
            }
        }
        if !notes.isEmpty {
            PageSection(title: "Notas") {
                ForEach(notes) { note in
                    row(note.title, icon: IconView(icon: note.icon, base: model.notes.folder)) {
                        model.route = .note(note.url)
                    }
                }
            }
        }
        if !tasks.isEmpty {
            PageSection(title: "Tarefas") {
                ForEach(tasks) { TaskRow(task: $0) }
            }
        }
    }

    private func row(_ title: String, icon: IconView, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon
                Text(title)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
