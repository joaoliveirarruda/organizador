import AppKit
import OrganizadorCore
import SwiftUI

/// Turns `MarkdownSpans` into text attributes. Shared by the editor and the PDF export.
enum MarkdownStyle {
    static let bodySize: CGFloat = 15
    /// Link values the editor handles itself; real `[text](url)` links carry a `URL` instead.
    static let checkboxLink = "organizador:checkbox"
    static let notePrefix = "organizador:note:"

    static var baseAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 4
        return [.font: NSFont.systemFont(ofSize: bodySize), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
    }

    /// Restyles all of `text`. Markers are dimmed in the editor; `forPrint` leaves them for the caller to remove.
    static func apply(_ spans: [MarkdownSpan], to text: NSMutableAttributedString, forPrint: Bool = false) {
        let all = NSRange(location: 0, length: text.length)
        text.setAttributes(baseAttributes, range: all)
        let mono = NSFont.monospacedSystemFont(ofSize: bodySize - 2, weight: .regular)

        for span in spans {
            let range = span.range
            switch span.kind {
            case .heading(let level):
                let sizes: [CGFloat] = [28, 22, 18]
                let size = level <= sizes.count ? sizes[level - 1] : bodySize
                text.addAttribute(.font, value: NSFont.systemFont(ofSize: size, weight: .bold), range: range)
                let paragraph = NSMutableParagraphStyle()
                paragraph.paragraphSpacingBefore = level == 1 ? 12 : 8
                paragraph.paragraphSpacing = 4
                text.addAttribute(.paragraphStyle, value: paragraph, range: range)
            case .bold:
                addTrait(.boldFontMask, to: text, in: range)
            case .italic:
                addTrait(.italicFontMask, to: text, in: range)
            case .strikethrough:
                text.addAttributes([
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: NSColor.secondaryLabelColor,
                ], range: range)
            case .code, .codeBlock:
                text.addAttributes([.font: mono, .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.12)], range: range)
            case .highlight:
                text.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.35), range: range)
            case .callout:
                let paragraph = NSMutableParagraphStyle()
                paragraph.firstLineHeadIndent = 12
                paragraph.headIndent = 12
                text.addAttributes([
                    .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.12), .paragraphStyle: paragraph,
                ], range: range)
            case .table:
                // The editor draws a `TableGrid` over these lines; the PDF swaps them for an `NSTextTable`.
                guard !forPrint else { break }
                let paragraph = NSMutableParagraphStyle()
                paragraph.minimumLineHeight = TableGrid.rowHeight
                paragraph.maximumLineHeight = TableGrid.rowHeight
                paragraph.lineBreakMode = .byClipping
                text.addAttributes([.foregroundColor: NSColor.clear, .paragraphStyle: paragraph], range: range)
            case .quote:
                let paragraph = NSMutableParagraphStyle()
                paragraph.firstLineHeadIndent = 12
                paragraph.headIndent = 12
                text.addAttributes([.foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph], range: range)
            case .rule:
                text.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
            case .listItem:
                text.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
            case .checkbox:
                text.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: range)
                if !forPrint { text.addAttribute(.link, value: checkboxLink, range: range) }
            case .wikiLink(let target):
                text.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: range)
                if !forPrint { text.addAttribute(.link, value: notePrefix + target, range: range) }
            case .link(let address):
                text.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
                if let url = URL(string: address) { text.addAttribute(.link, value: url, range: range) }
            case .marker:
                if !forPrint { text.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range) }
            }
        }
    }

    private static func addTrait(_ trait: NSFontTraitMask, to text: NSMutableAttributedString, in range: NSRange) {
        text.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let font = value as? NSFont else { return }
            text.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: subrange)
        }
    }
}

/// Markdown that formats itself as you type, with the syntax dimmed, like Obsidian's live preview.
/// `/` at the start of a line opens a menu of blocks and pages; clicking `[ ]` checks it; Enter continues lists.
/// Tables are edited in a grid drawn over their (hidden) Markdown.
struct MarkdownEditor: NSViewRepresentable {
    /// Changes when another note is opened, so undo history does not leak between notes.
    var id: URL
    var text: String
    var onChange: (String) -> Void
    var onOpenLink: (String) -> Void
    /// Titles offered by the `/` menu's link submenus.
    var pages: [String] = []
    var goals: [String] = []
    var tasks: [String] = []
    /// Creates a page under this one and returns its title.
    var onNewSubpage: () -> String? = { nil }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        // Transparent so the page color shows through, same as the header above it.
        scrollView.drawsBackground = false
        textView.drawsBackground = false
        // 35 + the 5pt line padding lines the text up with the title's 40pt margin.
        textView.textContainerInset = NSSize(width: 35, height: 24)
        textView.typingAttributes = MarkdownStyle.baseAttributes
        textView.linkTextAttributes = [.cursor: NSCursor.pointingHand]
        textView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator, selector: #selector(Coordinator.frameChanged),
            name: NSView.frameDidChangeNotification, object: textView
        )
        context.coordinator.textView = textView
        context.coordinator.load(text, id: id)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        let coordinator = context.coordinator
        if coordinator.loadedID != id || coordinator.textView?.string != text {
            coordinator.load(text, id: id)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        weak var textView: NSTextView?
        var loadedID: URL?
        private var tables: [NSHostingView<TableGrid>] = []
        private var tableRanges: [NSRange] = []
        private var lastSelection = NSRange(location: 0, length: 0)
        /// The open `/` list, while it is on screen.
        private var slashMenu: SlashMenu?

        init(_ parent: MarkdownEditor) {
            self.parent = parent
        }

        func load(_ text: String, id: URL) {
            guard let textView else { return }
            let selection = textView.selectedRange()
            textView.string = text
            if loadedID != id {
                textView.undoManager?.removeAllActions()
                textView.setSelectedRange(NSRange(location: 0, length: 0))
            } else {
                textView.setSelectedRange(NSRange(location: min(selection.location, textView.string.utf16.count), length: 0))
            }
            loadedID = id
            restyle()
        }

        private func restyle() {
            guard let textView, let storage = textView.textStorage else { return }
            let spans = MarkdownSpans.parse(storage.string)
            storage.beginEditing()
            MarkdownStyle.apply(spans, to: storage)
            storage.endEditing()
            textView.typingAttributes = MarkdownStyle.baseAttributes
            tableRanges = spans.filter { $0.kind == .table }.map(\.range)
            layoutTables()
        }

        @objc func frameChanged() { layoutTables() }

        // MARK: Tables

        /// Puts one grid over each table, reusing the views so a cell being typed in keeps focus.
        private func layoutTables() {
            guard let textView, let layout = textView.layoutManager, let container = textView.textContainer else { return }
            while tables.count > tableRanges.count { tables.removeLast().removeFromSuperview() }
            for (index, range) in tableRanges.enumerated() {
                let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                var rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
                rect.origin.x = textView.textContainerOrigin.x + container.lineFragmentPadding
                rect.origin.y += textView.textContainerOrigin.y
                rect.size.width = container.size.width - 2 * container.lineFragmentPadding
                let grid = TableGrid(rows: MarkdownTable.parse(string.substring(with: range))) { [weak self] rows in
                    self?.setTable(index, rows: rows)
                }
                if index < tables.count {
                    tables[index].rootView = grid
                } else {
                    tables.append(NSHostingView(rootView: grid))
                    textView.addSubview(tables[index])
                }
                tables[index].frame = rect
            }
        }

        /// Writes the grid back as Markdown; no rows deletes the table.
        private func setTable(_ index: Int, rows: [[String]]) {
            guard index < tableRanges.count else { return }
            var range = tableRanges[index]
            var text = MarkdownTable.render(rows)
            if rows.isEmpty, NSMaxRange(range) < string.length { range.length += 1 }  // its line break too
            guard text != string.substring(with: range) else { return }
            if rows.isEmpty { text = "" }
            replace(range, with: text, selecting: textView?.selectedRange())
        }

        /// The table's Markdown is hidden, so the cursor jumps over it instead of typing into it.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            let selection = textView.selectedRange()
            defer { lastSelection = textView.selectedRange() }
            guard selection.length == 0,
                  let table = tableRanges.first(where: { $0.location <= selection.location && selection.location <= NSMaxRange($0) })
            else { return }
            let backwards = selection.location < lastSelection.location
            let target = backwards ? table.location - 1 : NSMaxRange(table) + 1
            guard target >= 0, target <= string.length else { return }
            textView.setSelectedRange(NSRange(location: target, length: 0))
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            restyle()
            parent.onChange(textView.string)
            updateSlashQuery()
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let value = link as? String else { return false }  // real URLs open in the browser
            if value == MarkdownStyle.checkboxLink {
                toggleCheckbox(at: charIndex)
            } else if value.hasPrefix(MarkdownStyle.notePrefix) {
                parent.onOpenLink(String(value.dropFirst(MarkdownStyle.notePrefix.count)))
            }
            return true
        }

        func textView(
            _ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?
        ) -> Bool {
            if replacementString == "/", linePrefix(before: range.location).allSatisfy(\.isWhitespace) {
                let slash = range.location
                DispatchQueue.main.async { [weak self] in self?.showBlockMenu(slash: slash) }
            }
            return true
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if let menu = openSlashMenu {
                switch selector {
                case #selector(NSResponder.moveDown(_:)):
                    menu.move(1)
                    return true
                case #selector(NSResponder.moveUp(_:)):
                    menu.move(-1)
                    return true
                case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                    if menu.items.indices.contains(menu.selected) { pick(menu.items[menu.selected]) }
                    return true
                case #selector(NSResponder.cancelOperation(_:)):
                    closeSlashMenu()
                    return true
                case #selector(NSResponder.moveLeft(_:)), #selector(NSResponder.moveRight(_:)):
                    closeSlashMenu()
                default:
                    break
                }
            }
            return selector == #selector(NSResponder.insertNewline(_:)) ? continueList() : false
        }

        // MARK: Editing helpers

        private var string: NSString { (textView?.string ?? "") as NSString }

        private func linePrefix(before location: Int) -> String {
            let line = string.lineRange(for: NSRange(location: location, length: 0))
            return string.substring(with: NSRange(location: line.location, length: location - line.location))
        }

        /// Replaces text through the text view so it can be undone.
        private func replace(_ range: NSRange, with text: String, selecting selection: NSRange? = nil) {
            guard let textView, textView.shouldChangeText(in: range, replacementString: text) else { return }
            textView.textStorage?.replaceCharacters(in: range, with: text)
            textView.didChangeText()
            textView.setSelectedRange(selection ?? NSRange(location: range.location + (text as NSString).length, length: 0))
        }

        private func toggleCheckbox(at index: Int) {
            let line = string.lineRange(for: NSRange(location: index, length: 0))
            let box = string.range(of: "[", range: line)
            guard box.location != NSNotFound, box.location + 2 < NSMaxRange(line) else { return }
            let mark = NSRange(location: box.location + 1, length: 1)
            replace(mark, with: string.substring(with: mark) == " " ? "x" : " ", selecting: textView?.selectedRange())
        }

        private static let listPrefix = try! NSRegularExpression(pattern: #"^([ \t]*)([-*+] \[[ xX]\] |[-*+] |(\d+)([.)]) |> )"#)

        /// Enter on a list line starts the next item; Enter on an empty item ends the list.
        private func continueList() -> Bool {
            guard let textView else { return false }
            let cursor = textView.selectedRange()
            guard cursor.length == 0 else { return false }
            let lineStart = string.lineRange(for: NSRange(location: cursor.location, length: 0)).location
            let before = NSRange(location: lineStart, length: cursor.location - lineStart)
            guard let match = Self.listPrefix.firstMatch(in: string as String, range: before) else { return false }

            if NSMaxRange(match.range) == cursor.location,
               string.substring(from: cursor.location).prefix(while: { $0 != "\n" }).allSatisfy(\.isWhitespace) {
                replace(match.range, with: "")
                return true
            }
            let indent = string.substring(with: match.range(at: 1))
            var marker = string.substring(with: match.range(at: 2))
            if marker.contains("[") {
                marker = String(marker.prefix(2)) + "[ ] "
            } else if match.range(at: 3).location != NSNotFound, let number = Int(string.substring(with: match.range(at: 3))) {
                marker = "\(number + 1)\(string.substring(with: match.range(at: 4))) "
            }
            replace(cursor, with: "\n" + indent + marker)
            return true
        }

        private static let blocks: [(title: String, symbol: String, text: String)] = [
            ("Título 1", "textformat.size.larger", "# "),
            ("Título 2", "textformat.size", "## "),
            ("Título 3", "textformat.size.smaller", "### "),
            ("Lista", "list.bullet", "- "),
            ("Lista numerada", "list.number", "1. "),
            ("Checklist", "checklist", "- [ ] "),
            ("Citação", "text.quote", "> "),
            ("Destaque", "lightbulb", "> [!nota] "),
            ("Código", "curlybraces", "```\n\n```"),
            ("Divisória", "minus", "---\n"),
            ("Tabela", "tablecells", MarkdownTable.render([["Coluna 1", "Coluna 2"], ["", ""]]) + "\n"),
        ]

        /// The `/` list, if it is still the list on screen (Esc or a click elsewhere closes it from outside).
        private var openSlashMenu: SlashMenu? {
            guard let menu = slashMenu, Overlays.shared.popup?.id == menu.popupID else { return nil }
            return menu
        }

        /// The link items: picking one lists `titles` to link to.
        private func links(_ title: String, symbol: String, titles: [String], slash: Int) -> SlashMenu.Item {
            let children = titles.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { target in
                SlashMenu.Item(title: target, symbol: symbol) { [weak self] in self?.insert("[[\(target)]]", at: slash) }
            }
            return SlashMenu.Item(title: title, symbol: symbol, children: children)
        }

        private func showBlockMenu(slash: Int) {
            guard let textView, let layout = textView.layoutManager, let container = textView.textContainer,
                  slash < string.length, string.substring(with: NSRange(location: slash, length: 1)) == "/" else { return }
            var items = Self.blocks.map { block in
                SlashMenu.Item(title: block.title, symbol: block.symbol) { [weak self] in
                    // Code blocks put the cursor on the empty line between the fences.
                    self?.insert(block.text, at: slash, cursor: block.text.hasPrefix("```") ? 4 : nil)
                }
            }
            items.append(SlashMenu.Item(title: "Data de hoje", symbol: "calendar") { [weak self] in
                self?.insert(Date().formatted(date: .numeric, time: .omitted), at: slash)
            })
            items.append(SlashMenu.Item(title: "Página", symbol: "doc.badge.plus") { [weak self] in
                guard let self, let title = parent.onNewSubpage() else { return }
                insert("[[\(title)]]", at: slash)
            })
            items.append(links("Link para página", symbol: "link", titles: parent.pages, slash: slash))
            items.append(links("Mencionar objetivo", symbol: "target", titles: parent.goals, slash: slash))
            items.append(links("Mencionar tarefa", symbol: "checkmark.circle", titles: parent.tasks, slash: slash))

            let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: slash, length: 1), actualCharacterRange: nil)
            var rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            rect.origin.x += textView.textContainerOrigin.x
            rect.origin.y += textView.textContainerOrigin.y
            let menu = SlashMenu(slash: slash, items: items) { [weak self] in self?.pick($0) }
            menu.popupID = Overlays.shared.show(AnyView(SlashMenuView(menu: menu)), at: textView.globalRect(rect))
            slashMenu = menu
        }

        private func pick(_ item: SlashMenu.Item) {
            guard let menu = openSlashMenu, let textView else { return }
            if let children = item.children {
                guard !children.isEmpty else { return }
                menu.open(children, from: textView.selectedRange().location)
                return
            }
            closeSlashMenu()
            item.run()
            textView.window?.makeFirstResponder(textView)
        }

        /// Filters the list by what was typed after the `/`, or closes it once the slash is gone.
        private func updateSlashQuery() {
            guard let menu = slashMenu else { return }
            guard openSlashMenu != nil, let textView else { return closeSlashMenu() }
            let cursor = textView.selectedRange().location
            guard menu.slash < string.length, string.substring(with: NSRange(location: menu.slash, length: 1)) == "/",
                  cursor >= menu.queryStart else { return closeSlashMenu() }
            let query = string.substring(with: NSRange(location: menu.queryStart, length: cursor - menu.queryStart))
            if query.contains("\n") || query.hasPrefix(" ") || (query.hasSuffix(" ") && menu.items.isEmpty) {
                return closeSlashMenu()
            }
            menu.query = query
            menu.selected = 0
        }

        private func closeSlashMenu() {
            if openSlashMenu != nil { Overlays.shared.closePopup() }
            slashMenu = nil
        }

        /// Replaces the `/` with `text`, leaving the cursor at its end or `cursor` characters in.
        private func insert(_ text: String, at slash: Int, cursor: Int? = nil) {
            guard slash < string.length, string.substring(with: NSRange(location: slash, length: 1)) == "/" else { return }
            // Takes what was typed to filter the list along with the slash.
            let end = min(max(slash + 1, textView?.selectedRange().location ?? 0), string.length)
            let offset = cursor ?? (text as NSString).length
            replace(NSRange(location: slash, length: end - slash), with: text, selecting: NSRange(location: slash + offset, length: 0))
        }
    }
}

/// The `/` list of a note: blocks to insert, narrowed by what is typed after the slash.
@MainActor @Observable
final class SlashMenu {
    struct Item: Identifiable {
        let id = UUID()
        let title: String
        let symbol: String
        /// Titles to choose from next, for the link items.
        var children: [Item]?
        var run: () -> Void = {}
    }

    let slash: Int
    let root: [Item]
    let onPick: (Item) -> Void
    var popupID: UUID?
    /// Where the filter text starts: after the slash, or where a link list was opened.
    private(set) var queryStart: Int
    private var group: [Item]?
    var query = ""
    var selected = 0

    init(slash: Int, items: [Item], onPick: @escaping (Item) -> Void) {
        self.slash = slash
        root = items
        queryStart = slash + 1
        self.onPick = onPick
    }

    var items: [Item] {
        guard !query.isEmpty else { return group ?? root }
        // At the top, typing also finds pages, goals and tasks by name.
        let pool = group ?? root + root.flatMap { $0.children ?? [] }
        return pool.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    func open(_ children: [Item], from cursor: Int) {
        group = children
        queryStart = cursor
        query = ""
        selected = 0
    }

    func move(_ step: Int) {
        let count = items.count
        guard count > 0 else { return }
        selected = (selected + step + count) % count
    }
}

private struct SlashMenuView: View {
    let menu: SlashMenu

    var body: some View {
        let items = menu.items
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if items.isEmpty {
                        Text("Nada encontrado").foregroundStyle(Theme.secondaryText).padding(8)
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 8) {
                            Image(systemName: item.symbol).frame(width: 16).foregroundStyle(Theme.secondaryText)
                            Text(item.title).lineLimit(1)
                            Spacer(minLength: 8)
                            if item.children != nil {
                                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                            }
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 5).fill(index == menu.selected ? Theme.hover : .clear))
                        .contentShape(Rectangle())
                        .onHover { if $0 { menu.selected = index } }
                        .onTapGesture { menu.onPick(item) }
                        .opacity(item.children?.isEmpty == true ? 0.4 : 1)
                        .id(index)
                    }
                }
            }
            .frame(width: 240, height: min(CGFloat(max(items.count, 1)) * 28 + 4, 320))
            .onChange(of: menu.selected) { proxy.scrollTo(menu.selected) }
        }
    }
}

/// A Markdown table as a grid of editable cells, header first, with buttons to grow it.
/// Every row, the button bar included, is `rowHeight` tall so it covers exactly one hidden line of Markdown.
struct TableGrid: View {
    static let rowHeight: CGFloat = 32

    let rows: [[String]]
    var onChange: ([[String]]) -> Void

    var body: some View {
        let columns = rows.first?.count ?? 0
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<columns, id: \.self) { column in
                        TableCell(value: rows[row][column], header: row == 0) { set(row, column, $0) }
                            .appContextMenu {
                                if row > 0 { Button("Apagar linha") { onChange(rows.enumerated().filter { $0.offset != row }.map(\.element)) } }
                                if columns > 1 {
                                    Button("Apagar coluna") {
                                        onChange(rows.map { $0.enumerated().filter { $0.offset != column }.map(\.element) })
                                    }
                                }
                                Divider()
                                Button("Apagar tabela", role: .destructive) { onChange([]) }
                            }
                        if column < columns - 1 { Divider() }
                    }
                }
                .frame(height: Self.rowHeight)
                .background(row == 0 ? Theme.card : .clear)
                Divider()
            }
            HStack {
                Button("Linha", systemImage: "plus") { onChange(rows + [Array(repeating: "", count: columns)]) }
                Button("Coluna", systemImage: "plus") {
                    onChange(rows.enumerated().map { $1 + [$0 == 0 ? "Coluna \(columns + 1)" : ""] })
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(height: Self.rowHeight)
        }
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 4).stroke(Theme.border)
                .frame(height: Self.rowHeight * CGFloat(rows.count))
        }
    }

    private func set(_ row: Int, _ column: Int, _ value: String) {
        var rows = rows
        rows[row][column] = value
        onChange(rows)
    }
}

/// One cell. Keeps its own text while focused, so spaces being typed aren't trimmed away by the round trip through Markdown.
private struct TableCell: View {
    let value: String
    let header: Bool
    var onCommit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: MarkdownStyle.bodySize - 1, weight: header ? .semibold : .regular))
            .focused($focused)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .onChange(of: value, initial: true) { if !focused { text = value } }
            .onChange(of: text) { if text != value { onCommit(text) } }
    }
}
