import Charts
import OrganizadorCore
import SwiftUI

struct StatsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var days = 7

    var body: some View {
        let rows = model.dailyTotals(days: days)
        let totals = model.totalsByActivity(lastDays: days)
        let maxSeconds = totals.first?.seconds ?? 1

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Picker("Período", selection: $days) {
                    Text("7 dias").tag(7)
                    Text("30 dias").tag(30)
                }
                .pickerStyle(.segmented)
                .frame(width: 240)

                if rows.isEmpty {
                    ContentUnavailableView(
                        "Sem tempo registrado",
                        systemImage: "chart.bar",
                        description: Text("Use o cronômetro e o seu tempo aparece aqui.")
                    )
                } else {
                    Chart(rows) { row in
                        BarMark(
                            x: .value("Dia", row.day, unit: .day),
                            y: .value("Horas", row.seconds / 3600)
                        )
                        .foregroundStyle(by: .value("Atividade", label(for: row.activityID)))
                    }
                    .chartForegroundStyleScale(
                        domain: totals.map { label(for: $0.activity.id) },
                        range: totals.map { Color(hex: $0.activity.colorHex) }
                    )
                    .chartYAxisLabel("horas")
                    .frame(height: 260)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Total por atividade").font(.headline)
                        ForEach(totals, id: \.activity.id) { item in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color(hex: item.activity.colorHex))
                                    .frame(width: 10, height: 10)
                                Text(item.activity.name)
                                    .frame(width: 140, alignment: .leading)
                                ProgressView(value: item.seconds / maxSeconds)
                                    .tint(Color(hex: item.activity.colorHex))
                                Text(DurationFormat.short(item.seconds))
                                    .monospacedDigit()
                                    .frame(width: 80, alignment: .trailing)
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .navigationTitle("Estatísticas")
    }

    /// Chart series need unique labels, so repeated names get a suffix.
    private func label(for activityID: UUID) -> String {
        guard let activity = model.activity(activityID) else { return "?" }
        let sameName = model.data.activities.filter { $0.name == activity.name }
        guard sameName.count > 1, let index = sameName.firstIndex(where: { $0.id == activityID }) else {
            return activity.name
        }
        return "\(activity.name) (\(index + 1))"
    }
}
