import OrganizadorCore
import SwiftUI

/// A page of the main window.
enum Route: Hashable {
    case home, search, timer, notes, tasks, habits, finance
    case goal(UUID)
    case area(UUID)
    case note(URL)
}

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.page)
                .foregroundStyle(Theme.text)
        }
        .onReceive(NotificationCenter.default.publisher(for: StaleNotifier.openHome)) { _ in model.route = .home }
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
        case .notes: NotesScreen()
        case .tasks: TasksScreen()
        case .habits: HabitsScreen()
        case .finance: FinanceScreen()
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                SidebarRow(title: "Buscar", symbol: "magnifyingglass", route: .search)
                SidebarRow(title: "Home", symbol: "house", route: .home)
                SidebarRow(title: "Cronômetro", symbol: "timer", route: .timer)
                SidebarRow(title: "Nova nota", symbol: "square.and.pencil", route: nil) {
                    if let note = model.notes.create() { model.route = .note(note.url) }
                }

                if let running = model.runningActivity {
                    RunningPill(area: running).padding(.vertical, 8)
                }

                header("Objetivos") {
                    Button { addingGoal = true } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                        .help("Novo objetivo")
                }
                ForEach(model.activeGoals) { goal in
                    SidebarRow(title: goal.title, icon: goal.icon, base: model.imagesFolder, fallback: "flag", route: .goal(goal.id))
                }
                if model.activeGoals.isEmpty {
                    Text("Nenhum objetivo ativo").font(.callout).foregroundStyle(Theme.secondaryText).padding(.horizontal, 10)
                }
                if !model.inactiveGoals.isEmpty {
                    SidebarRow(
                        title: "Pausados e encerrados (\(model.inactiveGoals.count))",
                        symbol: showInactive ? "chevron.down" : "chevron.right", route: nil
                    ) { showInactive.toggle() }
                    if showInactive {
                        ForEach(model.inactiveGoals) { goal in
                            SidebarRow(title: goal.title, icon: goal.icon, base: model.imagesFolder, fallback: "flag", route: .goal(goal.id))
                                .opacity(0.7)
                        }
                    }
                }

                header("Recentes") { EmptyView() }
                ForEach(model.notes.notes.prefix(6)) { note in
                    SidebarRow(title: note.title, icon: FrontMatter.parse(note.body).0.icon, base: model.notes.folder, route: .note(note.url))
                }

                header("Mais") { EmptyView() }
                SidebarRow(title: "Todas as notas", symbol: "note.text", route: .notes)
                SidebarRow(title: "Tarefas", symbol: "checklist", route: .tasks)
                SidebarRow(title: "Hábitos", symbol: "repeat", route: .habits)
                SidebarRow(title: "Finanças", symbol: "dollarsign.circle", route: .finance)
            }
            .padding(8)
        }
        .safeAreaInset(edge: .bottom) {
            SettingsLink { Label("Ajustes", systemImage: "gearshape") }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .background(Theme.sidebar)
        .foregroundStyle(Theme.text)
        .sheet(isPresented: $addingGoal) { GoalEditor(goal: nil) }
    }

    private func header<Accessory: View>(_ title: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondaryText)
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
            }
            .font(.system(size: 14, weight: selected ? .medium : .regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected || hovering ? Theme.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The running timer, always in view.
private struct RunningPill: View {
    @Environment(AppModel.self) private var model
    let area: Activity

    var body: some View {
        let color = Color(hex: area.colorHex)
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Button(area.name) { model.route = .area(area.id) }
                .buttonStyle(.plain).lineLimit(1)
            Spacer(minLength: 0)
            Text(DurationFormat.clock(model.currentElapsed)).monospacedDigit().foregroundStyle(Theme.secondaryText)
            Button { model.toggle(area.id) } label: { Image(systemName: "pause.fill") }
                .buttonStyle(.borderless)
                .help("Pausar")
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.15)))
    }
}
