import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case timer, goals, history, stats

    var id: Self { self }

    var title: String {
        switch self {
        case .timer: "Cronômetro"
        case .goals: "Metas"
        case .history: "Histórico"
        case .stats: "Estatísticas"
        }
    }

    var systemImage: String {
        switch self {
        case .timer: "timer"
        case .goals: "flag"
        case .history: "list.bullet.rectangle"
        case .stats: "chart.bar"
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SidebarItem? = .timer

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.systemImage)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch selection ?? .timer {
            case .timer: TimerScreen()
            case .goals: GoalsScreen()
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
