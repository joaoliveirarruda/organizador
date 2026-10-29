import OrganizadorCore
import ShadcnUI
import SwiftUI

/// A page of the main window.
enum Route: Hashable {
    case home, search, timer, report, notes, tasks, habits, finance, settings
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
        .overlay { OverlayHost() }
        .overlay(alignment: .bottom) {
            if let error = model.lastError { ErrorToast(message: error) }
        }
        // Outermost, so ShadKit's own popovers (selects) draw above the app's cards too.
        .shadcnTheme(Theme.shadcn, glass: false)
    }

    @ViewBuilder
    private var detail: some View {
        switch model.route {
        case .home: HomeScreen()
        case .search: SearchScreen()
        case .timer: TimerScreen()
        case .report: ReportScreen()
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
                    Text("SEU ESPAÇO").font(Theme.font(size: 11, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 10)
                SidebarRow(title: "Buscar", symbol: "magnifyingglass", route: .search)
                SidebarRow(title: "Hoje", symbol: "sun.max", route: .home, also: [.habits])
                SidebarRow(title: "Tempo", symbol: "timer", route: .timer, also: [.report])
                SidebarRow(title: "Tarefas", symbol: "checklist", route: .tasks)
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
                        ShadcnMenuSeparator()
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
        .floatingSheet(isPresented: $addingGoal) { GoalEditor(goal: nil) }
        .appConfirm("Mover nota para o Lixo?", isPresented: Binding(get: { trashingNote != nil }, set: { if !$0 { trashingNote = nil } }), titleVisibility: .visible, presenting: trashingNote) { note in
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
    /// Other pages that live under this row, so it stays highlighted on them.
    var also: [Route] = []
    var action: (() -> Void)?
    /// Actions shown behind a "…" button while the pointer is over the row.
    var menu: AnyView?
    @State private var hovering = false

    init(title: String, symbol: String, route: Route?, also: [Route] = [], action: (() -> Void)? = nil) {
        self.title = title
        self.symbol = symbol
        self.route = route
        self.also = also
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
        let selected = route != nil && (model.route == route || also.contains(model.route))
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
                PopupMenu { menu } label: {
                    Image(systemName: "ellipsis").foregroundStyle(Theme.secondaryText).frame(width: 30, height: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 2)
            }
        }
        .onHover { hovering = $0 }
    }
}

/// "Algo deu errado" as a note at the bottom of the window that goes away by itself or on a click.
private struct ErrorToast: View {
    @Environment(AppModel.self) private var model
    let message: String

    var body: some View {
        ShadcnAlert(variant: .destructive, systemImage: "exclamationmark.triangle") {
            ShadcnAlertDescription(message)
        }
        .frame(maxWidth: 480)
        .shadcnShadow(.lg)
        .padding(.bottom, 24)
        .onTapGesture { model.lastError = nil }
        .task(id: message) {
            try? await Task.sleep(for: .seconds(6))
            if model.lastError == message { model.lastError = nil }
        }
    }
}
