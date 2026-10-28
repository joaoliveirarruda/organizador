import AppKit
import OrganizadorCore
import SwiftUI
import UniformTypeIdentifiers

/// Notion-like neutral palette that follows the system's light and dark mode.
enum Theme {
    static let page = Color(hex: "111417")
    static let sidebar = Color(hex: "191d20")
    static let hover = Color(hex: "252b2d")
    static let text = Color(hex: "f0f2ef")
    static let secondaryText = Color(hex: "a2adaa")
    static let border = Color(hex: "303638")
    static let card = Color(hex: "1d2225")
    static let accent = Color(hex: "b8e2ca")
    static let onAccent = Color(hex: "17352a")

    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Inter", size: size).weight(weight)
    }

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
            Text(emoji).font(Theme.font(size: size * 0.95))
                .frame(width: size, height: size)
        case .image(let path):
            if let image = ImageFiles.image(path, in: base) {
                Image(nsImage: thumbnail(image))
                    .frame(width: size, height: size)
            } else {
                symbol
            }
        case nil:
            symbol
        }
    }

    /// The photo already cropped and rounded at icon size. Menu labels (the page header) draw
    /// an NSImage at its own size and ignore SwiftUI frames, so the picture must be small itself.
    private func thumbnail(_ image: NSImage) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: size * 0.2, yRadius: size * 0.2).addClip()
            let scale = max(rect.width / image.size.width, rect.height / image.size.height)
            let width = image.size.width * scale, height = image.size.height * scale
            image.draw(in: NSRect(x: (rect.width - width) / 2, y: (rect.height - height) / 2, width: width, height: height))
            return true
        }
    }

    private var symbol: some View {
        Image(systemName: fallback)
            .font(Theme.font(size: size * 0.8))
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
    @FocusState private var emojiFocused: Bool

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
                    .popover(isPresented: $editingEmoji, arrowEdge: .bottom) { emojiPicker }
                    .offset(y: cover == nil ? 0 : -32)
                    .padding(.bottom, cover == nil ? 0 : -32)
                }
                HStack(spacing: 12) {
                    if icon == nil {
                        Menu("Adicionar ícone") { iconMenu }
                            .menuStyle(.borderlessButton).fixedSize()
                            .popover(isPresented: $editingEmoji, arrowEdge: .bottom) { emojiPicker }
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
            .padding(.horizontal, 40)
            .padding(.top, cover == nil ? 32 : 12)
        }
        .onHover { hovering = $0 }
    }

    /// A field that opens the Mac emoji picker right away; picking one sets it as the icon.
    private var emojiPicker: some View {
        TextField("Emoji", text: $emoji)
            .textFieldStyle(.roundedBorder)
            .frame(width: 120)
            .focused($emojiFocused)
            .onSubmit(commitEmoji)
            .onChange(of: emoji) { if !emoji.isEmpty { commitEmoji() } }
            .padding(12)
            .onAppear {
                emojiFocused = true
                // The picker types into whatever has focus, so wait for the field to take it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { NSApp.orderFrontCharacterPalette(nil) }
            }
    }

    @ViewBuilder
    private var iconMenu: some View {
        Button("Emoji…") {
            emoji = ""
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
            // An empty title drops the header row, for cards that need no name.
            if !title.isEmpty {
                HStack {
                    Text(title).font(Theme.font(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                    Spacer()
                    accessory
                }
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
    }
}

/// A screen's title, with its actions (navigation, the main button) on the right.
struct ScreenHeading<Accessory: View>: View {
    let section: String
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                // The small label only helps when the title says something else, like "Tarefas / Hoje".
                if section.localizedCaseInsensitiveCompare(title) != .orderedSame {
                    Text(section.uppercased())
                        .font(Theme.font(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                Text(title)
                    .font(Theme.font(size: 28, weight: .bold))
                    .foregroundStyle(Theme.text)
                if let subtitle {
                    Text(subtitle).font(Theme.font(size: 14)).foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) { accessory }
        }
    }
}

extension ScreenHeading where Accessory == EmptyView {
    init(section: String, title: String, subtitle: String? = nil) {
        self.init(section: section, title: title, subtitle: subtitle, accessory: { EmptyView() })
    }
}

struct AppActionButtonStyle: ButtonStyle {
    var primary = false
    /// Fixed width for the big buttons; nil hugs the label, for actions in a heading.
    var width: CGFloat? = 260

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(size: 13, weight: .medium))
            .foregroundStyle(primary ? Theme.onAccent : Theme.text)
            .frame(width: width, height: width == nil ? 30 : 44)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(primary ? Theme.accent : Theme.hover)
                    .opacity(configuration.isPressed ? 0.78 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

extension ButtonStyle where Self == AppActionButtonStyle {
    /// A compact button for a screen's heading or a card's header.
    static func heading(primary: Bool = false) -> AppActionButtonStyle {
        AppActionButtonStyle(primary: primary, width: nil)
    }
}

/// "‹ Hoje ›": steps a day or month back and forth, and jumps back to the current one.
struct PeriodStepper: View {
    let currentTitle: String
    let isCurrent: Bool
    let step: (Int) -> Void
    let reset: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            arrow("Anterior", "chevron.left") { step(-1) }
            Button(action: reset) {
                Text(currentTitle).padding(.horizontal, 6).frame(height: 30).contentShape(Rectangle())
            }
            .disabled(isCurrent)
            arrow("Próximo", "chevron.right") { step(1) }
        }
        .buttonStyle(.plain)
        .font(Theme.font(size: 13, weight: .medium))
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.hover))
    }

    /// The whole 30×30 square is clickable, not just the chevron.
    private func arrow(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 30, height: 30).contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .help(title)
    }
}

/// A choice between a few views, in the app's own look: same height, colors and corners as the heading buttons.
struct SegmentedTabs<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let selected = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.title)
                        .font(Theme.font(size: 13, weight: .medium))
                        .foregroundStyle(selected ? Theme.text : Theme.secondaryText)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Theme.border : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.hover))
        .accessibilityElement(children: .contain)
    }
}

extension String {
    /// "Quarta-feira, 28 de outubro": only the first letter goes up, unlike `capitalized`.
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
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
