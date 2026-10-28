import OrganizadorCore
import SwiftUI

struct TimerScreen: View {
    @Environment(AppModel.self) private var model
    @State private var showingNewActivity = false
    @State private var editingActivity: Activity?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TodaySummary()

                if let notice = model.pauseNotice {
                    HStack {
                        Image(systemName: "pause.circle")
                        Text(notice)
                        Spacer()
                        Button("OK") { model.pauseNotice = nil }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.yellow.opacity(0.15)))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Linha do tempo de hoje").font(.headline)
                    DayTimeline(segments: model.todayTimeline) { id in
                        Color(hex: model.activity(id)?.colorHex ?? "")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Atividades").font(.headline)
                    if model.activeActivities.isEmpty {
                        Text("Crie uma atividade para começar a cronometrar.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.activeActivities) { activity in
                        ActivityToggleRow(activity: activity)
                            .contextMenu {
                                Button("Editar") { editingActivity = activity }
                                Button("Arquivar", role: .destructive) { model.archiveActivity(activity.id) }
                            }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .navigationTitle("Cronômetro")
        .toolbar {
            ToolbarItem {
                Button {
                    showingNewActivity = true
                } label: {
                    Label("Nova atividade", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewActivity) {
            ActivityEditor(activity: nil)
        }
        .sheet(item: $editingActivity) { activity in
            ActivityEditor(activity: activity)
        }
    }
}

struct TodaySummary: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let total = model.todayTotal
        let target = model.dailyTarget
        VStack(alignment: .leading, spacing: 8) {
            Text("Hoje").font(.headline).foregroundStyle(.secondary)
            Text(DurationFormat.clock(total))
                .font(.system(size: 48, weight: .semibold, design: .rounded))
                .monospacedDigit()
            if let activity = model.runningActivity {
                Label("\(activity.name) · \(DurationFormat.clock(model.currentElapsed))", systemImage: "record.circle")
                    .foregroundStyle(Color(hex: activity.colorHex))
            }
            if target > 0 {
                ProgressView(value: min(1, total / target))
                Text(total >= target
                    ? "Meta diária de \(DurationFormat.short(target)) batida"
                    : "Meta diária \(DurationFormat.short(target)) · faltam \(DurationFormat.short(target - total))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
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

/// A 24-hour bar with a colored block for each span of timed work.
struct DayTimeline: View {
    let segments: [Stats.TimelineSegment]
    /// Meetings drawn as a thin bar above the timed work, as fractions of the day.
    var meetings: [ClosedRange<Double>] = []
    let color: (UUID) -> Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !meetings.isEmpty {
                GeometryReader { geometry in
                    let width = geometry.size.width
                    ZStack(alignment: .leading) {
                        ForEach(meetings, id: \.self) { meeting in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.accentColor.opacity(0.7))
                                .frame(width: max(2, width * (meeting.upperBound - meeting.lowerBound)))
                                .offset(x: width * meeting.lowerBound)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 8)
                .help("Reuniões da agenda")
            }
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.secondary.opacity(0.12))
                    ForEach(segments, id: \.self) { segment in
                        Rectangle()
                            .fill(color(segment.activityID))
                            .frame(width: max(1, width * (segment.endFraction - segment.startFraction)))
                            .offset(x: width * segment.startFraction)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(height: 28)

            HStack {
                ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                    Text("\(hour)h")
                    if hour != 24 { Spacer() }
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

struct ActivityEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let activity: Activity?
    @State private var name: String
    @State private var colorHex: String
    @State private var goalID: UUID?

    init(activity: Activity?) {
        self.activity = activity
        _name = State(initialValue: activity?.name ?? "")
        _colorHex = State(initialValue: activity?.colorHex ?? Palette.colors[3])
        _goalID = State(initialValue: activity?.goalID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(activity == nil ? "Nova atividade" : "Editar atividade").font(.headline)
            TextField("Nome", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                ForEach(Palette.colors, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(Color.primary, lineWidth: hex == colorHex ? 2 : 0))
                        .onTapGesture { colorHex = hex }
                }
            }
            Picker("Conta para a meta", selection: $goalID) {
                Text("Nenhuma").tag(UUID?.none)
                ForEach(model.sortedGoals) { goal in
                    Text(goal.title).tag(Optional(goal.id))
                }
            }
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Salvar") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        if var activity {
            activity.name = trimmedName
            activity.colorHex = colorHex
            activity.goalID = goalID
            model.updateActivity(activity)
        } else {
            model.addActivity(name: trimmedName, colorHex: colorHex, goalID: goalID)
        }
        dismiss()
    }
}
