import OrganizadorCore
import SwiftUI

/// The timer, Yeolpumta style: today's total in the running area's color, every area one click away,
/// and the day's calendar with meetings and timed blocks side by side.
struct TimerScreen: View {
    @Environment(AppModel.self) private var model
    @State private var showingNewActivity = false
    @State private var editingActivity: Activity?
    @State private var addingSession = false
    @State private var archivingActivity: Activity?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TimerHeader()

                if let notice = model.pauseNotice {
                    HStack {
                        Image(systemName: "pause.circle")
                        Text(notice)
                        Spacer()
                        Button("OK") { model.pauseNotice = nil }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.15)))
                }

                PageSection(title: "Atividades") {
                    activities
                } accessory: {
                    Button("Atividade", systemImage: "plus") { showingNewActivity = true }
                        .buttonStyle(.heading())
                        .keyboardShortcut("n")
                }

                PageSection(title: "Sessões de hoje") {
                    sessions
                } accessory: {
                    Button("Sessão", systemImage: "plus") { addingSession = true }
                        .buttonStyle(.heading())
                        .disabled(model.activeActivities.isEmpty)
                        .help("Registrar uma sessão que o cronômetro não pegou")
                }
            }
            .padding(.horizontal, 40).padding(.top, 28).padding(.bottom, 40)
            .pageColumn()
        }
        .toolbar { ToolbarItem(placement: .principal) { TimeTabs() } }
        .floatingSheet(isPresented: $showingNewActivity) {
            ActivityEditor(activity: nil)
        }
        .floatingSheet(item: $editingActivity) { activity in
            ActivityEditor(activity: activity)
        }
        .floatingSheet(isPresented: $addingSession) { SessionEditor(session: nil) }
        .appConfirm(
            "Arquivar atividade?",
            isPresented: Binding(get: { archivingActivity != nil }, set: { if !$0 { archivingActivity = nil } }),
            titleVisibility: .visible,
            presenting: archivingActivity
        ) { area in
            Button("Arquivar \(area.name)", role: .destructive) {
                model.archiveActivity(area.id)
                archivingActivity = nil
            }
        } message: { area in
            Text("As sessões registradas serão mantidas.")
        }
    }

    @ViewBuilder
    private var activities: some View {
        if model.activeActivities.isEmpty {
            Text("Crie uma atividade para começar a cronometrar.").foregroundStyle(Theme.secondaryText)
        }
        ForEach(model.activeActivities) { area in
            AreaTimerRow(area: area)
                .appContextMenu {
                    Button("Abrir") { model.route = .area(area.id) }
                    Button("Editar") { editingActivity = area }
                    Button("Arquivar", role: .destructive) { archivingActivity = area }
                }
        }
    }

    @ViewBuilder
    private var sessions: some View {
        let sessions = model.data.sessions.filter { model.calendar.isDate($0.start, inSameDayAs: model.now) }.sorted { $0.start < $1.start }
        if sessions.isEmpty {
            Text("Nenhuma sessão registrada hoje.").font(Theme.font(size: 12)).foregroundStyle(Theme.secondaryText)
        }
        ForEach(sessions) { session in
            HStack {
                Text("\(session.start.formatted(date: .omitted, time: .shortened))–\(session.end.formatted(date: .omitted, time: .shortened))")
                    .monospacedDigit().foregroundStyle(Theme.secondaryText)
                Text(model.activity(session.activityID)?.name ?? "Atividade removida")
                Spacer()
                Text(DurationFormat.short(session.duration)).foregroundStyle(Theme.secondaryText)
            }
            .font(Theme.font(size: 12))
            .padding(.vertical, 5)
        }
    }
}

/// Cronômetro and Relatório are two views of the same timed sessions, under one "Tempo" in the sidebar.
struct TimeTabs: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        SegmentedTabs(options: [(Route.timer, "Cronômetro"), (Route.report, "Relatório")], selection: $model.route)
    }
}

private struct TimerHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let total = model.todayTotal
        let target = model.dailyTarget
        let running = model.runningActivity
        let goal = running?.goalID.flatMap(model.goal)
        ScreenHeading(
            section: "Tempo",
            title: "Cronômetro",
            subtitle: "Hoje · \(DurationFormat.short(total))" + (target > 0 ? " de uma meta de \(DurationFormat.short(target))" : "") + (goal.map { " · \($0.title)" } ?? "")
        )
    }
}

/// An area with ▶, its objective and progress, and today's time.
private struct AreaTimerRow: View {
    @Environment(AppModel.self) private var model
    let area: Activity

    var body: some View {
        let isRunning = model.running?.activityID == area.id
        let color = Color(hex: area.colorHex)
        let goal = area.goalID.flatMap(model.goal)
        HStack(spacing: 12) {
            Button { model.toggle(area.id) } label: {
                Image(systemName: isRunning ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(color)
            }
            .buttonStyle(.plain)
            .help(isRunning ? "Pausar" : "Começar")
            Button { model.route = .area(area.id) } label: {
                HStack(spacing: 8) {
                    IconView(icon: area.icon, base: model.imagesFolder, fallback: "circle.fill", size: 18)
                        .foregroundStyle(color)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(area.name).font(Theme.font(size: 15, weight: .medium))
                        if let goal {
                            HStack(spacing: 6) {
                                Text(goal.title).font(.caption).foregroundStyle(Theme.secondaryText)
                                if let fraction = model.progress(for: goal).fraction {
                                    ProgressView(value: fraction).tint(color).frame(width: 80)
                                }
                            }
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text(DurationFormat.clock(model.todayTotal(for: area.id)))
                .monospacedDigit()
                .foregroundStyle(isRunning ? Theme.text : Theme.secondaryText)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(isRunning ? color.opacity(0.15) : Theme.card))
    }
}

/// The day hour by hour: meetings from the agenda next to the timed blocks. Click a block to edit it.
struct DayCalendar: View {
    @Environment(AppModel.self) private var model
    let day: Date
    @State private var editingSession: FocusSession?
    @State private var addingSession = false
    private let hourHeight: CGFloat = 44

    var body: some View {
        let interval = Stats.day(containing: day, calendar: model.calendar)
        let events = model.calendarEvents(on: day).filter { !$0.isAllDay }
        let sessions = model.data.sessions.filter { $0.end > interval.start && $0.start < interval.end }
        VStack(spacing: 0) {
            HStack {
                Text("Calendário do dia").font(Theme.font(size: 13, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                Spacer()
                Button { addingSession = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("Incluir sessão à mão")
                    .disabled(model.activeActivities.isEmpty)
            }
            .padding(12)
            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: 0) {
                            ForEach(0..<24, id: \.self) { hour in
                                HStack(alignment: .top) {
                                    Text("\(hour)h").font(.caption2).foregroundStyle(Theme.secondaryText).frame(width: 28, alignment: .trailing)
                                    VStack { Divider() }
                                }
                                .frame(height: hourHeight, alignment: .top)
                                .id(hour)
                            }
                        }
                        ForEach(events) { event in
                            block(start: event.start, end: event.end, in: interval, column: 0) {
                                Text(event.title).font(.caption2).lineLimit(2)
                            }
                            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.accent.opacity(0.18)))
                        }
                        ForEach(sessions) { session in
                            let area = model.activity(session.activityID)
                            block(start: session.start, end: session.end, in: interval, column: 1) {
                                Text(area?.name ?? "").font(.caption2).lineLimit(2)
                            }
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: area?.colorHex ?? "").opacity(0.35)))
                            .onTapGesture { editingSession = session }
                            .help("Clique para editar")
                        }
                        if let running = model.running, let area = model.activity(running.activityID) {
                            block(start: running.startedAt, end: model.now, in: interval, column: 1) {
                                Text(area.name).font(.caption2).lineLimit(1)
                            }
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: area.colorHex).opacity(0.6)))
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .onAppear { proxy.scrollTo(max(0, model.calendar.component(.hour, from: model.now) - 2), anchor: .top) }
            }
        }
        .background(Theme.sidebar)
        .floatingSheet(item: $editingSession) { SessionEditor(session: $0) }
        .floatingSheet(isPresented: $addingSession) { SessionEditor(session: nil) }
    }

    /// Meetings go in the left column, timed work in the right one.
    private func block<Label: View>(
        start: Date, end: Date, in interval: DateInterval, column: Int, @ViewBuilder label: () -> Label
    ) -> some View {
        let top = CGFloat(max(start, interval.start).timeIntervalSince(interval.start) / 3600) * hourHeight
        let height = max(14, CGFloat(min(end, interval.end).timeIntervalSince(max(start, interval.start)) / 3600) * hourHeight)
        return label()
            .padding(.horizontal, 4)
            .frame(width: 112, height: height, alignment: .topLeading)
            .offset(x: 36 + CGFloat(column) * 116, y: top)
    }
}

/// One activity with its time today. Clicking starts it, or pauses it if it is running.
struct ActivityToggleRow: View {
    @Environment(AppModel.self) private var model
    let activity: Activity
    var compact = false

    var body: some View {
        let isRunning = model.running?.activityID == activity.id
        let color = Color(hex: activity.colorHex)
        Button {
            model.toggle(activity.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isRunning ? "pause.circle.fill" : "play.circle.fill")
                    .font(compact ? .title3 : .title)
                    .foregroundStyle(color)
                Text(activity.name)
                    .font(compact ? .body : .title3)
                Spacer()
                Text(DurationFormat.clock(model.todayTotal(for: activity.id)))
                    .monospacedDigit()
                    .foregroundStyle(isRunning ? .primary : .secondary)
            }
            .padding(.vertical, compact ? 4 : 10)
            .padding(.horizontal, compact ? 6 : 14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isRunning ? color.opacity(0.18) : Color.secondary.opacity(compact ? 0 : 0.06))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ActivityEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.closeSheet) private var dismiss
    let activity: Activity?
    @State private var name: String
    @State private var colorHex: String
    @State private var goalID: UUID?
    @State private var areaID: UUID?
    @State private var addingArea = false

    init(activity: Activity?, goalID: UUID? = nil) {
        self.activity = activity
        _name = State(initialValue: activity?.name ?? "")
        _colorHex = State(initialValue: activity?.colorHex ?? Palette.colors[3])
        _goalID = State(initialValue: activity?.goalID ?? goalID)
        _areaID = State(initialValue: activity?.areaID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(activity == nil ? "Nova atividade" : "Editar atividade").font(Theme.font(size: 16, weight: .semibold))
            TextField("Nome", text: $name)
            HStack(spacing: 8) {
                ForEach(Palette.colors, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(Theme.text, lineWidth: hex == colorHex ? 2 : 0))
                        .onTapGesture { colorHex = hex }
                }
            }
            HStack {
                ChoicePicker("Área", selection: $areaID, choices: [Choice(value: nil, title: "Sem área")] + model.areas.map {
                    Choice(value: Optional($0.id), title: $0.name, color: Color(hex: $0.colorHex))
                })
                Button("Nova área…") { addingArea = true }
            }
            ChoicePicker("Conta para o objetivo", selection: $goalID, choices: [Choice(value: nil, title: "Nenhum (atividade solta)")] + model.activeGoals.map {
                Choice(value: Optional($0.id), title: $0.title)
            })
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Salvar") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.heading(primary: true))
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .floatingSheet(isPresented: $addingArea) {
            AreaEditor(area: nil) { areaID = $0.id }
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        if var activity {
            activity.name = trimmedName
            activity.colorHex = colorHex
            activity.goalID = goalID
            activity.areaID = areaID
            model.updateActivity(activity)
        } else {
            model.addActivity(name: trimmedName, colorHex: colorHex, goalID: goalID, areaID: areaID)
        }
        dismiss()
    }
}
