import AppKit
import OrganizadorCore
import SwiftUI

/// Every note, with search, and the graph of connections between them. A note opens as its own page.
struct NotesScreen: View {
    enum Mode: String, CaseIterable, Identifiable {
        case list, graph

        var id: Self { self }
        var title: String { self == .list ? "Lista" : "Grafo" }
    }

    @Environment(AppModel.self) private var model
    @State private var mode: Mode = .list
    @State private var search = ""
    @State private var trashingNote: Note?

    private var library: NotesLibrary { model.notes }

    var body: some View {
        Group {
            if mode == .graph {
                NoteGraphView(
                    graph: NoteGraph.build(notes: library.notes, goals: model.data.goals, tasks: model.data.tasks),
                    selected: library.selectedURL,
                    onOpen: open
                )
                .padding(20)
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .principal) {
                SegmentedTabs(options: Mode.allCases.map { ($0, $0.title) }, selection: $mode)
            }
        }
        .confirmationDialog("Mover nota para o Lixo?", isPresented: Binding(get: { trashingNote != nil }, set: { if !$0 { trashingNote = nil } }), titleVisibility: .visible, presenting: trashingNote) { note in
            Button("Mover para o Lixo", role: .destructive) { library.trash(note); trashingNote = nil }
        } message: { _ in Text("A nota será removida.") }
    }

    private var list: some View {
        let notes = filteredNotes
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ScreenHeading(section: "Notas", title: "Notas", subtitle: subtitle) {
                    Button("Nova nota", systemImage: "square.and.pencil") { createNote() }
                        .buttonStyle(.heading(primary: true))
                        .help("Nova nota (⌘N)")
                        .keyboardShortcut("n")
                }
                if !library.notes.isEmpty {
                    TextField("Buscar por título ou conteúdo", text: $search)
                        .textFieldStyle(.plain)
                        .font(Theme.font(size: 14))
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
                }
                if library.notes.isEmpty {
                    Text("Nenhuma nota ainda. Crie a primeira com o botão acima ou ⌘N.")
                        .foregroundStyle(Theme.secondaryText)
                } else if notes.isEmpty {
                    Text("Nenhuma nota com “\(search.trimmingCharacters(in: .whitespaces))”.")
                        .foregroundStyle(Theme.secondaryText)
                }
                VStack(spacing: 2) {
                    ForEach(notes) { note in
                        NoteRow(note: note, base: library.folder) { model.route = .note(note.url) }
                            .contextMenu {
                                Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([note.url]) }
                                Divider()
                                Button("Mover para o Lixo", role: .destructive) { trashingNote = note }
                            }
                    }
                }
            }
            .padding(.horizontal, 40).padding(.top, 28).padding(.bottom, 40)
            .pageColumn()
        }
    }

    private var subtitle: String {
        switch library.notes.count {
        case 0: "Seu espaço para escrever e ligar ideias."
        case 1: "1 nota"
        case let count: "\(count) notas"
        }
    }

    /// Newest first, filtered by title or content.
    private var filteredNotes: [Note] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let sorted = library.notes.sorted { $0.modifiedAt > $1.modifiedAt }
        guard !query.isEmpty else { return sorted }
        return sorted.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.body.localizedCaseInsensitiveContains(query) }
    }

    private func open(_ ref: GraphNode.Ref) {
        if case .note(let url) = ref {
            model.route = .note(url)
        } else {
            model.open(ref)
        }
    }

    private func createNote() {
        if let note = library.create() {
            model.route = .note(note.url)
        }
    }
}

/// Icon, title, the first line of text and when it last changed.
private struct NoteRow: View {
    let note: Note
    let base: URL
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconView(icon: note.icon, base: base, size: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title).font(Theme.font(size: 14, weight: .medium)).foregroundStyle(Theme.text)
                    if let excerpt {
                        Text(excerpt).font(Theme.font(size: 12)).foregroundStyle(Theme.secondaryText)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 16)
                Text(note.modifiedAt.formatted(.relative(presentation: .named)))
                    .font(Theme.font(size: 12)).foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Theme.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    /// The first line of the body that isn't a heading, so the row says what's inside.
    private var excerpt: String? {
        FrontMatter.parse(note.body).body
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") }
    }
}
