import AppKit
import OrganizadorCore
import SwiftUI

struct PreferencesView: View {
    @Environment(AppModel.self) private var model
    @State private var calendarLink = ""

    var body: some View {
        let preferences = model.data.preferences
        Form {
            Section("Cronômetro") {
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
            }

            Section("Agenda") {
                SecureField("Endereço secreto no formato iCal", text: $calendarLink)
                    .onSubmit { model.setCalendarURL(calendarLink) }
                HStack {
                    Button(model.hasCalendar ? "Salvar e atualizar" : "Conectar") {
                        model.setCalendarURL(calendarLink)
                    }
                    .disabled(calendarLink.trimmingCharacters(in: .whitespaces).isEmpty)
                    if model.hasCalendar {
                        Button("Desconectar", role: .destructive) {
                            calendarLink = ""
                            model.setCalendarURL("")
                        }
                    }
                    Spacer()
                    CalendarSyncStatus()
                }
                Text("No Google Agenda na web: Configurações › clique na sua agenda › \"Endereço secreto no formato iCal\". O link fica só no seu Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notas") {
                LabeledContent("Pasta") {
                    HStack {
                        Text(model.notes.folder.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Escolher…", action: chooseNotesFolder)
                        Button("Mostrar no Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([model.notes.folder])
                        }
                    }
                }
                if !preferences.notesFolderPath.isEmpty {
                    Button("Voltar para a pasta padrão") { model.setNotesFolder(nil) }
                }
                Text("Cada nota é um arquivo .md. Você pode abrir a mesma pasta como cofre no Obsidian.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let url = model.dataFileURL {
                Section {
                    LabeledContent("Seus dados") {
                        Button("Mostrar no Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding()
        .onAppear { calendarLink = model.data.preferences.calendarURL }
    }

    private func chooseNotesFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Usar esta pasta"
        if panel.runModal() == .OK, let url = panel.url {
            model.setNotesFolder(url)
        }
    }
}
