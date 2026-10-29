import AppKit
import OrganizadorCore
import ShadcnUI
import SwiftUI

struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        Text("\(Image(systemName: model.running == nil ? "timer" : "record.circle")) \(model.menuBarTitle)")
            .monospacedDigit()
    }
}

/// The panel that opens from the menu bar: today's total and one click to start or pause.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Hoje").font(.headline)
                Spacer()
                Text(DurationFormat.clock(model.todayTotal))
                    .font(.headline)
                    .monospacedDigit()
            }
            if model.dailyTarget > 0 {
                ShadcnProgress(value: min(1, model.todayTotal / model.dailyTarget))
            }
            if let notice = model.pauseNotice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }

            ShadcnSeparator()

            ForEach(model.activeActivities) { activity in
                ActivityToggleRow(activity: activity, compact: true)
            }

            ShadcnSeparator()

            HStack {
                Button("Abrir Organizador") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Sair") { NSApp.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 300)
    }
}
