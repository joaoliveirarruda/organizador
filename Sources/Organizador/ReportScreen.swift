import OrganizadorCore
import ShadcnUI
import SwiftUI

/// Time per area, and per activity inside each, for the chosen period. Read-only.
struct ReportScreen: View {
    @Environment(AppModel.self) private var model
    @State private var period: ReportPeriod = .week
    @State private var expanded: UUID??

    var body: some View {
        let report = model.report(period)
        let total = report.areas.reduce(0) { $0 + $1.seconds }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom) {
                    ScreenHeading(
                        section: "Tempo",
                        title: "Relatório",
                        subtitle: report.interval.map { "\(label($0)) · \(DurationFormat.compact(total))" } ?? "Nenhum tempo registrado ainda"
                    )
                    Spacer()
                    SegmentedTabs(options: ReportPeriod.allCases.map { ($0, $0.rawValue) }, selection: $period)
                }

                VStack(alignment: .leading, spacing: 2) {
                    if report.areas.isEmpty {
                        Text("Nenhum tempo registrado neste período.")
                            .font(Theme.font(size: 13))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(12)
                    }
                    ForEach(report.areas, id: \.area?.id) { row in
                        AreaTimeRow(
                            row: row,
                            share: total > 0 ? row.seconds / total : 0,
                            isExpanded: expanded == .some(row.area?.id),
                            toggle: {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    expanded = expanded == .some(row.area?.id) ? nil : .some(row.area?.id)
                                }
                            }
                        )
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardChrome()
            }
            .padding(.horizontal, 40).padding(.top, 28).padding(.bottom, 40)
            .pageColumn()
        }
        .toolbar { ToolbarItem(placement: .principal) { TimeTabs() } }
    }

    private static let months = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"]

    /// "27 out – 2 nov", "1 – 31 out", "2026", "Desde mar 2025".
    private func label(_ interval: DateInterval) -> String {
        let calendar = model.calendar
        let first = calendar.dateComponents([.day, .month, .year], from: interval.start)
        let last = calendar.dateComponents([.day, .month, .year], from: interval.end.addingTimeInterval(-1))
        let month = { (parts: DateComponents) in Self.months[(parts.month ?? 1) - 1] }
        switch period {
        case .year: return "\(first.year ?? 0)"
        case .total: return "Desde \(month(first)) \(first.year ?? 0)"
        case .week, .month:
            return first.month == last.month
                ? "\(first.day ?? 1) – \(last.day ?? 1) \(month(last))"
                : "\(first.day ?? 1) \(month(first)) – \(last.day ?? 1) \(month(last))"
        }
    }
}

/// One area: written name, hours and a bar in its color; click to see its activities.
private struct AreaTimeRow: View {
    let row: TimeReport.AreaTotal
    let share: Double
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        let color = row.area.map { Color(hex: $0.colorHex) } ?? Theme.secondaryText
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 13)
                        Circle().fill(color).frame(width: 10, height: 10)
                        Text(row.area?.name ?? "Sem área")
                            .font(Theme.font(size: 15, weight: .medium))
                            .foregroundStyle(row.area == nil ? Theme.secondaryText : Theme.text)
                        Spacer()
                        Text(DurationFormat.compact(row.seconds))
                            .font(Theme.font(size: 15, weight: .medium))
                            .monospacedDigit()
                    }
                    Bar(value: share, color: color, height: 6, track: Theme.border)
                        .padding(.leading, 39)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(row.activities, id: \.activity.id) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(item.activity.name).font(Theme.font(size: 13))
                                Spacer()
                                Text(DurationFormat.compact(item.seconds))
                                    .font(Theme.font(size: 13))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            Bar(value: row.seconds > 0 ? item.seconds / row.seconds : 0, color: color, height: 3, track: Theme.border)
                        }
                        .padding(.vertical, 7)
                        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
                    }
                }
                .padding(.leading, 51).padding(.trailing, 12).padding(.bottom, 10)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(isExpanded ? Theme.hover : .clear))
    }
}

/// A thin rounded bar filled to `value` (0…1).
private struct Bar: View {
    let value: Double
    let color: Color
    let height: CGFloat
    let track: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(color).frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: height)
    }
}
