import Foundation

/// A Markdown note stored as `<title>.md`. The title is the file name, as in Obsidian.
public struct Note: Identifiable, Hashable, Sendable {
    public var url: URL
    public var body: String
    public var modifiedAt: Date

    public init(url: URL, body: String, modifiedAt: Date = Date()) {
        self.url = url
        self.body = body
        self.modifiedAt = modifiedAt
    }

    public var id: URL { url }
    public var title: String { url.deletingPathExtension().lastPathComponent }
}

public enum NoteError: LocalizedError, Equatable {
    case alreadyExists(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyExists(let title): "Já existe uma nota chamada \"\(title)\"."
        }
    }
}

/// Reads and writes notes as `.md` files in a folder (subfolders included), so the folder
/// also works as an Obsidian vault.
public struct NoteStore: Sendable {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// Every note in the folder, most recently changed first. Hidden folders like `.obsidian` are skipped.
    public func list() throws -> [Note] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let files = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var notes: [Note] = []
        for case let url as URL in files where url.pathExtension.lowercased() == "md" {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else { continue }
            let body = try String(contentsOf: url, encoding: .utf8)
            notes.append(Note(url: url, body: body, modifiedAt: values.contentModificationDate ?? Date()))
        }
        return notes.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    public func save(_ note: Note) throws {
        try note.body.write(to: note.url, atomically: true, encoding: .utf8)
    }

    /// Creates an empty note named `title`, or `title 2`, `title 3`... when the name is taken.
    public func create(title: String = "Sem título", body: String = "") throws -> Note {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = Self.sanitize(title)
        var name = base
        var counter = 2
        while FileManager.default.fileExists(atPath: url(for: name, in: folder).path) {
            name = "\(base) \(counter)"
            counter += 1
        }
        let note = Note(url: url(for: name, in: folder), body: body)
        try save(note)
        return note
    }

    /// Renames the file and rewrites `[[old]]` links to `[[new]]` in every note.
    /// Returns the renamed note.
    public func rename(_ note: Note, to title: String) throws -> Note {
        let newTitle = Self.sanitize(title)
        let oldTitle = note.title
        guard newTitle != oldTitle else { return note }
        let target = url(for: newTitle, in: note.url.deletingLastPathComponent())
        let caseOnly = newTitle.lowercased() == oldTitle.lowercased()
        if !caseOnly, FileManager.default.fileExists(atPath: target.path) {
            throw NoteError.alreadyExists(newTitle)
        }
        if caseOnly {
            // Case-insensitive disks treat "a.md" and "A.md" as the same file, so go through a temporary name.
            let temporary = note.url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".md")
            try FileManager.default.moveItem(at: note.url, to: temporary)
            try FileManager.default.moveItem(at: temporary, to: target)
        } else {
            try FileManager.default.moveItem(at: note.url, to: target)
        }

        var renamed = note
        renamed.url = target
        for var other in try list() {
            let body = WikiLinks.rewrite(other.body, from: oldTitle, to: newTitle)
            guard body != other.body else { continue }
            other.body = body
            try save(other)
            if other.url == target { renamed.body = body }
        }
        return renamed
    }

    /// Moves the note to the Trash, so it can still be recovered.
    public func trash(_ note: Note) throws {
        try FileManager.default.trashItem(at: note.url, resultingItemURL: nil)
    }

    /// A title that is safe as a file name: no slashes, colons or line breaks, never empty.
    public static func sanitize(_ title: String) -> String {
        var text = title
        for character in ["/", ":", "\\", "\n", "\r"] {
            text = text.replacingOccurrences(of: character, with: "-")
        }
        text = text.trimmingCharacters(in: .whitespaces)
        while text.hasPrefix(".") { text.removeFirst() }
        return text.isEmpty ? "Sem título" : text
    }

    private func url(for title: String, in directory: URL) -> URL {
        directory.appendingPathComponent(title).appendingPathExtension("md")
    }
}

/// `[[Note]]`, `[[Note#Section]]` and `[[Note|alias]]` links between notes.
public enum WikiLinks {
    /// Groups: 1 target, 2 `#section`, 3 `|alias`.
    static let pattern = try! NSRegularExpression(
        pattern: #"\[\[([^\[\]|#\n]+)(#[^\[\]|\n]*)?(\|[^\[\]\n]*)?\]\]"#
    )

    /// The note titles linked from `text`, in order, without repeats.
    public static func targets(in text: String) -> [String] {
        let string = text as NSString
        var seen = Set<String>()
        var targets: [String] = []
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: string.length)) {
            let target = string.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            guard !target.isEmpty, seen.insert(target.lowercased()).inserted else { continue }
            targets.append(target)
        }
        return targets
    }

    /// Points links to `old` at `new`, keeping their section and alias.
    public static func rewrite(_ text: String, from old: String, to new: String) -> String {
        let string = text as NSString
        var result = text as NSString
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: string.length)).reversed() {
            let targetRange = match.range(at: 1)
            let target = string.substring(with: targetRange).trimmingCharacters(in: .whitespaces)
            guard target.caseInsensitiveCompare(old) == .orderedSame else { continue }
            result = result.replacingCharacters(in: targetRange, with: new) as NSString
        }
        return result as String
    }
}

/// What a part of a Markdown text is, for styling it in the editor and rendering it in a PDF.
public struct MarkdownSpan: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// The whole heading line, without its line break.
        case heading(Int)
        case bold, italic, strikethrough, code, quote, rule
        /// The fenced block, fences included.
        case codeBlock
        /// The list marker (`- `, `1. `), without indentation.
        case listItem
        /// The `- [ ] ` marker.
        case checkbox(checked: Bool)
        /// The whole `[[...]]`.
        case wikiLink(String)
        /// The link text.
        case link(String)
        /// Markdown syntax that is hidden in a rendered document (`#`, `**`, `[[`, fences...).
        case marker
    }

    public var kind: Kind
    /// UTF-16 range, as used by `NSString` and `NSTextView`.
    public var range: NSRange

    public init(_ kind: Kind, _ range: NSRange) {
        self.kind = kind
        self.range = range
    }
}

/// A small line-based Markdown reader: headings, lists, checklists, quotes, code, rules,
/// emphasis, links and wiki links. Not CommonMark; just what notes need.
public enum MarkdownSpans {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }

    private static let fence = regex(#"^\s*```"#)
    private static let heading = regex(#"^(#{1,6})[ \t]+"#)
    private static let rule = regex(#"^[ \t]*(?:-{3,}|\*{3,}|_{3,})[ \t]*$"#)
    private static let quote = regex(#"^>[ \t]?"#)
    private static let checkbox = regex(#"^[ \t]*([-*+] \[( |x|X)\] )"#)
    private static let listItem = regex(#"^[ \t]*([-*+]|\d+[.)]) "#)
    private static let inlineCode = regex(#"`([^`\n]+)`"#)
    private static let bold = regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let italic = regex(#"(?<![*\w])\*(?![\s*])(.+?)(?<![\s*])\*(?!\*)|(?<![_\w])_(?![\s_])(.+?)(?<![\s_])_(?!\w)"#)
    private static let strike = regex(#"~~(?=\S)(.+?)(?<=\S)~~"#)
    private static let link = regex(#"(?<![!\[])\[([^\[\]\n]+)\]\(([^)\s]+)\)"#)

    public static func parse(_ text: String) -> [MarkdownSpan] {
        let string = text as NSString
        var spans: [MarkdownSpan] = []
        var fenceStart: Int?
        var location = 0

        while location < string.length {
            let lineWithBreak = string.lineRange(for: NSRange(location: location, length: 0))
            var line = lineWithBreak
            while line.length > 0, [10, 13].contains(string.character(at: NSMaxRange(line) - 1)) {
                line.length -= 1
            }
            location = NSMaxRange(lineWithBreak)

            if fence.firstMatch(in: text, range: line) != nil {
                spans.append(MarkdownSpan(.marker, lineWithBreak))
                if let start = fenceStart {
                    spans.append(MarkdownSpan(.codeBlock, NSRange(location: start, length: NSMaxRange(line) - start)))
                    fenceStart = nil
                } else {
                    fenceStart = line.location
                }
                continue
            }
            if fenceStart != nil { continue }
            spans += parseLine(text, line: line)
        }
        if let start = fenceStart {
            spans.append(MarkdownSpan(.codeBlock, NSRange(location: start, length: string.length - start)))
        }
        return spans
    }

    private static func parseLine(_ text: String, line: NSRange) -> [MarkdownSpan] {
        var spans: [MarkdownSpan] = []
        var content = line

        if rule.firstMatch(in: text, range: line) != nil {
            return [MarkdownSpan(.rule, line)]
        }
        if let match = heading.firstMatch(in: text, range: line) {
            spans.append(MarkdownSpan(.heading(match.range(at: 1).length), line))
            spans.append(MarkdownSpan(.marker, match.range))
            content = NSRange(location: NSMaxRange(match.range), length: NSMaxRange(line) - NSMaxRange(match.range))
        } else if let match = quote.firstMatch(in: text, range: line) {
            spans.append(MarkdownSpan(.quote, line))
            spans.append(MarkdownSpan(.marker, match.range))
            content = NSRange(location: NSMaxRange(match.range), length: NSMaxRange(line) - NSMaxRange(match.range))
        } else if let match = checkbox.firstMatch(in: text, range: line) {
            let checked = (text as NSString).substring(with: match.range(at: 2)) != " "
            spans.append(MarkdownSpan(.checkbox(checked: checked), match.range(at: 1)))
            content = NSRange(location: NSMaxRange(match.range), length: NSMaxRange(line) - NSMaxRange(match.range))
            if checked { spans.append(MarkdownSpan(.strikethrough, content)) }
        } else if let match = listItem.firstMatch(in: text, range: line) {
            spans.append(MarkdownSpan(.listItem, NSRange(
                location: match.range(at: 1).location, length: NSMaxRange(match.range) - match.range(at: 1).location
            )))
            content = NSRange(location: NSMaxRange(match.range), length: NSMaxRange(line) - NSMaxRange(match.range))
        }

        // Inline code first; nothing inside it is formatted.
        var taken: [NSRange] = []
        func isFree(_ range: NSRange) -> Bool {
            !taken.contains { NSIntersectionRange($0, range).length > 0 }
        }
        for match in inlineCode.matches(in: text, range: content) {
            spans.append(MarkdownSpan(.code, match.range))
            spans += edgeMarkers(match.range, open: 1, close: 1)
            taken.append(match.range)
        }
        for match in WikiLinks.pattern.matches(in: text, range: content) where isFree(match.range) {
            let target = (text as NSString).substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            spans.append(MarkdownSpan(.wikiLink(target), match.range))
            // With an alias only the alias shows, as in Obsidian.
            let alias = match.range(at: 3)
            let open = alias.location == NSNotFound ? 2 : alias.location + 1 - match.range.location
            spans += edgeMarkers(match.range, open: open, close: 2)
            taken.append(match.range)
        }
        for match in link.matches(in: text, range: content) where isFree(match.range) {
            let url = (text as NSString).substring(with: match.range(at: 2))
            spans.append(MarkdownSpan(.link(url), match.range(at: 1)))
            spans.append(MarkdownSpan(.marker, NSRange(location: match.range.location, length: 1)))
            let tail = NSMaxRange(match.range(at: 1))
            spans.append(MarkdownSpan(.marker, NSRange(location: tail, length: NSMaxRange(match.range) - tail)))
            taken.append(match.range)
        }
        for (expression, kind, width) in [(bold, MarkdownSpan.Kind.bold, 2), (strike, .strikethrough, 2), (italic, .italic, 1)] {
            for match in expression.matches(in: text, range: content) where isFree(match.range) {
                spans.append(MarkdownSpan(kind, match.range))
                spans += edgeMarkers(match.range, open: width, close: width)
                if kind != .bold { taken.append(match.range) }
            }
        }
        return spans
    }

    private static func edgeMarkers(_ range: NSRange, open: Int, close: Int) -> [MarkdownSpan] {
        [
            MarkdownSpan(.marker, NSRange(location: range.location, length: open)),
            MarkdownSpan(.marker, NSRange(location: NSMaxRange(range) - close, length: close)),
        ]
    }
}

/// A point in the connections graph: a note, or a goal or task that a note links to.
public struct GraphNode: Identifiable, Hashable, Sendable {
    public enum Ref: Hashable, Sendable {
        case note(URL)
        case goal(UUID)
        case task(UUID)
    }

    public var ref: Ref
    public var title: String

    public var id: Ref { ref }
}

public struct GraphEdge: Hashable, Sendable {
    /// Indexes into `NoteGraph.nodes`.
    public var from: Int
    public var to: Int
}

/// Notes and the `[[links]]` between them, plus the goals and tasks they mention.
public struct NoteGraph: Sendable {
    public var nodes: [GraphNode]
    public var edges: [GraphEdge]

    /// What `[[target]]` points to: a note first, then a goal, then a task, by title ignoring case.
    public static func resolve(_ target: String, notes: [Note], goals: [Goal], tasks: [TaskItem]) -> GraphNode? {
        func same(_ title: String) -> Bool { title.caseInsensitiveCompare(target) == .orderedSame }
        if let note = notes.first(where: { same($0.title) }) { return GraphNode(ref: .note(note.url), title: note.title) }
        if let goal = goals.first(where: { same($0.title) }) { return GraphNode(ref: .goal(goal.id), title: goal.title) }
        if let task = tasks.first(where: { same($0.title) }) { return GraphNode(ref: .task(task.id), title: task.title) }
        return nil
    }

    /// Every note is a node; goals and tasks only when some note links to them. Links to nothing are left out.
    public static func build(notes: [Note], goals: [Goal], tasks: [TaskItem]) -> NoteGraph {
        var nodes = notes.map { GraphNode(ref: .note($0.url), title: $0.title) }
        var index = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.ref, $0) })
        var edges = Set<GraphEdge>()
        for (from, note) in notes.enumerated() {
            for target in WikiLinks.targets(in: note.body) {
                guard let node = resolve(target, notes: notes, goals: goals, tasks: tasks) else { continue }
                let to = index[node.ref] ?? {
                    nodes.append(node)
                    index[node.ref] = nodes.count - 1
                    return nodes.count - 1
                }()
                if to != from { edges.insert(GraphEdge(from: from, to: to)) }
            }
        }
        return NoteGraph(nodes: nodes, edges: edges.sorted { ($0.from, $0.to) < ($1.from, $1.to) })
    }

    /// Notes that link to `title`.
    public static func backlinks(to title: String, in notes: [Note]) -> [Note] {
        notes.filter { note in
            note.title != title
                && WikiLinks.targets(in: note.body).contains { $0.caseInsensitiveCompare(title) == .orderedSame }
        }
    }
}

/// Force-directed layout: nodes push each other away, links pull like springs, everything drifts to the center.
// ponytail: O(n²) per step, use a quadtree (Barnes-Hut) if vaults pass ~1000 notes.
public struct ForceLayout: Sendable {
    public var positions: [SIMD2<Double>]
    private var velocities: [SIMD2<Double>]

    public var repulsion = 6_000.0
    public var linkLength = 90.0
    public var linkStrength = 0.04
    public var gravity = 0.012
    public var damping = 0.82

    /// Starts nodes on a spiral around the origin so the first frames are stable and repeatable.
    public init(count: Int) {
        positions = (0..<count).map { index in
            let angle = Double(index) * 2.399963  // golden angle
            let radius = 30 * Double(index).squareRoot() + 10
            return SIMD2(cos(angle) * radius, sin(angle) * radius)
        }
        velocities = Array(repeating: .zero, count: count)
    }

    /// Advances one step and returns the total movement, which goes to ~0 once the layout settles.
    /// `pinned` stays where it is (the node being dragged).
    @discardableResult
    public mutating func step(edges: [GraphEdge], pinned: Int? = nil) -> Double {
        let count = positions.count
        var forces = Array(repeating: SIMD2<Double>.zero, count: count)
        for i in 0..<count {
            for j in (i + 1)..<max(i + 1, count) {
                var delta = positions[i] - positions[j]
                var distanceSquared = (delta * delta).sum()
                if distanceSquared < 0.01 {
                    delta = SIMD2(Double(i - j), 1)
                    distanceSquared = 1
                }
                let push = delta / distanceSquared.squareRoot() * (repulsion / distanceSquared)
                forces[i] += push
                forces[j] -= push
            }
        }
        for edge in edges where edge.from < count && edge.to < count {
            let delta = positions[edge.to] - positions[edge.from]
            let distance = max((delta * delta).sum().squareRoot(), 0.01)
            let pull = delta / distance * ((distance - linkLength) * linkStrength)
            forces[edge.from] += pull
            forces[edge.to] -= pull
        }
        var movement = 0.0
        for i in 0..<count {
            guard i != pinned else {
                velocities[i] = .zero
                continue
            }
            forces[i] -= positions[i] * gravity
            var velocity = (velocities[i] + forces[i]) * damping
            let speed = (velocity * velocity).sum().squareRoot()
            if speed > 40 { velocity *= 40 / speed }
            velocities[i] = velocity
            positions[i] += velocity
            movement += min(speed, 40)
        }
        return movement
    }
}
