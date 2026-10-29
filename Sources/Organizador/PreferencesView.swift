import AppKit
import OrganizadorCore
import SwiftUI

/// Ajustes as a desktop settings page: tabs for the sections, then the chosen one's rows.
struct PreferencesView: View {
    @Environment(AppModel.self) private var model
    @State private var calendarLink = ""
    @State private var selected: SettingsSection

    init(section: String? = nil) {
        _selected = State(initialValue: SettingsSection(rawValue: section ?? "") ?? .timer)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ScreenHeading(section: "Ajustes", title: "Ajustes", subtitle: selected.subtitle)
                SegmentedTabs(options: SettingsSection.allCases.map { ($0, $0.rawValue) }, selection: $selected)
                content(model.data.preferences)
            }
            .padding(.horizontal, 40).padding(.top, 28).padding(.bottom, 40)
            .pageColumn()
        }
        .font(Theme.font(size: 13))
        .foregroundStyle(Theme.text)
        .buttonStyle(.heading())
        .textFieldStyle(AppFieldStyle())
        .toggleStyle(RowToggleStyle())
        .labeledContentStyle(RowLabeledContentStyle())
        .frame(minWidth: 640, minHeight: 420)
        .background(Theme.page)
        .preferredColorScheme(.dark)
        .onAppear {
            calendarLink = model.data.preferences.calendarURL
            if model.data.preferences.exportSessionsToCalendar { model.calendarExport.connect() }
        }
    }

    @ViewBuilder
    private func content(_ preferences: Preferences) -> some View {
        switch selected {
        case .timer:
            SettingGroup {
                SettingRow("Meta diária", detail: "Quanto você quer cronometrar por dia. O Início mostra o progresso.") {
                    NumberStepper(
                        preferences.dailyTargetMinutes == 0 ? "Sem meta" : DurationFormat.short(TimeInterval(preferences.dailyTargetMinutes * 60)),
                        value: Binding(get: { preferences.dailyTargetMinutes }, set: { model.setDailyTarget(minutes: $0) }),
                        in: 0...960, step: 30
                    )
                }
                SettingRow("Pausa automática", detail: "Pausa o cronômetro quando você para de usar o Mac.") {
                    NumberStepper(
                        preferences.idlePauseMinutes == 0 ? "Desligada" : "Após \(preferences.idlePauseMinutes) min",
                        value: Binding(get: { preferences.idlePauseMinutes }, set: { model.setIdlePause(minutes: $0) }),
                        in: 0...120, step: 5
                    )
                }
            }

        case .areas:
            AreaSettings()

        case .calendar:
            SettingGroup("Receber compromissos") {
                SettingRow("Endereço secreto iCal", detail: "No Google Agenda na web: Configurações › sua agenda › \"Endereço secreto no formato iCal\". O link fica só no seu Mac.") {
                    SecureField("https://…", text: $calendarLink)
                        .onSubmit { model.setCalendarURL(calendarLink) }
                        .frame(width: 240)
                }
                SettingRow("Conexão", detail: model.hasCalendar ? "Os compromissos aparecem no Início e na Agenda." : "Nenhuma agenda conectada.") {
                    CalendarSyncStatus()
                    if model.hasCalendar {
                        Button("Desconectar", role: .destructive) {
                            calendarLink = ""
                            model.setCalendarURL("")
                        }
                    }
                    Button(model.hasCalendar ? "Atualizar" : "Conectar") { model.setCalendarURL(calendarLink) }
                        .buttonStyle(.heading(primary: true))
                        .disabled(calendarLink.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            SettingGroup("Enviar sessões") {
                SettingRow("Criar eventos das sessões", detail: "Cada sessão cronometrada vira um evento no Calendário do macOS, com atividade, objetivo, início e fim. Sessões antigas não são enviadas.") {
                    Toggle(isOn: Binding(get: { preferences.exportSessionsToCalendar }, set: { model.setExportSessions($0) })) { EmptyView() }
                        .fixedSize()
                }
                if preferences.exportSessionsToCalendar {
                    SettingRow("Calendário de destino", detail: exportDetail) { CalendarExportStatus() }
                }
            }

        case .notifications:
            SettingGroup {
                SettingRow("Objetivos parados", detail: "Um aviso por dia, no máximo, quando um objetivo passa do prazo combinado sem nenhuma sessão.") {
                    Toggle(isOn: Binding(get: { preferences.staleGoalNotifications }, set: { model.setStaleGoalNotifications($0) })) { EmptyView() }
                        .fixedSize()
                }
            }

        case .files:
            SettingGroup("Notas") {
                SettingRow("Pasta das notas", detail: model.notes.folder.path, truncateDetail: true) {
                    Button("Mostrar") { NSWorkspace.shared.activateFileViewerSelecting([model.notes.folder]) }
                    Button("Escolher…", action: chooseNotesFolder)
                }
                if !preferences.notesFolderPath.isEmpty {
                    SettingRow("Pasta padrão", detail: "Volta a guardar as notas na pasta do Organizador.") {
                        Button("Usar pasta padrão") { model.setNotesFolder(nil) }
                    }
                }
            } footnote: {
                Text("Cada nota é um arquivo .md. Você pode abrir a mesma pasta como cofre no Obsidian.")
            }
            if let url = model.dataFileURL {
                SettingGroup("Dados") {
                    SettingRow("Arquivo de dados", detail: "Atividades, sessões, objetivos e ajustes, num arquivo JSON local.") {
                        Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                }
            }
        }
    }

    private var exportDetail: String {
        switch model.calendarExport.access {
        case .denied: "Sem acesso ao Calendário. Libere em Ajustes do Sistema › Privacidade e Segurança › Calendários."
        case .unavailable: "Disponível só no app empacotado (scripts/build-app.sh)."
        default: "Com sua conta Google em Ajustes do Sistema › Contas de Internet, os eventos aparecem também no Google Agenda."
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

/// The parts of Ajustes. The raw value is the title, and what `Route.settingsSection` carries.
enum SettingsSection: String, CaseIterable {
    case timer = "Cronômetro"
    case areas = "Áreas"
    case calendar = "Calendário"
    case notifications = "Notificações"
    case files = "Notas e dados"

    var subtitle: String {
        switch self {
        case .timer: "Meta do dia e pausa automática."
        case .areas: "Agrupe atividades para ver o tempo de cada parte da vida."
        case .calendar: "Traga compromissos para o app e envie suas sessões ao Calendário."
        case .notifications: "Quando o Organizador pode chamar sua atenção."
        case .files: "Onde ficam suas notas e seus dados."
        }
    }
}

/// A run of setting rows under an optional small heading, with an optional note below.
struct SettingGroup<Content: View, Footnote: View>: View {
    var title: String?
    @ViewBuilder let content: Content
    @ViewBuilder var footnote: Footnote

    init(_ title: String? = nil, @ViewBuilder content: () -> Content, @ViewBuilder footnote: () -> Footnote) {
        self.title = title
        self.content = content()
        self.footnote = footnote()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title.uppercased())
                    .font(Theme.font(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.bottom, 6)
            }
            content
            Rectangle().fill(Theme.border).frame(height: 1)
            footnote
                .font(Theme.font(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 8)
        }
    }
}

extension SettingGroup where Footnote == EmptyView {
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, content: content, footnote: { EmptyView() })
    }
}

/// Name and explanation on the left, the control on the right, a hairline above.
struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    var dot: Color?
    var truncateDetail = false
    @ViewBuilder let control: Control

    init(_ title: String, detail: String? = nil, dot: Color? = nil, truncateDetail: Bool = false, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.dot = dot
        self.truncateDetail = truncateDetail
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    if let dot { Circle().fill(dot).frame(width: 10, height: 10) }
                    Text(title).font(Theme.font(size: 13, weight: .medium))
                }
                if let detail {
                    Text(detail)
                        .font(Theme.font(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(truncateDetail ? 1 : nil)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: !truncateDetail)
                        .help(truncateDetail ? detail : "")
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) { control }.fixedSize()
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

/// Which calendar receives the sessions, or how to get access.
private struct CalendarExportStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let exporter = model.calendarExport
        switch exporter.access {
        case .granted:
            ChoicePicker("", selection: Binding(
                get: { model.data.preferences.exportCalendarID },
                set: { model.setExportCalendar($0) }
            ), choices: [Choice(value: "", title: "Padrão do Mac")] + exporter.calendars.map {
                Choice(value: $0.calendarIdentifier, title: "\($0.title) · \($0.source.title)", color: Color(nsColor: $0.color))
            })
        case .denied:
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.danger)
                .accessibilityLabel("Sem acesso ao Calendário")
            Button("Abrir Ajustes do Sistema") { CalendarExporter.openPrivacySettings() }
        case .unavailable:
            EmptyView()
        case .unknown:
            ProgressView().controlSize(.small)
        }
    }
}
