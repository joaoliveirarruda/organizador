import OrganizadorCore
import SwiftUI

/// Meetings for the next 7 days.
struct AgendaScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let calendar = model.calendar
        let today = calendar.startOfDay(for: model.now)
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        let end = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        let events = model.agenda.occurrences(in: DateInterval(start: today, end: end))

        Group {
            if !model.hasCalendar {
                CalendarSetupPrompt()
            } else {
                List {
                    ForEach(days, id: \.self) { day in
                        let interval = Stats.day(containing: day, calendar: calendar)
                        let dayEvents = events.filter { $0.start < interval.end && $0.end > interval.start }
                        Section(dayTitle(day, today: today)) {
                            if dayEvents.isEmpty {
                                Text("Nada marcado").foregroundStyle(.secondary)
                            }
                            ForEach(dayEvents) { event in
                                EventRow(event: event, now: model.now)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Agenda")
        .toolbar {
            ToolbarItem {
                Button {
                    model.refreshCalendar()
                } label: {
                    Label("Atualizar", systemImage: "arrow.clockwise")
                }
                .disabled(!model.hasCalendar || model.agenda.isSyncing)
            }
            ToolbarItem {
                CalendarSyncStatus()
            }
        }
    }

    private func dayTitle(_ day: Date, today: Date) -> String {
        let formatted = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        if day == today { return "Hoje · \(formatted)" }
        if model.calendar.date(byAdding: .day, value: 1, to: today) == day { return "Amanhã · \(formatted)" }
        return formatted
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

struct CalendarSetupPrompt: View {
    var body: some View {
        ContentUnavailableView {
            Label("Conecte sua agenda", systemImage: "calendar.badge.plus")
        } description: {
            Text("Cole nos Ajustes o \"endereço secreto no formato iCal\" do Google Agenda para ver suas reuniões aqui.")
        } actions: {
            SettingsLink {
                Text("Abrir Ajustes")
            }
        }
    }
}
