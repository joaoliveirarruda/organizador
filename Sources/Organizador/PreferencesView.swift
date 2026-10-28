import AppKit
import OrganizadorCore
import SwiftUI

struct PreferencesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let preferences = model.data.preferences
        Form {
            Stepper(
                "Meta diária: \(preferences.dailyTargetMinutes == 0 ? "sem meta" : DurationFormat.short(TimeInterval(preferences.dailyTargetMinutes * 60)))",
                value: Binding(
                    get: { preferences.dailyTargetMinutes },
                    set: { model.setDailyTarget(minutes: $0) }
                ),
                in: 0...960,
                step: 30
            )

            Stepper(
                "Pausar após \(preferences.idlePauseMinutes == 0 ? "nunca (desligado)" : "\(preferences.idlePauseMinutes) min sem usar o Mac")",
                value: Binding(
                    get: { preferences.idlePauseMinutes },
                    set: { model.setIdlePause(minutes: $0) }
                ),
                in: 0...120,
                step: 5
            )

            if let url = model.dataFileURL {
                LabeledContent("Seus dados") {
                    Button("Mostrar no Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding()
    }
}
