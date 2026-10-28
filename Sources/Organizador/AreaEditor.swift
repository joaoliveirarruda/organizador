import OrganizadorCore
import SwiftUI

/// Name and color of a big area, like "Universidade".
struct AreaEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
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
            Text(area == nil ? "Nova área" : "Editar área").font(.headline)
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
        Section("Áreas") {
            if model.areas.isEmpty {
                Text("Nenhuma área ainda.").foregroundStyle(Theme.secondaryText)
            }
            ForEach(model.areas) { area in
                Button { editing = area } label: {
                    HStack(spacing: 8) {
                        Circle().fill(Color(hex: area.colorHex)).frame(width: 10, height: 10)
                        Text(area.name).foregroundStyle(Theme.text)
                        Spacer()
                        Text(activityCount(area)).foregroundStyle(Theme.secondaryText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Editar") { editing = area }
                    Button("Apagar", role: .destructive) { deleting = area }
                }
            }
            Button("Nova área") { adding = true }
        }
        .sheet(isPresented: $adding) { AreaEditor(area: nil) }
        .sheet(item: $editing) { AreaEditor(area: $0) }
        .confirmationDialog(
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

    private func activityCount(_ area: Area) -> String {
        let count = model.activeActivities.filter { $0.areaID == area.id }.count
        return count == 1 ? "1 atividade" : "\(count) atividades"
    }
}
