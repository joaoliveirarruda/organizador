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

    private var library: NotesLibrary { model.notes }

    var body: some View {
        HStack(spacing: 0) {
            noteList
                .frame(width: 230)
            Divider()
            switch mode {
            case .editor: editor
            case .graph:
                NoteGraphView(
                    graph: NoteGraph.build(notes: library.notes, goals: model.data.goals, tasks: model.data.tasks),
                    selected: library.selectedURL,
                    onOpen: open
                )
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Picker("Modo", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Button("Nova nota", systemImage: "square.and.pencil") {
                    library.create()
                    mode = .editor
                }
            }
        }
    }

    private var filteredNotes: [Note] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return library.notes }
        return library.notes.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.body.localizedCaseInsensitiveContains(query) }
    }

    private var noteList: some View {
        @Bindable var library = library
        return VStack(spacing: 0) {
            TextField("Buscar", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(8)
            List(filteredNotes, selection: $library.selectedURL) { note in
                HStack(spacing: 8) {
                    IconView(icon: FrontMatter.parse(note.body).0.icon, base: library.folder, size: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.title).lineLimit(1)
                        Text(note.modifiedAt, format: .dateTime.day().month().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(note.url)
                .contextMenu {
                    Button("Abrir como página") { model.route = .note(note.url) }
                    Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([note.url]) }
                    Divider()
                    Button("Mover para o Lixo", role: .destructive) { library.trash(note) }
                }
            }
        }
    }

    @ViewBuilder
    private var editor: some View {
        if let note = library.selected {
            NotePage(note: note).id(note.url)
        } else {
            ContentUnavailableView {
                Label(library.notes.isEmpty ? "Nenhuma nota ainda" : "Escolha uma nota", systemImage: "note.text")
            } description: {
                Text("Escreva em Markdown. Digite / no começo da linha para inserir blocos e [[Nome]] para ligar notas, objetivos ou tarefas.")
            } actions: {
                Button("Nova nota") { library.create() }
            }
        }
    }

    private func open(_ ref: GraphNode.Ref) {
        if case .note(let url) = ref {
            library.selectedURL = url
            mode = .editor
        } else {
            model.open(ref)
        }
    }
}
