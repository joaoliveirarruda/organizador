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

    private var library: NotesLibrary { model.notes }

    var body: some View {
        HStack(spacing: 0) {
            list
                .frame(width: 260)
                .background(Theme.sidebar.opacity(0.5))
            Divider()
            Group {
                if mode == .graph {
                    NoteGraphView(
                        graph: NoteGraph.build(notes: library.notes, goals: model.data.goals, tasks: model.data.tasks),
                        selected: library.selectedURL,
                        onOpen: open
                    )
                    .padding(20)
                } else if let note = library.selected {
                    NotePage(note: note).id(note.url)
                } else {
                    ContentUnavailableView {
                        Label("Nenhuma nota aberta", systemImage: "note.text")
                    } description: {
                        Text("Escolha uma nota na lista ou crie uma nova.")
                    } actions: {
                        Button("Nova nota") { createNote() }.buttonStyle(.heading(primary: true))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Modo", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
        .confirmationDialog("Mover nota para o Lixo?", isPresented: Binding(get: { trashingNote != nil }, set: { if !$0 { trashingNote = nil } }), titleVisibility: .visible, presenting: trashingNote) { note in
            Button("Mover para o Lixo", role: .destructive) { library.trash(note); trashingNote = nil }
        } message: { _ in Text("A nota será removida.") }
    }

    /// The notes column: search, the new-note button and every note.
    private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Notas").font(Theme.font(size: 16, weight: .semibold))
                Spacer()
                Button("Nova nota", systemImage: "square.and.pencil") { createNote() }
                    .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(Theme.secondaryText)
                    .help("Nova nota (⌘N)")
                    .keyboardShortcut("n")
            }
            TextField("Buscar notas", text: $search)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if filteredNotes.isEmpty {
                        Text("Nenhuma nota encontrada.").font(Theme.font(size: 12)).foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(filteredNotes) { note in
                        let selected = library.selectedURL == note.url
                        Button {
                            library.selectedURL = note.url
                            mode = .editor
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.title).foregroundStyle(Theme.text).lineLimit(1)
                                Text(note.modifiedAt.formatted(.relative(presentation: .named)))
                                    .font(Theme.font(size: 12)).foregroundStyle(Theme.secondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Theme.hover : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([note.url]) }
                            Button("Abrir como página") { model.route = .note(note.url) }
                            Divider()
                            Button("Mover para o Lixo", role: .destructive) { trashingNote = note }
                        }
                    }
                }
            }
        }
        .padding(16)
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
        if let note = library.create() {
            library.selectedURL = note.url
            mode = .editor
        }
    }
}
