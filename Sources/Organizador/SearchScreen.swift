import OrganizadorCore
import ShadcnUI
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
                ScreenHeading(section: "Busca", title: "Buscar em todo o espaço", subtitle: "Encontre notas, objetivos, atividades e tarefas.")
                TextField("Buscar notas, objetivos, atividades e tarefas", text: $query)
                    .textFieldStyle(.plain)
                    .font(Theme.font(size: 16))
                    .focused($focused)
                    .padding(.vertical, 10)
                    .fieldChrome()
                if !text.isEmpty {
                    results(text)
                }
            }
            .padding(.horizontal, 40).padding(.top, 28).padding(.bottom, 40)
            .pageColumn()
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
            PageSection(title: "Atividades") {
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
