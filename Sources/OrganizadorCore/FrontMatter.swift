import Foundation

/// The YAML block at the top of a note (`---` ... `---`), as Obsidian writes it.
/// Only `icon` and `cover` are understood; every other line is kept as it was.
public struct FrontMatter: Hashable, Sendable {
    public var icon: Icon?
    /// Image path relative to the notes folder.
    public var cover: String?
    /// The block's lines as read, `icon:` and `cover:` included (they are rewritten on render).
    private var lines: [String] = []

    public init(icon: Icon? = nil, cover: String? = nil) {
        self.icon = icon
        self.cover = cover
    }

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp"]

    /// Splits a note into its front matter and the Markdown body. Text without a block has an empty front matter.
    public static func parse(_ text: String) -> (FrontMatter, body: String) {
        guard text.hasPrefix("---\n") else { return (FrontMatter(), text) }
        let rest = text.dropFirst(4)
        let closing: Range<Substring.Index>
        if rest.hasPrefix("---\n") || rest == "---" {
            closing = rest.startIndex..<rest.index(rest.startIndex, offsetBy: min(4, rest.count))
        } else if let range = rest.range(of: "\n---\n") ?? (rest.hasSuffix("\n---") ? rest.range(of: "\n---", options: .backwards) : nil) {
            closing = range
        } else {
            return (FrontMatter(), text)
        }
        var meta = FrontMatter()
        let block = rest[rest.startIndex..<closing.lowerBound]
        meta.lines = block.isEmpty ? [] : block.components(separatedBy: "\n")
        for line in meta.lines {
            if let value = value(of: "icon", in: line), !value.isEmpty {
                let isImage = imageExtensions.contains((value as NSString).pathExtension.lowercased())
                meta.icon = isImage ? .image(value) : .emoji(value)
            } else if let value = value(of: "cover", in: line), !value.isEmpty {
                meta.cover = value
            }
        }
        return (meta, String(rest[closing.upperBound...]))
    }

    /// The note text: the block (left out when there is nothing to put in it) followed by `body`.
    public func render(_ body: String) -> String {
        var output: [String] = []
        var wroteIcon = false
        var wroteCover = false
        for line in lines {
            if Self.value(of: "icon", in: line) != nil {
                if let icon, !wroteIcon { output.append("icon: \(Self.text(of: icon))") }
                wroteIcon = true
            } else if Self.value(of: "cover", in: line) != nil {
                if let cover, !wroteCover { output.append("cover: \(cover)") }
                wroteCover = true
            } else {
                output.append(line)
            }
        }
        if let icon, !wroteIcon { output.append("icon: \(Self.text(of: icon))") }
        if let cover, !wroteCover { output.append("cover: \(cover)") }
        guard !output.isEmpty else { return body }
        return "---\n" + output.joined(separator: "\n") + "\n---\n" + body
    }

    private static func text(of icon: Icon) -> String {
        switch icon {
        case .emoji(let text), .image(let text): text
        }
    }

    /// The value of a top-level `key: value` line, without quotes.
    private static func value(of key: String, in line: String) -> String? {
        guard line.hasPrefix(key + ":") else { return nil }
        var value = line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
        if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }
}
