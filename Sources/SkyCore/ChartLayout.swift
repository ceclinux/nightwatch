import Foundation

/// Layout for Tonight's plan chart (#92 follow-up, owner, 1 October 2026): each target keeps its line style from night
/// to night, and the names at the peaks keep clear of each other and of the other lines.
public enum ChartLayout {
    /// A style for each target, chosen from its ID so it stays the same whatever else is in the plan; two that want
    /// the same style in one plan are settled in ID order, the later taking the next free one. With more targets than
    /// styles, styles repeat.
    public static func styles(for ids: [String], count: Int) -> [String: Int] {
        guard count > 0 else { return [:] }
        var taken = Set<Int>(), out: [String: Int] = [:]
        for id in Set(ids).sorted() {
            let want = Int(fnv1a(id) % UInt64(count))
            let free = (0..<count).map { (want + $0) % count }.first { !taken.contains($0) } ?? want
            out[id] = free
            taken.insert(free)
            if taken.count == count { taken.removeAll() }
        }
        return out
    }

    /// FNV-1a: stable across launches, unlike Swift's seeded `hashValue`.
    static func fnv1a(_ s: String) -> UInt64 {
        s.utf8.reduce(0xcbf29ce484222325) { ($0 ^ UInt64($1)) &* 0x100000001b3 }
    }

    public struct Label: Equatable, Sendable {
        public var x: Double, y: Double
        public let width: Double, height: Double
        public init(x: Double, y: Double, width: Double, height: Double) { self.x = x; self.y = y; self.width = width; self.height = height }
        func contains(_ px: Double, _ py: Double) -> Bool { abs(px - x) <= width / 2 && abs(py - y) <= height / 2 }
        func overlaps(_ o: Label) -> Bool { abs(x - o.x) * 2 < width + o.width && abs(y - o.y) * 2 < height + o.height }
    }

    /// Centres for labels named at `anchors` (each label's peak), in chart points. Each tries above its peak, then
    /// below, beside, and further above or below, taking the first spot that touches no other label and no other
    /// target's line (`lines[i]` is label i's own line, which it may touch); failing that, the spot touching least.
    /// Every spot is kept inside `width` × `height`.
    public static func placeLabels(anchors: [(x: Double, y: Double)], sizes: [(width: Double, height: Double)],
                                   lines: [[(x: Double, y: Double)]], width: Double, height: Double) -> [(x: Double, y: Double)] {
        var placed: [Label] = []
        for (i, a) in anchors.enumerated() {
            let (w, h) = sizes[i]
            let offsets = [(0.0, -11.0), (0, 13), (w / 2 + 7, -2), (-(w / 2 + 7), -2), (0, -24), (0, 26), (0, -37), (0, 39)]
            var best: (Label, Int)?
            for (dx, dy) in offsets {
                let l = Label(x: min(max(a.x + dx, w / 2), width - w / 2), y: min(max(a.y + dy, h / 2), height - h / 2), width: w, height: h)
                let hits = placed.filter { $0.overlaps(l) }.count * 10 + lines.indices.filter { $0 != i }.reduce(0) { n, j in n + crossings(l, lines[j]) }
                if best == nil || hits < best!.1 { best = (l, hits) }
                if hits == 0 { break }
            }
            placed.append(best!.0)
        }
        return placed.map { ($0.x, $0.y) }
    }

    /// How many points of a line, and midpoints between them, fall inside the label.
    static func crossings(_ l: Label, _ line: [(x: Double, y: Double)]) -> Int {
        var n = 0
        for (k, p) in line.enumerated() {
            if l.contains(p.x, p.y) { n += 1 }
            if k > 0 {
                let q = line[k - 1]
                for t in [0.25, 0.5, 0.75] where l.contains(q.x + (p.x - q.x) * t, q.y + (p.y - q.y) * t) { n += 1 }
            }
        }
        return n
    }
}
