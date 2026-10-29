import OrganizadorCore
import SwiftUI

/// Name and color of a big area, like "Universidade".
struct AreaEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.closeSheet) private var dismiss
    let area: Area?
    var onSave: ((Area) -> Void)?
    @State private var name: String
    @State private var colorHex: String

    init(area: Area?, onSave: ((Area) -> Void)? = nil) {
        self.area = area
        self.onSave = onSave
        _name = State(initialValue: area?.name ?? "")
        _colorHex = State(initialValue: area?.colorHex ?? Palette.colors[3])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(area == nil ? "Nova área" : "Editar área").font(Theme.font(size: 16, weight: .semibold))
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
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        let saved: Area
        if var area {
            area.name = trimmedName
            area.colorHex = colorHex
            model.updateArea(area)
            saved = area
        } else {
            saved = model.addArea(name: trimmedName, colorHex: colorHex)
        }
        onSave?(saved)
        dismiss()
    }
}

/// The areas list in Ajustes: create, edit and delete.
struct AreaSettings: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Area?
    @State private var adding = false
    @State private var deleting: Area?

    var body: some View {
        SettingGroup {
            if model.areas.isEmpty {
                SettingRow("Nenhuma área ainda", detail: "Crie uma para agrupar atividades, como Universidade ou Trabalho.") { EmptyView() }
            }
            ForEach(model.areas) { area in
                SettingRow(area.name, detail: activityCount(area), dot: Color(hex: area.colorHex)) {
                    Button("Editar") { editing = area }
                    Button("Apagar", role: .destructive) { deleting = area }
                }
            }
        } footnote: {
            // Sheets hang off this one button so each opens once, not once per row.
            Button("Nova área") { adding = true }
                .buttonStyle(.heading(primary: true))
                .padding(.top, 8)
                .floatingSheet(isPresented: $adding) { AreaEditor(area: nil) }
                .floatingSheet(item: $editing) { AreaEditor(area: $0) }
                .appConfirm(
                    deleting.map { "Apagar \($0.name)?" } ?? "",
                    isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                    titleVisibility: .visible,
                    presenting: deleting
                ) { area in
                    Button("Apagar \(area.name)", role: .destructive) {
                        model.deleteArea(area.id)
                        deleting = nil
                    }
                } message: { _ in
                    Text("As atividades ficam sem área. O tempo registrado não muda.")
                }
        }
    }

    private func activityCount(_ area: Area) -> String {
        let count = model.activeActivities.filter { $0.areaID == area.id }.count
        return count == 1 ? "1 atividade" : "\(count) atividades"
    }
}
