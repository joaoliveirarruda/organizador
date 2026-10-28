import AppKit
import OrganizadorCore
import SwiftUI

struct PreferencesView: View {
    @Environment(AppModel.self) private var model
    @State private var calendarLink = ""
    @State private var selectedSection: String?

    init(section: String? = nil) {
        _selectedSection = State(initialValue: section)
    }

    var body: some View {
        let preferences = model.data.preferences
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let selectedSection {
                    Button("‹  Ajustes") { self.selectedSection = nil }
                        .buttonStyle(.plain).foregroundStyle(Theme.secondaryText)
                    ScreenHeading(section: "Ajustes", title: selectedSection, subtitle: settingsSubtitle(selectedSection))
                    settingsForm(preferences)
                } else {
                    ScreenHeading(section: "Ajustes", title: "Ajustes", subtitle: "Preferências, arquivos e integrações.")
                    PageSection(title: "Preferências") {
                        settingsRows
                    }
                }
            }
            .padding(.horizontal, 40).padding(.top, 28).padding(.bottom, 40)
            .frame(maxWidth: 888, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            calendarLink = model.data.preferences.calendarURL
            if model.data.preferences.exportSessionsToCalendar { model.calendarExport.connect() }
        }
    }

    @ViewBuilder
    private func settingsForm(_ preferences: Preferences) -> some View {
        Form {
            if selectedSection == "Áreas" {
                AreaSettings()
            }

            if selectedSection == "Cronômetro" {
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
            }

            if selectedSection == "Receber compromissos" {
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
            }

            if selectedSection == "Enviar sessões ao Calendário" {
            Section("Sessões no Calendário do macOS") {
                Toggle("Criar um evento para cada sessão cronometrada", isOn: Binding(
                    get: { preferences.exportSessionsToCalendar },
                    set: { model.setExportSessions($0) }
                ))
                if preferences.exportSessionsToCalendar {
                    CalendarExportStatus()
                }
                Text("O evento leva a atividade, o objetivo e o horário de início e fim. Com sua conta Google adicionada em Ajustes do Sistema › Contas de Internet, ele aparece também no Google Agenda. Sessões antigas não são exportadas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            }

            if selectedSection == "Avisos de objetivos parados" {
            Section("Fio da meada") {
                Toggle("Avisar uma vez por dia sobre objetivos parados", isOn: Binding(
                    get: { preferences.staleGoalNotifications },
                    set: { model.setStaleGoalNotifications($0) }
                ))
            }
            }

            if selectedSection == "Notas e dados locais" {
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
            }

            if selectedSection == "Notas e dados locais", let url = model.dataFileURL {
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
    }

    private var settingsRows: some View {
        let rows = [
            ("Áreas", "Grupos de atividades, como Universidade ou Trabalho"),
            ("Cronômetro", "Meta diária e pausa automática"),
            ("Receber compromissos", "Agenda por endereço iCal"),
            ("Enviar sessões ao Calendário", "Permissão e calendário de destino"),
            ("Avisos de objetivos parados", "No máximo um por dia"),
            ("Notas e dados locais", "Pasta Markdown e arquivo JSON")
        ]
        return ForEach(rows, id: \.0) { title, description in
            Button { selectedSection = title } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack { Text(title).foregroundStyle(Theme.text); Spacer(); Text("›").foregroundStyle(Theme.secondaryText) }
                    Text(description).font(Theme.font(size: 11)).foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func settingsSubtitle(_ section: String) -> String {
        switch section {
        case "Áreas": "Agrupe atividades para ver o tempo de cada parte da vida."
        case "Cronômetro": "Meta diária e pausa automática."
        case "Receber compromissos": "Conecte uma agenda por endereço iCal."
        case "Enviar sessões ao Calendário": "Escolha como registrar sessões no Calendário."
        case "Avisos de objetivos parados": "Receba no máximo um aviso por dia."
        default: "Pasta Markdown e arquivo JSON locais."
        }
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

/// Calendar access and which calendar receives the sessions.
private struct CalendarExportStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let exporter = model.calendarExport
        switch exporter.access {
        case .granted:
            Picker("Calendário", selection: Binding(
                get: { model.data.preferences.exportCalendarID },
                set: { model.setExportCalendar($0) }
            )) {
                Text("Padrão do Mac").tag("")
                ForEach(exporter.calendars, id: \.calendarIdentifier) { calendar in
                    Text("\(calendar.title) · \(calendar.source.title)").tag(calendar.calendarIdentifier)
                }
            }
        case .denied:
            VStack(alignment: .leading, spacing: 6) {
                Label("O Organizador não tem acesso ao Calendário, então os eventos não são criados.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text("Libere em Ajustes do Sistema › Privacidade e Segurança › Calendários.").font(.caption)
                Button("Abrir Ajustes do Sistema") { CalendarExporter.openPrivacySettings() }
            }
        case .unavailable:
            Text("Disponível só no app empacotado (scripts/build-app.sh).").foregroundStyle(.secondary)
        case .unknown:
            ProgressView().controlSize(.small)
        }
    }
}
