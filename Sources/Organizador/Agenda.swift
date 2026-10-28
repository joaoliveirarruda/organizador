import OrganizadorCore
import SwiftUI

struct AgendaScreen: View {
    @Environment(AppModel.self) private var model
    @State private var day = Date()
    @State private var addingSession = false
    @State private var editingSession: FocusSession?

    private var sessions: [FocusSession] {
        model.data.sessions.filter { model.calendar.isDate($0.start, inSameDayAs: day) }.sorted { $0.start < $1.start }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeading(section: "Agenda", title: "Agenda", subtitle: day.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized + (model.calendar.isDateInToday(day) ? " · dia atual" : ""))
                PageSection(title: "Compromissos") {
                    if model.calendarEvents(on: day).isEmpty {
                        Text(model.hasCalendar ? "Nenhum compromisso neste dia." : "Conecte uma agenda em Ajustes para receber compromissos.")
                            .font(Theme.font(size: 12)).foregroundStyle(Theme.secondaryText)
                    } else {
                        ForEach(model.calendarEvents(on: day)) { event in
                            EventRow(event: event, now: model.now)
                        }
                    }
                }
                PageSection(title: "Sessões") {
                    if sessions.isEmpty {
                        Text("Nenhuma sessão registrada neste dia.").font(Theme.font(size: 12)).foregroundStyle(Theme.secondaryText)
                    } else {
                        ForEach(sessions) { session in
                            HStack {
                                Text("\(session.start.formatted(date: .omitted, time: .shortened))–\(session.end.formatted(date: .omitted, time: .shortened))")
                                    .monospacedDigit().foregroundStyle(Theme.secondaryText)
                                Text(model.activity(session.activityID)?.name ?? "Área removida")
                                Spacer()
                                Text(DurationFormat.short(session.duration)).font(.caption).foregroundStyle(Theme.secondaryText)
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                            .onTapGesture { editingSession = session }
                        }
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    Button("Dia anterior") { shiftDay(-1) }.buttonStyle(AppActionButtonStyle())
                    Button("Próximo dia") { shiftDay(1) }.buttonStyle(AppActionButtonStyle())
                    Button("Hoje") { day = model.now }.buttonStyle(AppActionButtonStyle()).disabled(model.calendar.isDateInToday(day))
                    Button("Adicionar sessão") { addingSession = true }.buttonStyle(AppActionButtonStyle(primary: true)).disabled(model.activeActivities.isEmpty)
                    Button("Atualizar agenda") { model.refreshCalendar() }.buttonStyle(AppActionButtonStyle())
                    Button("Integrações") { model.route = .settingsSection("Receber compromissos") }.buttonStyle(AppActionButtonStyle())
                }
            }
            .padding(.horizontal, 40).padding(.top, 28).padding(.bottom, 40)
            .frame(maxWidth: 888, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .sheet(isPresented: $addingSession) { SessionEditor(session: nil) }
        .sheet(item: $editingSession) { SessionEditor(session: $0) }
    }

    private func shiftDay(_ amount: Int) {
        day = model.calendar.date(byAdding: .day, value: amount, to: day) ?? day
    }
}

struct EventRow: View {
    let event: CalendarEvent
    let now: Date

    var body: some View {
        let isNow = !event.isAllDay && event.start <= now && now < event.end
        let isPast = !event.isAllDay && event.end <= now
        let minutesUntil = Int(event.start.timeIntervalSince(now) / 60)

        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(timeText)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .fontWeight(isNow ? .semibold : .regular)
                if let location = event.location {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isNow {
                Badge(text: "agora")
            } else if !event.isAllDay, minutesUntil >= 0, minutesUntil <= 60 {
                Badge(text: "em \(minutesUntil) min")
            }
        }
        .opacity(isPast ? 0.5 : 1)
    }

    private var timeText: String {
        if event.isAllDay { return "Dia inteiro" }
        let start = event.start.formatted(date: .omitted, time: .shortened)
        let end = event.end.formatted(date: .omitted, time: .shortened)
        return "\(start)–\(end)"
    }
}

private struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor.opacity(0.2)))
    }
}

struct CalendarSyncStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let agenda = model.agenda
        Group {
            if agenda.isSyncing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Atualizando…")
                }
            } else if let error = agenda.errorMessage {
                Label("Erro", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help(error)
            } else if let lastSync = agenda.lastSync {
                Text("Atualizada \(lastSync.formatted(.relative(presentation: .named)))")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
