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
/// `/` at the start of a line opens a menu of blocks; clicking `[ ]` checks it; Enter continues lists.
struct MarkdownEditor: NSViewRepresentable {
    /// Changes when another note is opened, so undo history does not leak between notes.
    var id: URL
    var text: String
    var onChange: (String) -> Void
    var onOpenLink: (String) -> Void

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
        textView.textContainerInset = NSSize(width: 32, height: 24)
        textView.typingAttributes = MarkdownStyle.baseAttributes
        textView.linkTextAttributes = [.cursor: NSCursor.pointingHand]
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
            storage.beginEditing()
            MarkdownStyle.apply(MarkdownSpans.parse(storage.string), to: storage)
            storage.endEditing()
            textView.typingAttributes = MarkdownStyle.baseAttributes
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            restyle()
            parent.onChange(textView.string)
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
            selector == #selector(NSResponder.insertNewline(_:)) ? continueList() : false
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
            ("Código", "curlybraces", "```\n\n```"),
            ("Divisória", "minus", "---\n"),
        ]

        private func showBlockMenu(slash: Int) {
            guard let textView, let layout = textView.layoutManager, let container = textView.textContainer,
                  slash < string.length, string.substring(with: NSRange(location: slash, length: 1)) == "/" else { return }
            let menu = NSMenu()
            for (index, block) in Self.blocks.enumerated() {
                let item = NSMenuItem(title: block.title, action: #selector(insertBlock(_:)), keyEquivalent: "")
                item.image = NSImage(systemSymbolName: block.symbol, accessibilityDescription: nil)
                item.target = self
                item.tag = index
                item.representedObject = slash
                menu.addItem(item)
            }
            let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: slash, length: 1), actualCharacterRange: nil)
            var rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            rect.origin.x += textView.textContainerOrigin.x
            rect.origin.y += textView.textContainerOrigin.y
            menu.popUp(positioning: nil, at: NSPoint(x: rect.minX, y: rect.maxY + 4), in: textView)
        }

        @objc private func insertBlock(_ item: NSMenuItem) {
            guard let slash = item.representedObject as? Int, slash < string.length else { return }
            let block = Self.blocks[item.tag].text
            // Code blocks put the cursor on the empty line between the fences.
            let cursor = block.hasPrefix("```") ? slash + 4 : slash + (block as NSString).length
            replace(NSRange(location: slash, length: 1), with: block, selecting: NSRange(location: cursor, length: 0))
        }
    }
}
