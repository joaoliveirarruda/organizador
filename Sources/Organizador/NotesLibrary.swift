import AppKit
import Foundation
import Observation
import OrganizadorCore

/// The notes folder as the app sees it. Typing changes notes in memory right away and
/// writes them to disk half a second later.
@MainActor
@Observable
final class NotesLibrary {
    private(set) var notes: [Note] = []
    var selectedURL: URL?
    /// Called with a message when reading or writing fails.
    @ObservationIgnored var onError: (String) -> Void = { _ in }

    @ObservationIgnored private(set) var store: NoteStore
    @ObservationIgnored private var unsaved = Set<URL>()
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(folder: URL) {
        store = NoteStore(folder: folder)
        reload()
        // ponytail: picks up edits made in Obsidian/Finder when the app comes back to the front; FSEvents if it must be live.
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        })
        for name in [NSApplication.willResignActiveNotification, NSApplication.willTerminateNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.saveNow() }
            })
        }
    }

    var folder: URL { store.folder }

    var selected: Note? {
        guard let selectedURL else { return nil }
        return notes.first { $0.url == selectedURL }
    }

    func note(titled title: String) -> Note? {
        notes.first { $0.title.caseInsensitiveCompare(title) == .orderedSame }
    }

    /// Reads the folder again, keeping the text of notes not saved yet.
    func reload() {
        do {
            let inMemory = Dictionary(notes.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
            notes = try store.list().map { unsaved.contains($0.url) ? inMemory[$0.url] ?? $0 : $0 }
            if let selectedURL, !notes.contains(where: { $0.url == selectedURL }) {
                self.selectedURL = nil
            }
        } catch {
            onError("Não foi possível ler as notas em \(folder.path): \(error.localizedDescription)")
        }
    }

    func setFolder(_ url: URL) {
        saveNow()
        store = NoteStore(folder: url)
        selectedURL = nil
        notes = []
        reload()
    }

    /// Creates a note and selects it.
    @discardableResult
    func create(title: String = "Sem título", body: String = "") -> Note? {
        do {
            let note = try store.create(title: title, body: body)
            notes.insert(note, at: 0)
            selectedURL = note.url
            return note
        } catch {
            onError("Não foi possível criar a nota: \(error.localizedDescription)")
            return nil
        }
    }

    func setBody(_ body: String, of url: URL) {
        guard let index = notes.firstIndex(where: { $0.url == url }), notes[index].body != body else { return }
        notes[index].body = body
        notes[index].modifiedAt = Date()
        unsaved.insert(url)
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        for url in unsaved {
            guard let note = notes.first(where: { $0.url == url }) else { continue }
            do {
                try store.save(note)
            } catch {
                onError("Não foi possível salvar \"\(note.title)\": \(error.localizedDescription)")
                return
            }
        }
        unsaved.removeAll()
    }

    /// Renames the note and updates the links to it in the other notes.
    func rename(_ note: Note, to title: String) {
        saveNow()
        do {
            let renamed = try store.rename(note, to: title)
            reload()
            selectedURL = renamed.url
        } catch {
            onError(error.localizedDescription)
        }
    }

    func trash(_ note: Note) {
        unsaved.remove(note.url)
        do {
            try store.trash(note)
            notes.removeAll { $0.url == note.url }
            if selectedURL == note.url { selectedURL = nil }
        } catch {
            onError("Não foi possível mover a nota para o Lixo: \(error.localizedDescription)")
        }
    }
}
