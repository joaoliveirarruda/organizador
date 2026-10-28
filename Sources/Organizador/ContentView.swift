import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case today, agenda, timer, goals, tasks, habits, history, stats

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "Hoje"
        case .agenda: "Agenda"
        case .timer: "Cronômetro"
        case .goals: "Metas"
        case .tasks: "Tarefas"
        case .habits: "Hábitos"
        case .history: "Histórico"
        case .stats: "Estatísticas"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .agenda: "calendar"
        case .timer: "timer"
        case .goals: "flag"
        case .tasks: "checklist"
        case .habits: "repeat"
        case .history: "list.bullet.rectangle"
        case .stats: "chart.bar"
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SidebarItem? = .today

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.systemImage)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch selection ?? .today {
            case .today: TodayScreen()
            case .agenda: AgendaScreen()
            case .timer: TimerScreen()
            case .goals: GoalsScreen()
            case .tasks: TasksScreen()
            case .habits: HabitsScreen()
            case .history: HistoryScreen()
            case .stats: StatsScreen()
            }
        }
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
}
