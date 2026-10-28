import AppKit
import OrganizadorCore
import UniformTypeIdentifiers

/// Saves a note as an A4 PDF with the Markdown rendered: no `#`, `**` or `[[ ]]`, bullets and boxes drawn.
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

        let edits: [(range: NSRange, text: String)] = spans.compactMap { span in
            switch span.kind {
            case .marker: return (span.range, "")
            case .checkbox(let checked): return (span.range, checked ? "☑ " : "☐ ")
            case .rule: return (span.range, String(repeating: "─", count: 28))
            case .listItem:
                let marker = text.attributedSubstring(from: span.range).string
                return "-*+".contains(marker.prefix(1)) ? (span.range, "• ") : nil
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
}
