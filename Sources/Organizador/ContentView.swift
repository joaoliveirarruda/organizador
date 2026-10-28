import OrganizadorCore
import SwiftUI

/// A page of the main window.
enum Route: Hashable {
    case home, search, timer, agenda, notes, tasks, habits, finance, settings
    case settingsSection(String)
    case goal(UUID)
    case area(UUID)
    case note(URL)
}

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 232, ideal: 232, max: 232)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.page)
                .foregroundStyle(Theme.text)
                // A clear toolbar lets each column's own color reach the top of the window.
                .toolbarBackground(.hidden, for: .windowToolbar)
        }
        .onReceive(NotificationCenter.default.publisher(for: StaleNotifier.openHome)) { _ in model.route = .home }
        .preferredColorScheme(.dark)
        .alert(
            "Algo deu errado",
            isPresented: Binding(
                get: { model.lastError != nil },
                set: { if !$0 { model.lastError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastError ?? "")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.route {
        case .home: HomeScreen()
        case .search: SearchScreen()
        case .timer: TimerScreen()
        case .agenda: AgendaScreen()
        case .notes: NotesScreen()
        case .tasks: TasksScreen()
        case .habits: HabitsScreen()
        case .finance: FinanceScreen()
        case .settings: PreferencesView()
        case .settingsSection(let section): PreferencesView(section: section)
        case .goal(let id):
            if let goal = model.goal(id) { GoalPage(goal: goal) } else { missing }
        case .area(let id):
            if let area = model.activity(id) { AreaPage(area: area) } else { missing }
        case .note(let url):
            if let note = model.notes.notes.first(where: { $0.url == url }) {
                NotePage(note: note).id(url)
            } else {
                missing
            }
        }
    }

    private var missing: some View {
        ContentUnavailableView("Não encontrado", systemImage: "questionmark.folder")
    }
}

/// Notion-like sidebar: fixed shortcuts, the running timer, objectives and recent notes.
private struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @State private var addingGoal = false
    @State private var showInactive = false
    @State private var trashingNote: Note?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("organizador").font(Theme.font(size: 16, weight: .semibold))
                    Text("SEU ESPAÇO").font(Theme.font(size: 10, weight: .semibold)).foregroundStyle(Color(hex: "72817d"))
                }
                .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 10)
                SidebarRow(title: "Buscar", symbol: "magnifyingglass", route: .search)
                SidebarRow(title: "Início", symbol: "house", route: .home)
                SidebarRow(title: "Cronômetro", symbol: "timer", route: .timer)
                SidebarRow(title: "Agenda", symbol: "calendar", route: .agenda)
                SidebarRow(title: "Tarefas", symbol: "checklist", route: .tasks)
                SidebarRow(title: "Hábitos", symbol: "repeat", route: .habits)
                SidebarRow(title: "Notas", symbol: "note.text", route: .notes)
                SidebarRow(title: "Finanças", symbol: "dollarsign.circle", route: .finance)

                header("Objetivos") { EmptyView() }
                ForEach(model.activeGoals) { goal in
                    SidebarRow(title: goal.title, icon: goal.icon, base: model.imagesFolder, fallback: "flag", route: .goal(goal.id))
                }
                if model.activeGoals.isEmpty {
                    Text("Nenhum objetivo ativo").font(.callout).foregroundStyle(Theme.secondaryText).padding(.horizontal, 10)
                }
                SidebarRow(
                    title: "Pausados e encerrados",
                    symbol: showInactive ? "chevron.down" : "chevron.right", route: nil
                ) { showInactive.toggle() }
                if showInactive {
                    ForEach(model.inactiveGoals) { goal in
                        SidebarRow(title: goal.title, icon: goal.icon, base: model.imagesFolder, fallback: "flag", route: .goal(goal.id))
                            .opacity(0.7)
                    }
                }
                SidebarRow(title: "+ Novo objetivo", symbol: "plus", route: nil) { addingGoal = true }

                header("Recentes") { EmptyView() }
                ForEach(model.notes.notes.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(6)) { note in
                    SidebarRow(title: note.title, icon: note.icon, base: model.notes.folder, route: .note(note.url)) {
                        Button("Abrir") { model.route = .note(note.url) }
                        Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([note.url]) }
                        Button("Exportar PDF…") {
                            model.notes.saveNow()
                            NotePDF.export(Note(url: note.url, body: FrontMatter.parse(note.body).body, modifiedAt: note.modifiedAt))
                        }
                        Divider()
                        Button("Mover para o Lixo", role: .destructive) { trashingNote = note }
                    }
                }

            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) {
            SidebarRow(title: "Ajustes", symbol: "gearshape", route: .settings).padding(8)
        }
        .background(Theme.sidebar)
        .foregroundStyle(Theme.text)
        .sheet(isPresented: $addingGoal) { GoalEditor(goal: nil) }
        .confirmationDialog("Mover nota para o Lixo?", isPresented: Binding(get: { trashingNote != nil }, set: { if !$0 { trashingNote = nil } }), titleVisibility: .visible, presenting: trashingNote) { note in
            Button("Mover para o Lixo", role: .destructive) {
                model.notes.trash(note)
                if model.route == .note(note.url) { model.route = .notes }
                trashingNote = nil
            }
        } message: { _ in Text("A nota será removida.") }
    }

    private func header<Accessory: View>(_ title: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack {
            Text(title).font(Theme.font(size: 11, weight: .semibold)).foregroundStyle(Theme.secondaryText)
            Spacer()
            accessory()
        }
        .padding(.horizontal, 10)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }
}

private struct SidebarRow: View {
    @Environment(AppModel.self) private var model
    let title: String
    var symbol: String?
    var icon: Icon?
    var base: URL?
    var fallback = "doc.text"
    let route: Route?
    var action: (() -> Void)?
    /// Actions shown behind a "…" button while the pointer is over the row.
    var menu: AnyView?
    @State private var hovering = false

    init(title: String, symbol: String, route: Route?, action: (() -> Void)? = nil) {
        self.title = title
        self.symbol = symbol
        self.route = route
        self.action = action
    }

    init(title: String, icon: Icon?, base: URL, fallback: String = "doc.text", route: Route) {
        self.title = title
        self.icon = icon
        self.base = base
        self.fallback = fallback
        self.route = route
    }

    init<Menu: View>(title: String, icon: Icon?, base: URL, route: Route, @ViewBuilder menu: () -> Menu) {
        self.init(title: title, icon: icon, base: base, route: route)
        self.menu = AnyView(menu())
    }

    var body: some View {
        let selected = route != nil && model.route == route
        Button {
            if let action { action() } else if let route { model.route = route }
        } label: {
            HStack(spacing: 8) {
                if let symbol {
                    Image(systemName: symbol).frame(width: 18).foregroundStyle(Theme.secondaryText)
                } else if let base {
                    IconView(icon: icon, base: base, fallback: fallback, size: 18)
                }
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
                if menu != nil, hovering { Color.clear.frame(width: 26) }
            }
            .font(Theme.font(size: 13, weight: selected ? .medium : .regular))
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected || hovering ? Theme.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if let menu, hovering {
                Menu { menu } label: {
                    Image(systemName: "ellipsis").foregroundStyle(Theme.secondaryText).frame(width: 30, height: 30).contentShape(Rectangle())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                .padding(.trailing, 2)
            }
        }
        .onHover { hovering = $0 }
    }
}
