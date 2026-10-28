import OrganizadorCore
import SwiftUI

/// Obsidian-style graph: notes, and the goals and tasks they mention, pulled together by their links.
/// Drag a node to move it, drag the background to pan, pinch to zoom, click to open.
struct NoteGraphView: View {
    let graph: NoteGraph
    var selected: URL?
    var onOpen: (GraphNode.Ref) -> Void

    @State private var layout = ForceLayout(count: 0)
    @State private var refs: [GraphNode.Ref] = []
    /// Bumped to restart the simulation after the graph changes or a node is dragged.
    @State private var wakeups = 0
    @State private var offset = CGSize.zero
    @State private var panStart: CGSize?
    @State private var zoom: CGFloat = 1
    @State private var zoomStart: CGFloat?
    @State private var dragging: Int?
    @State private var hovered: Int?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Canvas { context, _ in draw(in: &context, size: size) }
                .contentShape(Rectangle())
                .gesture(dragGesture(size: size))
                .simultaneousGesture(MagnifyGesture()
                    .onChanged { value in
                        zoomStart = zoomStart ?? zoom
                        zoom = min(4, max(0.2, (zoomStart ?? 1) * value.magnification))
                    }
                    .onEnded { _ in zoomStart = nil })
                .onContinuousHover { phase in
                    if case .active(let location) = phase {
                        hovered = node(at: location, size: size)
                    } else {
                        hovered = nil
                    }
                }
        }
        .overlay(alignment: .bottomTrailing) {
            HStack {
                Legend(color: .accentColor, title: "Nota")
                Legend(color: Color(hex: Palette.colors[4]), title: "Objetivo")
                Legend(color: Color(hex: Palette.colors[2]), title: "Tarefa")
                Button("Centralizar") {
                    offset = .zero
                    zoom = 1
                }
            }
            .font(.caption)
            .padding(10)
        }
        .onAppear(perform: syncLayout)
        .onChange(of: graph.nodes.map(\.ref)) { syncLayout() }
        .onChange(of: graph.edges) { wakeups += 1 }
        .task(id: wakeups) {
            while !Task.isCancelled {
                let movement = layout.step(edges: graph.edges, pinned: dragging)
                if movement < 0.05 * Double(refs.count), dragging == nil { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    /// Keeps the position of nodes that were already on screen when notes are added or removed.
    private func syncLayout() {
        let old = Dictionary(uniqueKeysWithValues: zip(refs, layout.positions))
        var next = ForceLayout(count: graph.nodes.count)
        for (index, node) in graph.nodes.enumerated() {
            if let position = old[node.ref] { next.positions[index] = position }
        }
        layout = next
        refs = graph.nodes.map(\.ref)
        wakeups += 1
    }

    // MARK: Geometry

    private func screen(_ point: SIMD2<Double>, size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width / 2 + offset.width + CGFloat(point.x) * zoom,
            y: size.height / 2 + offset.height + CGFloat(point.y) * zoom
        )
    }

    private func world(_ point: CGPoint, size: CGSize) -> SIMD2<Double> {
        SIMD2(
            Double((point.x - size.width / 2 - offset.width) / zoom),
            Double((point.y - size.height / 2 - offset.height) / zoom)
        )
    }

    private var degrees: [Int] {
        var degrees = Array(repeating: 0, count: graph.nodes.count)
        for edge in graph.edges {
            degrees[edge.from] += 1
            degrees[edge.to] += 1
        }
        return degrees
    }

    private func radius(degree: Int) -> CGFloat {
        (4 + 2 * CGFloat(Double(degree).squareRoot())) * max(zoom, 0.6)
    }

    private func node(at location: CGPoint, size: CGSize) -> Int? {
        guard layout.positions.count == graph.nodes.count else { return nil }
        let degrees = degrees
        return layout.positions.indices.min { a, b in
            distance(screen(layout.positions[a], size: size), location) < distance(screen(layout.positions[b], size: size), location)
        }.flatMap { index in
            distance(screen(layout.positions[index], size: size), location) <= radius(degree: degrees[index]) + 6 ? index : nil
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    // MARK: Drawing

    private func color(_ node: GraphNode) -> Color {
        switch node.ref {
        case .note: .accentColor
        case .goal: Color(hex: Palette.colors[4])
        case .task: Color(hex: Palette.colors[2])
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        guard layout.positions.count == graph.nodes.count else { return }
        let degrees = degrees
        let focus = hovered ?? dragging
        var neighbors = Set<Int>()
        if let focus {
            neighbors.insert(focus)
            for edge in graph.edges where edge.from == focus || edge.to == focus {
                neighbors.formUnion([edge.from, edge.to])
            }
        }
        func dimmed(_ index: Int) -> Bool { focus != nil && !neighbors.contains(index) }

        for edge in graph.edges {
            var path = Path()
            path.move(to: screen(layout.positions[edge.from], size: size))
            path.addLine(to: screen(layout.positions[edge.to], size: size))
            let lit = focus != nil && (edge.from == focus || edge.to == focus)
            context.stroke(path, with: .color(lit ? .accentColor : .secondary.opacity(dimmed(edge.from) ? 0.1 : 0.35)), lineWidth: lit ? 1.5 : 1)
        }

        for (index, node) in graph.nodes.enumerated() {
            let center = screen(layout.positions[index], size: size)
            let r = radius(degree: degrees[index])
            let circle = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            context.fill(circle, with: .color(color(node).opacity(dimmed(index) ? 0.2 : 1)))
            if case .note(let url) = node.ref, url == selected {
                context.stroke(circle.insetBy(-3), with: .color(.primary), lineWidth: 1.5)
            }
            if zoom > 0.7 || neighbors.contains(index) {
                let label = Text(node.title)
                    .font(.system(size: 11, weight: index == focus ? .semibold : .regular))
                    .foregroundStyle(Color.primary.opacity(dimmed(index) ? 0.25 : 0.85))
                context.draw(label, at: CGPoint(x: center.x, y: center.y + r + 4), anchor: .top)
            }
        }
    }

    // MARK: Gestures

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragging == nil, panStart == nil {
                    if let index = node(at: value.startLocation, size: size) {
                        dragging = index
                        wakeups += 1
                    } else {
                        panStart = offset
                    }
                }
                if let dragging, dragging < layout.positions.count {
                    layout.positions[dragging] = world(value.location, size: size)
                } else if let panStart {
                    offset = CGSize(width: panStart.width + value.translation.width, height: panStart.height + value.translation.height)
                }
            }
            .onEnded { value in
                let isClick = hypot(value.translation.width, value.translation.height) < 4
                if isClick, let index = dragging ?? node(at: value.location, size: size) {
                    onOpen(graph.nodes[index].ref)
                }
                dragging = nil
                panStart = nil
                wakeups += 1
            }
    }
}

private extension Path {
    func insetBy(_ amount: CGFloat) -> Path {
        Path(ellipseIn: boundingRect.insetBy(dx: amount, dy: amount))
    }
}

private struct Legend: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).foregroundStyle(.secondary)
        }
    }
}
