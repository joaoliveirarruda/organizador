import AppKit
import OrganizadorCore
import UniformTypeIdentifiers

/// Saves a note as an A4 PDF with the Markdown rendered: no `#`, `**` or `[[ ]]`, bullets, boxes and tables drawn.
@MainActor
enum NotePDF {
    /// Asks where to save, then writes the PDF. Returns false when the user cancels.
    @discardableResult
    static func export(_ note: Note) -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = note.title + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return write(note, to: url)
    }

    static func write(_ note: Note, to url: URL) -> Bool {
        let printInfo = NSPrintInfo(dictionary: [.jobSavingURL: url])
        printInfo.jobDisposition = .save
        printInfo.paperSize = NSSize(width: 595, height: 842)
        for margin in [\NSPrintInfo.topMargin, \.bottomMargin, \.leftMargin, \.rightMargin] {
            printInfo[keyPath: margin] = 56
        }
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isVerticallyCentered = false

        let width = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        textView.appearance = NSAppearance(named: .aqua)  // black text on white, whatever the app's theme
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textStorage?.setAttributedString(rendered(note))
        textView.sizeToFit()

        let operation = NSPrintOperation(view: textView, printInfo: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        return operation.run()
    }

    static func rendered(_ note: Note) -> NSAttributedString {
        let text = NSMutableAttributedString(string: note.body)
        let spans = MarkdownSpans.parse(note.body)
        MarkdownStyle.apply(spans, to: text, forPrint: true)

        let edits: [(range: NSRange, text: NSAttributedString)] = spans.compactMap { span in
            let plain = { (string: String) in
                (span.range, NSAttributedString(string: string, attributes: text.attributes(at: span.range.location, effectiveRange: nil)))
            }
            switch span.kind {
            case .table: return (span.range, table(MarkdownTable.parse(text.attributedSubstring(from: span.range).string)))
            case .marker: return plain("")
            case .checkbox(let checked): return plain(checked ? "☑ " : "☐ ")
            case .rule: return plain(String(repeating: "─", count: 28))
            case .listItem:
                let marker = text.attributedSubstring(from: span.range).string
                return "-*+".contains(marker.prefix(1)) ? plain("• ") : nil
            default: return nil
            }
        }
        // From the end, so earlier ranges stay valid.
        var limit = text.length
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) where NSMaxRange(edit.range) <= limit {
            text.replaceCharacters(in: edit.range, with: edit.text)
            limit = edit.range.location
        }

        let title = NSMutableAttributedString(string: note.title + "\n", attributes: MarkdownStyle.baseAttributes)
        title.addAttribute(.font, value: NSFont.systemFont(ofSize: 30, weight: .bold), range: NSRange(location: 0, length: title.length))
        text.insert(title, at: 0)
        return text
    }

    /// Rows of cells as an `NSTextTable` with thin borders, header in bold.
    private static func table(_ rows: [[String]]) -> NSAttributedString {
        let table = NSTextTable()
        table.numberOfColumns = rows.first?.count ?? 0
        table.collapsesBorders = true
        let result = NSMutableAttributedString()
        for (row, cells) in rows.enumerated() {
            for (column, cell) in cells.enumerated() {
                let block = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
                block.setWidth(0.5, type: .absoluteValueType, for: .border)
                block.setBorderColor(.gray)
                block.setWidth(4, type: .absoluteValueType, for: .padding)
                let paragraph = NSMutableParagraphStyle()
                paragraph.textBlocks = [block]
                var attributes = MarkdownStyle.baseAttributes
                attributes[.paragraphStyle] = paragraph
                if row == 0 { attributes[.font] = NSFont.systemFont(ofSize: MarkdownStyle.bodySize, weight: .semibold) }
                result.append(NSAttributedString(string: cell + "\n", attributes: attributes))
            }
        }
        return result
    }
}
