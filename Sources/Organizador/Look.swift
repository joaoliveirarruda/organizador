import AppKit
import OrganizadorCore
import SwiftUI
import UniformTypeIdentifiers

/// Notion-like neutral palette that follows the system's light and dark mode.
enum Theme {
    static let page = dynamic(light: 0xFFFFFF, dark: 0x191919)
    static let sidebar = dynamic(light: 0xF7F7F5, dark: 0x202020)
    static let hover = dynamic(light: 0xEBEBEA, dark: 0x2C2C2C)
    static let text = dynamic(light: 0x37352F, dark: 0xE6E6E5)
    static let secondaryText = dynamic(light: 0x787774, dark: 0x9B9B9B)
    static let border = dynamic(light: 0xE9E9E7, dark: 0x2F2F2F)
    static let card = dynamic(light: 0xFBFBFA, dark: 0x202020)
    static let accent = Color(nsColor: NSColor(srgbRed: 0x23 / 255, green: 0x83 / 255, blue: 0xE2 / 255, alpha: 1))

    private static func dynamic(light: Int, dark: Int) -> Color {
        func color(_ hex: Int) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                     blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? color(dark) : color(light)
        })
    }
}

/// Copies pictures the user picks into a folder the app owns, so deleting the original breaks nothing.
enum ImageFiles {
    /// Asks for an image and copies it into `folder`. Returns the copy's path relative to `relativeTo`.
    @MainActor
    static func pick(into folder: URL, relativeTo base: URL) -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.prompt = "Usar esta foto"
        guard panel.runModal() == .OK, let source = panel.url else { return nil }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = UUID().uuidString.prefix(8) + "." + (source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased())
            let target = folder.appendingPathComponent(String(name))
            try FileManager.default.copyItem(at: source, to: target)
            return String(target.path.dropFirst(base.standardizedFileURL.path.count + 1))
        } catch {
            return nil
        }
    }

    static func image(_ path: String, in base: URL) -> NSImage? {
        NSImage(contentsOf: base.appendingPathComponent(path))
    }
}

/// An emoji or a small photo; falls back to an SF Symbol.
struct IconView: View {
    let icon: Icon?
    /// Folder that image icons are relative to.
    let base: URL
    var fallback = "doc.text"
    var size: CGFloat = 16

    var body: some View {
        switch icon {
        case .emoji(let emoji):
            Text(emoji).font(.system(size: size * 0.95))
                .frame(width: size, height: size)
        case .image(let path):
            if let image = ImageFiles.image(path, in: base) {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else {
                symbol
            }
        case nil:
            symbol
        }
    }

    private var symbol: some View {
        Image(systemName: fallback)
            .font(.system(size: size * 0.8))
            .foregroundStyle(Theme.secondaryText)
            .frame(width: size, height: size)
    }
}

/// The top of an opened page: cover strip, large icon and the controls to change both.
/// Covers only ever appear here, never in lists or the sidebar.
struct PageHeader<Title: View>: View {
    let icon: Icon?
    let cover: String?
    let base: URL
    var fallback = "doc.text"
    /// Where picked pictures are copied to.
    let imagesFolder: URL
    let setIcon: (Icon?) -> Void
    let setCover: (String?) -> Void
    @ViewBuilder let title: Title
    @State private var hovering = false
    @State private var editingEmoji = false
    @State private var emoji = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let cover, let image = ImageFiles.image(cover, in: base) {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 180)
                    .clipped()
                    .overlay(alignment: .bottomTrailing) {
                        if hovering {
                            HStack {
                                Button("Trocar capa") { pickCover() }
                                Button("Remover") { setCover(nil) }
                            }
                            .controlSize(.small)
                            .padding(10)
                        }
                    }
            }
            VStack(alignment: .leading, spacing: 8) {
                if icon != nil {
                    Menu {
                        iconMenu
                    } label: {
                        IconView(icon: icon, base: base, fallback: fallback, size: 64)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .offset(y: cover == nil ? 0 : -32)
                    .padding(.bottom, cover == nil ? 0 : -32)
                }
                HStack(spacing: 12) {
                    if icon == nil {
                        Menu("Adicionar ícone") { iconMenu }
                            .menuStyle(.borderlessButton).fixedSize()
                    }
                    if cover == nil {
                        Button("Adicionar capa") { pickCover() }
                            .buttonStyle(.borderless)
                    }
                }
                .font(.callout)
                .foregroundStyle(Theme.secondaryText)
                .opacity(hovering ? 1 : 0)
                title
            }
            .padding(.horizontal, 48)
            .padding(.top, cover == nil ? 32 : 12)
        }
        .onHover { hovering = $0 }
        .popover(isPresented: $editingEmoji) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Emoji", text: $emoji)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .onSubmit(commitEmoji)
                Text("⌃⌘Espaço abre os emojis do Mac.").font(.caption).foregroundStyle(.secondary)
                Button("Usar") { commitEmoji() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var iconMenu: some View {
        Button("Emoji…") {
            if case .emoji(let current) = icon { emoji = current } else { emoji = "" }
            editingEmoji = true
        }
        Button("Foto…") {
            if let path = ImageFiles.pick(into: imagesFolder, relativeTo: base) { setIcon(.image(path)) }
        }
        if icon != nil {
            Divider()
            Button("Remover ícone") { setIcon(nil) }
        }
    }

    private func commitEmoji() {
        let text = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        setIcon(text.isEmpty ? nil : .emoji(String(text.prefix(2))))
        editingEmoji = false
    }

    private func pickCover() {
        if let path = ImageFiles.pick(into: imagesFolder, relativeTo: base) { setCover(path) }
    }
}

/// A titled block on a page.
struct PageSection<Content: View, Accessory: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                Spacer()
                accessory
            }
            content
        }
    }
}

extension PageSection where Accessory == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, content: content, accessory: { EmptyView() })
    }
}

/// Days until the deadline: "D-12", "D-dia", "D+3".
func dDay(_ deadline: Date, now: Date, calendar: Calendar) -> String {
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: deadline)).day ?? 0
    return days == 0 ? "D-dia" : days > 0 ? "D-\(days)" : "D+\(-days)"
}
