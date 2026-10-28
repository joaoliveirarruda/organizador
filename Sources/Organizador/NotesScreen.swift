import AppKit
import OrganizadorCore
import SwiftUI

struct NotesScreen: View {
    enum Mode: String, CaseIterable, Identifiable {
        case editor, graph

        var id: Self { self }
        var title: String { self == .editor ? "Editor" : "Grafo" }
    }

    @Environment(AppModel.self) private var model
    /// Opens another sidebar section, for links to goals and tasks.
    var openSection: (SidebarItem) -> Void
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
        .navigationTitle("Notas")
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
                Button("Exportar PDF…", systemImage: "arrow.down.doc") {
                    if let note = library.selected { exportPDF(note) }
                }
                .disabled(library.selected == nil)
                Button("Mostrar no Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([library.selected?.url ?? library.folder])
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title).lineLimit(1)
                    Text(note.modifiedAt, format: .dateTime.day().month().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(note.url)
                .contextMenu {
                    Button("Exportar PDF…") { exportPDF(note) }
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
            VStack(spacing: 0) {
                TitleField(note: note)
                MarkdownEditor(
                    id: note.url,
                    text: note.body,
                    onChange: { library.setBody($0, of: note.url) },
                    onOpenLink: open
                )
                Backlinks(note: note, notes: library.notes) { library.selectedURL = $0.url }
            }
        } else {
            ContentUnavailableView {
                Label(library.notes.isEmpty ? "Nenhuma nota ainda" : "Escolha uma nota", systemImage: "note.text")
            } description: {
                Text("Escreva em Markdown. Digite / no começo da linha para inserir blocos e [[Nome]] para ligar notas, metas ou tarefas.")
            } actions: {
                Button("Nova nota") { library.create() }
            }
        }
    }

    /// Opens a `[[link]]`: a note, a goal or a task. A link to nothing creates the note, as in Obsidian.
    private func open(_ target: String) {
        if let node = NoteGraph.resolve(target, notes: library.notes, goals: model.data.goals, tasks: model.data.tasks) {
            open(node.ref)
        } else {
            library.create(title: target)
        }
    }

    private func open(_ ref: GraphNode.Ref) {
        switch ref {
        case .note(let url):
            library.selectedURL = url
            mode = .editor
        case .goal: openSection(.goals)
        case .task: openSection(.tasks)
        }
    }

    private func exportPDF(_ note: Note) {
        library.saveNow()
        NotePDF.export(note)
    }
}

/// The note's title. Renaming it renames the file and updates links in other notes.
private struct TitleField: View {
    @Environment(AppModel.self) private var model
    let note: Note
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Título", text: $draft)
            .textFieldStyle(.plain)
            .font(.system(size: 26, weight: .bold))
            .padding(.horizontal, 36)
            .padding(.top, 20)
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { if !focused { commit() } }
            .onChange(of: note.url, initial: true) { draft = note.title }
    }

    private func commit() {
        let title = draft.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, title != note.title else {
            draft = note.title
            return
        }
        model.notes.rename(note, to: title)
        draft = model.notes.selected?.title ?? note.title
    }
}

/// "Mencionada em": the notes that link here.
private struct Backlinks: View {
    let note: Note
    let notes: [Note]
    var onOpen: (Note) -> Void

    var body: some View {
        let backlinks = NoteGraph.backlinks(to: note.title, in: notes)
        if !backlinks.isEmpty {
            Divider()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Text("Mencionada em").foregroundStyle(.secondary)
                    ForEach(backlinks) { backlink in
                        Button(backlink.title) { onOpen(backlink) }
                            .buttonStyle(.link)
                    }
                }
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }
}
