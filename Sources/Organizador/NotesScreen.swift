import AppKit
import OrganizadorCore
import SwiftUI

/// Every note, with search, and the graph of connections between them.
struct NotesScreen: View {
    enum Mode: String, CaseIterable, Identifiable {
        case editor, graph

        var id: Self { self }
        var title: String { self == .editor ? "Editor" : "Grafo" }
    }

    @Environment(AppModel.self) private var model
    @State private var mode: Mode = .editor
    @State private var search = ""
    @State private var trashingNote: Note?
    @FocusState private var searchFocused: Bool

    private var library: NotesLibrary { model.notes }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeading(
                    section: "Notas",
                    title: library.selected?.title ?? "Notas",
                    subtitle: library.selected.map { "Salvo agora · \($0.modifiedAt.formatted(.relative(presentation: .named)))" } ?? "Escreva em Markdown e conecte suas ideias."
                )
                PageSection(title: "Biblioteca") {
                    TextField("Buscar notas", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .focused($searchFocused)
                    if filteredNotes.isEmpty {
                        Text("Nenhuma nota encontrada.").font(Theme.font(size: 12)).foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(filteredNotes) { note in
                        Button { library.selectedURL = note.url } label: {
                            HStack {
                                Text(note.title).foregroundStyle(Theme.text)
                                Text("›").foregroundStyle(Theme.secondaryText)
                                Spacer()
                                Text(note.modifiedAt.formatted(.relative(presentation: .named)))
                                    .font(Theme.font(size: 10)).foregroundStyle(Theme.secondaryText)
                            }
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Mover para o Lixo", role: .destructive) { trashingNote = note }
                        }
                    }
                }
                PageSection(title: mode == .editor ? "Editor" : "Grafo") {
                    if mode == .graph {
                        NoteGraphView(
                            graph: NoteGraph.build(notes: library.notes, goals: model.data.goals, tasks: model.data.tasks),
                            selected: library.selectedURL,
                            onOpen: open
                        )
                        .frame(height: 300)
                    } else if let note = library.selected {
                        let body = FrontMatter.parse(note.body).body
                        let mention = WikiLinks.targets(in: body).first
                        Text(body.isEmpty ? "Esta nota ainda está vazia." : body)
                            .font(Theme.font(size: 12)).foregroundStyle(Theme.secondaryText)
                            .lineLimit(5)
                        if let mention {
                            Button("\(mention)   ›") { openMentioned(in: note) }
                                .buttonStyle(.plain)
                        }
                        Button("Editar texto   ›") { model.route = .note(note.url) }
                            .buttonStyle(.plain)
                    } else {
                        Text("Escolha uma nota ou crie uma nova.").font(Theme.font(size: 12)).foregroundStyle(Theme.secondaryText)
                    }
                }
                if let note = library.selected {
                    PageSection(title: "Mencionada em") {
                        Backlinks(note: note, notes: library.notes) { model.route = .note($0.url) }
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                    Button("Nova nota") { createNote() }.buttonStyle(AppActionButtonStyle())
                    Button(mode == .graph ? "Editor" : "Grafo") { mode = mode == .graph ? .editor : .graph }.buttonStyle(AppActionButtonStyle())
                    Button("Buscar notas") { searchFocused = true }.buttonStyle(AppActionButtonStyle())
                    Menu("Mais ações") {
                        if let note = library.selected {
                            Button("Abrir no Finder") { NSWorkspace.shared.activateFileViewerSelecting([note.url]) }
                            Button("Abrir como página") { model.route = .note(note.url) }
                            Button("Mover para o Lixo", role: .destructive) { trashingNote = note }
                        }
                    }
                    .buttonStyle(AppActionButtonStyle())
                    Button("Ícone e capa") { if let note = library.selected { model.route = .note(note.url) } }
                        .buttonStyle(AppActionButtonStyle())
            }
            }
            .padding(.horizontal, 40).padding(.top, 28).padding(.bottom, 40)
            .frame(maxWidth: 888, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .confirmationDialog("Mover nota para o Lixo?", isPresented: Binding(get: { trashingNote != nil }, set: { if !$0 { trashingNote = nil } }), titleVisibility: .visible, presenting: trashingNote) { note in
            Button("Mover para o Lixo", role: .destructive) { library.trash(note); trashingNote = nil }
        } message: { _ in Text("A nota será removida.") }
    }

    private var filteredNotes: [Note] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return library.notes }
        return library.notes.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.body.localizedCaseInsensitiveContains(query) }
    }

    private func open(_ ref: GraphNode.Ref) {
        if case .note(let url) = ref {
            library.selectedURL = url
            mode = .editor
        } else {
            model.open(ref)
        }
    }

    private func createNote() {
        if let note = library.create() { model.route = .note(note.url) }
    }

    private func openMentioned(in note: Note) {
        guard let target = WikiLinks.targets(in: note.body).first,
              let ref = NoteGraph.resolve(target, notes: library.notes, goals: model.data.goals, tasks: model.data.tasks)?.ref else { return }
        model.open(ref)
    }
}
