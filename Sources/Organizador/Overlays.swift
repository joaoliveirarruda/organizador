import AppKit
import SwiftUI

/// The app's own floating layers, drawn over the main window in place of macOS sheets, menus,
/// pop-up buttons and alerts: cards that block the page, and one list hanging from a control.
@MainActor @Observable
final class Overlays {
    static let shared = Overlays()

    struct Modal: Identifiable {
        let id: UUID
        let content: AnyView
        let close: () -> Void
    }

    struct Popup: Identifiable {
        let id = UUID()
        /// The control it hangs from, in window coordinates with the origin at the top left.
        let anchor: CGRect
        let content: AnyView
    }

    private(set) var modals: [Modal] = []
    private(set) var popup: Popup?

    /// Shows a card. `onClose` runs when the user closes it (Esc, Cancelar, Salvar).
    func present(_ content: AnyView, onClose: @escaping () -> Void) -> UUID {
        let id = UUID()
        popup = nil
        modals.append(Modal(id: id, content: content) { [weak self] in
            onClose()
            self?.dismiss(id)
        })
        return id
    }

    /// Takes a card away without telling its owner, for when the owner is the one asking.
    func dismiss(_ id: UUID) { modals.removeAll { $0.id == id } }

    @discardableResult
    func show(_ content: AnyView, at anchor: CGRect) -> UUID {
        let popup = Popup(anchor: anchor, content: content)
        self.popup = popup
        return popup.id
    }

    func closePopup() { popup = nil }
}

struct CloseAction {
    var run: () -> Void = {}
    func callAsFunction() { run() }
}

extension EnvironmentValues {
    /// Closes the card a view sits in, like `dismiss` does for a sheet.
    @Entry var closeSheet = CloseAction()
}

extension NSView {
    /// A rect of this view in the window's top-left coordinates, the space SwiftUI calls global.
    func globalRect(_ rect: NSRect) -> CGRect {
        let inWindow = convert(rect, to: nil)
        let height = window?.contentView?.bounds.height ?? 0
        return CGRect(x: inWindow.minX, y: height - inWindow.maxY, width: inWindow.width, height: inWindow.height)
    }
}

/// Draws the open cards and the open list. Sits over the whole window.
struct OverlayHost: View {
    @State private var monitor: Any?

    var body: some View {
        let overlays = Overlays.shared
        ZStack(alignment: .topLeading) {
            ForEach(overlays.modals) { modal in
                ZStack {
                    // Swallows clicks so the page under the card stays put.
                    Color.black.opacity(0.5).contentShape(Rectangle()).onTapGesture {}
                    modal.content
                        .environment(\.closeSheet, CloseAction(run: modal.close))
                        .font(Theme.font(size: 13))
                        .foregroundStyle(Theme.text)
                        .buttonStyle(.heading())
                        .textFieldStyle(AppFieldStyle())
                        .toggleStyle(RowToggleStyle())
                        .labeledContentStyle(RowLabeledContentStyle())
                        .scrollContentBackground(.hidden)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.sidebar))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                        .shadow(color: .black.opacity(0.4), radius: 24, y: 8)
                        .padding(24)
                }
                .transition(.opacity)
            }
            if let popup = overlays.popup {
                PopupLayer(popup: popup).id(popup.id)
            }
        }
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.12), value: overlays.modals.map(\.id))
        .onAppear {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 53 else { return event }  // Esc closes the topmost layer
                if overlays.popup != nil {
                    overlays.closePopup()
                    return nil
                }
                if let top = overlays.modals.last {
                    top.close()
                    return nil
                }
                return event
            }
        }
        .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

/// The open list, under its control, or above it when there is no room below.
private struct PopupLayer: View {
    let popup: Overlays.Popup
    @State private var size: CGSize?

    var body: some View {
        GeometryReader { space in
            let bounds = space.frame(in: .global)
            ZStack(alignment: .topLeading) {
                Color.clear.contentShape(Rectangle()).onTapGesture { Overlays.shared.closePopup() }
                popup.content
                    .font(Theme.font(size: 13))
                    .foregroundStyle(Theme.text)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.sidebar))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
                    .fixedSize()
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                    .offset(origin(in: bounds))
                    .opacity(size == nil ? 0 : 1)
            }
        }
    }

    private func origin(in bounds: CGRect) -> CGSize {
        let size = size ?? .zero
        let anchor = popup.anchor.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
        let x = max(8, min(anchor.minX, bounds.width - size.width - 8))
        var y = anchor.maxY + 4
        if y + size.height > bounds.height - 8 { y = max(8, anchor.minY - size.height - 4) }
        return CGSize(width: x, height: y)
    }
}

extension View {
    /// Shows `content` as a card over the window while `isPresented` is true. Replaces `.sheet`.
    func floatingSheet<Sheet: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Sheet) -> some View {
        modifier(FloatingSheet(isPresented: isPresented, sheet: content))
    }

    /// Shows a card for `item` while it is set. Replaces `.sheet(item:)`.
    func floatingSheet<Item: Identifiable, Sheet: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Sheet) -> some View {
        modifier(FloatingItemSheet(item: item, sheet: content))
    }

    /// Asks before doing something, in a small card. Replaces `.confirmationDialog`.
    func appConfirm<Actions: View, Message: View>(
        _ title: String, isPresented: Binding<Bool>, titleVisibility: Visibility = .visible,
        @ViewBuilder actions: @escaping () -> Actions, @ViewBuilder message: @escaping () -> Message
    ) -> some View {
        floatingSheet(isPresented: isPresented) { ConfirmCard(title: title, actions: actions(), message: message()) }
    }

    func appConfirm<Actions: View>(
        _ title: String, isPresented: Binding<Bool>, titleVisibility: Visibility = .visible,
        @ViewBuilder actions: @escaping () -> Actions
    ) -> some View {
        appConfirm(title, isPresented: isPresented, actions: actions) { EmptyView() }
    }

    func appConfirm<T, Actions: View, Message: View>(
        _ title: String, isPresented: Binding<Bool>, titleVisibility: Visibility = .visible, presenting data: T?,
        @ViewBuilder actions: @escaping (T) -> Actions, @ViewBuilder message: @escaping (T) -> Message
    ) -> some View {
        floatingSheet(isPresented: isPresented) {
            if let data { ConfirmCard(title: title, actions: actions(data), message: message(data)) }
        }
    }

    /// Right-click (or Control-click) opens `menu` at the pointer. Replaces `.contextMenu`.
    func appContextMenu<Menu: View>(@ViewBuilder _ menu: @escaping () -> Menu) -> some View {
        overlay(RightClickCatcher { point in
            Overlays.shared.show(AnyView(MenuList(content: menu)), at: CGRect(origin: point, size: .zero))
        })
    }
}

private struct FloatingSheet<Sheet: View>: ViewModifier {
    let isPresented: Binding<Bool>
    let sheet: () -> Sheet
    @State private var shown: UUID?

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented.wrappedValue, initial: true) { _, present in
                if present, shown == nil {
                    shown = Overlays.shared.present(AnyView(sheet())) { isPresented.wrappedValue = false }
                } else if !present, let id = shown {
                    Overlays.shared.dismiss(id)
                    shown = nil
                }
            }
            .onDisappear {
                guard let id = shown else { return }
                Overlays.shared.dismiss(id)
                shown = nil
                isPresented.wrappedValue = false
            }
    }
}

private struct FloatingItemSheet<Item: Identifiable, Sheet: View>: ViewModifier {
    let item: Binding<Item?>
    let sheet: (Item) -> Sheet
    @State private var shown: (item: Item.ID, modal: UUID)?

    func body(content: Content) -> some View {
        content
            .onChange(of: item.wrappedValue?.id, initial: true) { _, id in
                if let current = shown, current.item != id {
                    Overlays.shared.dismiss(current.modal)
                    shown = nil
                }
                if let id, shown == nil, let value = item.wrappedValue {
                    shown = (id, Overlays.shared.present(AnyView(sheet(value))) { item.wrappedValue = nil })
                }
            }
            .onDisappear {
                guard let current = shown else { return }
                Overlays.shared.dismiss(current.modal)
                shown = nil
                item.wrappedValue = nil
            }
    }
}

private struct ConfirmCard<Actions: View, Message: View>: View {
    let title: String
    let actions: Actions
    let message: Message
    @Environment(\.closeSheet) private var close

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.font(size: 15, weight: .semibold))
            message.foregroundStyle(Theme.secondaryText)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancelar") { close() }
                actions.buttonStyle(ConfirmActionStyle())
            }
            .padding(.top, 10)
        }
        .padding(20)
        .frame(width: 360, alignment: .leading)
    }
}

/// A confirmation's own button: does its thing, then closes the card.
private struct ConfirmActionStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View { ConfirmAction(configuration: configuration) }
}

private struct ConfirmAction: View {
    let configuration: PrimitiveButtonStyleConfiguration
    @Environment(\.closeSheet) private var close

    var body: some View {
        Button(role: configuration.role) {
            configuration.trigger()
            close()
        } label: {
            configuration.label
        }
        .buttonStyle(.heading())
    }
}

/// A control that opens `content` in a floating list under itself.
struct PopupButton<Label: View, Content: View>: View {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var label: () -> Label
    @State private var frame = CGRect.zero

    var body: some View {
        Button { Overlays.shared.show(AnyView(content()), at: frame) } label: { label() }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
    }
}

/// A button that opens a list of actions. Replaces `Menu`.
struct PopupMenu<Label: View, Content: View>: View {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var label: () -> Label

    var body: some View {
        PopupButton(content: { MenuList(content: content) }, label: label)
    }
}

extension PopupMenu where Label == Text {
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(content: content) { Text(title) }
    }
}

/// Buttons and dividers stacked like a menu; picking one closes the list.
struct MenuList<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .buttonStyle(MenuItemStyle())
            .labelStyle(MenuItemLabelStyle())
            .frame(minWidth: 180, alignment: .leading)
    }
}

private struct MenuItemStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View { MenuItem(configuration: configuration) }
}

private struct MenuItem: View {
    let configuration: PrimitiveButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button {
            Overlays.shared.closePopup()
            configuration.trigger()
        } label: {
            configuration.label
                .lineLimit(1)
                .foregroundStyle(configuration.role == .destructive ? Theme.danger : Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 5).fill(hovering && isEnabled ? Theme.hover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { hovering = $0 }
    }
}

private struct MenuItemLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.frame(width: 16).foregroundStyle(Theme.secondaryText)
            configuration.title
        }
    }
}

/// An invisible layer that only answers right-clicks and Control-clicks; every other click goes through.
private struct RightClickCatcher: NSViewRepresentable {
    let onClick: (CGPoint) -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }
    func updateNSView(_ view: CatcherView, context: Context) { view.onClick = onClick }

    final class CatcherView: NSView {
        var onClick: (CGPoint) -> Void = { _ in }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            let secondary = event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            return secondary ? super.hitTest(point) : nil
        }

        override func rightMouseDown(with event: NSEvent) { open(event) }
        override func mouseDown(with event: NSEvent) { open(event) }

        private func open(_ event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            onClick(globalRect(NSRect(origin: point, size: .zero)).origin)
        }
    }
}
