import AppKit
import OrganizadorCore
import SwiftUI

/// A note opened as a page: icon and cover (kept in the file's front matter), title, editor and backlinks.
struct NotePage: View {
    @Environment(AppModel.self) private var model
    let note: Note
    @State private var confirmingTrash = false

    private var library: NotesLibrary { model.notes }

    var body: some View {
        let (meta, body) = FrontMatter.parse(note.body)
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                icon: meta.icon, cover: meta.cover, base: library.folder,
                imagesFolder: library.folder.appendingPathComponent("anexos", isDirectory: true),
                setIcon: { icon in change { $0.icon = icon } },
                setCover: { cover in change { $0.cover = cover } }
            ) {
                TitleField(note: note)
            }
            MarkdownEditor(
                id: note.url,
                text: body,
                // The editor only sees the body; the front matter is put back on every change.
                onChange: { library.setBody(FrontMatter.parse(current.body).0.render($0), of: note.url) },
                onOpenLink: { model.open(link: $0) }
            )
            Backlinks(note: note, notes: library.notes) { model.route = .note($0.url) }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Exportar PDF…", systemImage: "arrow.down.doc") {
                    library.saveNow()
                    NotePDF.export(Note(url: current.url, body: FrontMatter.parse(current.body).body, modifiedAt: current.modifiedAt))
                }
                Button("Mostrar no Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([note.url])
                }
                Button("Mover para o Lixo", systemImage: "trash") { confirmingTrash = true }
            }
        }
        .confirmationDialog("Mover nota para o Lixo?", isPresented: $confirmingTrash, titleVisibility: .visible) {
            Button("Mover para o Lixo", role: .destructive) {
                library.trash(current)
                model.route = .notes
            }
        } message: { Text("A nota será removida.") }
    }

    /// The note as it is now in the library (the view's copy may be a keystroke behind).
    private var current: Note {
        library.notes.first { $0.url == note.url } ?? note
    }

    private func change(_ edit: (inout FrontMatter) -> Void) {
        var (meta, body) = FrontMatter.parse(current.body)
        edit(&meta)
        library.setBody(meta.render(body), of: note.url)
    }
}

/// The note's title. Renaming it renames the file and updates links in other notes.
struct TitleField: View {
    @Environment(AppModel.self) private var model
    let note: Note
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Título", text: $draft)
            .textFieldStyle(.plain)
            .font(Theme.font(size: 36, weight: .bold))
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
        if model.route == .note(note.url), let renamed = model.notes.selectedURL {
            model.route = .note(renamed)
        }
        draft = model.notes.selected?.title ?? note.title
    }
}

/// "Mencionada em": the notes that link here.
struct Backlinks: View {
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
