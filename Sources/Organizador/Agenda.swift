import OrganizadorCore
import SwiftUI

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
