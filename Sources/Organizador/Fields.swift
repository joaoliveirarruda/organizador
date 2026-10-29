import SwiftUI

/// One option of a `ChoicePicker`.
struct Choice<Value: Hashable> {
    let value: Value
    let title: String
    var color: Color? = nil
}

/// Picks one of a few values from the app's own floating list. Replaces `Picker`.
struct ChoicePicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let choices: [Choice<Value>]

    init(_ title: String, selection: Binding<Value>, choices: [Choice<Value>]) {
        self.title = title
        _selection = selection
        self.choices = choices
    }

    var body: some View {
        if title.isEmpty {
            button
        } else {
            LabeledContent(title) { button }
        }
    }

    private var button: some View {
        let current = choices.first { $0.value == selection }
        return PopupButton {
            ChoiceList(choices: choices, selection: $selection)
        } label: {
            HStack(spacing: 6) {
                if let color = current?.color { Circle().fill(color).frame(width: 8, height: 8) }
                Text(current?.title ?? "Escolha…").lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            .fieldChrome()
        }
        .buttonStyle(.plain)
    }
}

private struct ChoiceList<Value: Hashable>: View {
    let choices: [Choice<Value>]
    @Binding var selection: Value

    var body: some View {
        let list = MenuList {
            ForEach(choices.indices, id: \.self) { index in
                let choice = choices[index]
                Button { selection = choice.value } label: {
                    HStack(spacing: 8) {
                        if let color = choice.color { Circle().fill(color).frame(width: 8, height: 8) }
                        Text(choice.title)
                        Spacer(minLength: 16)
                        if choice.value == selection {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                        }
                    }
                }
            }
        }
        if choices.count > 10 {
            ScrollView { list }.frame(height: 300)
        } else {
            list
        }
    }
}

/// A date (and time) that opens a small calendar. Replaces `DatePicker`.
struct DateField: View {
    let title: String
    @Binding var selection: Date
    let withTime: Bool

    init(_ title: String, selection: Binding<Date>, displayedComponents: DatePickerComponents = [.date, .hourAndMinute]) {
        self.title = title
        _selection = selection
        withTime = displayedComponents.contains(.hourAndMinute)
    }

    var body: some View {
        LabeledContent(title) {
            PopupButton {
                CalendarPanel(date: $selection, withTime: withTime)
            } label: {
                Text(selection.formatted(date: .abbreviated, time: withTime ? .shortened : .omitted)).fieldChrome()
            }
            .buttonStyle(.plain)
        }
    }
}

private struct CalendarPanel: View {
    @Binding var date: Date
    let withTime: Bool
    @State private var month: Date
    @State private var time: String
    private let calendar = Calendar.current

    init(date: Binding<Date>, withTime: Bool) {
        _date = date
        self.withTime = withTime
        _month = State(initialValue: Calendar.current.dateInterval(of: .month, for: date.wrappedValue)?.start ?? date.wrappedValue)
        _time = State(initialValue: Self.clock.string(from: date.wrappedValue))
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year()).capitalizedFirst)
                    .font(Theme.font(size: 13, weight: .semibold))
                Spacer()
                arrow("chevron.left", -1)
                arrow("chevron.right", 1)
            }
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    ForEach(weekdays.indices, id: \.self) { index in
                        Text(weekdays[index]).font(Theme.font(size: 11)).foregroundStyle(Theme.secondaryText).frame(width: 28)
                    }
                }
                ForEach(weeks.indices, id: \.self) { week in
                    GridRow {
                        ForEach(0..<7, id: \.self) { column in dayCell(weeks[week][column]) }
                    }
                }
            }
            HStack {
                Button("Hoje") { pick(Date()) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                if withTime {
                    TextField("00:00", text: $time)
                        .textFieldStyle(.plain)
                        .frame(width: 44)
                        .fieldChrome()
                        .onChange(of: time) { applyTime() }
                }
            }
        }
        .padding(6)
    }

    private func arrow(_ symbol: String, _ months: Int) -> some View {
        Button {
            month = calendar.date(byAdding: .month, value: months, to: month) ?? month
        } label: {
            Image(systemName: symbol).frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Short weekday names starting on the calendar's first day of the week.
    private var weekdays: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// The shown month as rows of seven, with blanks before the 1st and after the last day.
    private var weeks: [[Date?]] {
        let days = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let lead = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: lead)
        cells += (0..<days).map { calendar.date(byAdding: .day, value: $0, to: month) }
        cells += Array(repeating: nil, count: (7 - cells.count % 7) % 7)
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    @ViewBuilder
    private func dayCell(_ day: Date?) -> some View {
        if let day {
            let selected = calendar.isDate(day, inSameDayAs: date)
            Button { pick(day) } label: {
                Text("\(calendar.component(.day, from: day))")
                    .font(Theme.font(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.onAccent : Theme.text)
                    .frame(width: 28, height: 24)
                    .background(RoundedRectangle(cornerRadius: 5).fill(selected ? Theme.accent : .clear))
                    .overlay {
                        if calendar.isDateInToday(day), !selected { RoundedRectangle(cornerRadius: 5).stroke(Theme.border) }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(width: 28, height: 24)
        }
    }

    /// Moves to `day`, keeping the time of day.
    private func pick(_ day: Date) {
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        let clock = calendar.dateComponents([.hour, .minute], from: date)
        parts.hour = clock.hour
        parts.minute = clock.minute
        date = calendar.date(from: parts) ?? day
        month = calendar.dateInterval(of: .month, for: date)?.start ?? month
        if !withTime { Overlays.shared.closePopup() }
    }

    private func applyTime() {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return }
        date = calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: date) ?? date
    }
}

/// "Label  − +": nudges a whole number up and down. Replaces `Stepper`.
struct NumberStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1

    init(_ title: String, value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 0) {
                button("minus", -step).disabled(value <= range.lowerBound)
                Rectangle().fill(Theme.border).frame(width: 1, height: 14)
                button("plus", step).disabled(value >= range.upperBound)
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.hover))
        }
    }

    private func button(_ symbol: String, _ delta: Int) -> some View {
        Button {
            value = min(max(value + delta, range.lowerBound), range.upperBound)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A titled group of rows inside a card.
struct FormSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(Theme.font(size: 11, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 10)
            content
        }
    }
}

/// A switch drawn by the app, with its label on the left and the switch at the far right.
struct RowToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 12) {
                configuration.label
                Spacer(minLength: 0)
                Capsule()
                    .fill(configuration.isOn ? Theme.accent : Theme.border)
                    .frame(width: 30, height: 18)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(configuration.isOn ? Theme.onAccent : Theme.text).padding(3)
                    }
                    .animation(.easeOut(duration: 0.12), value: configuration.isOn)
            }
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Label on the left, value on the right, like a Notion property.
struct RowLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label.foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 0)
            configuration.content
        }
        .frame(minHeight: 28)
    }
}

struct AppFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.hover))
    }
}

extension View {
    /// The rounded box around a field's value.
    func fieldChrome() -> some View {
        padding(.horizontal, 8)
            .frame(minHeight: 26)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.hover))
            .contentShape(Rectangle())
    }
}
