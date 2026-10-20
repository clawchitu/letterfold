import Foundation

/// A stretch of the leaning window where the shadows lock onto gaps (fold degrees, inclusive).
public struct LockWindow: Sendable, Equatable {
    public var lo, hi: Double
    public let cells: [Cell]
    public init(lo: Double, hi: Double, cells: [Cell]) { self.lo = lo; self.hi = hi; self.cells = cells }
    /// Where a page let go inside the window comes to rest (a whole degree, so the reading is steady).
    public var mid: Double { ((lo + hi) / 2).rounded() }
    public func contains(_ a: Double) -> Bool { a >= lo && a <= hi }
}

/// The pure rules: a 1:1 port of fold-proto/logic.js (same names where possible).
/// The sheet is W = 2N columns wide; the hinge sits between column N-1 and N.
/// Folding the right half onto the left maps column c -> mirror(c) = W-1-c.
public struct Rules: Sendable {
    public let config: FoldConfig
    public init(_ config: FoldConfig = .standard) { self.config = config }
    public var n: Int { config.columnsPerPage }

    public func mirror(_ c: Int) -> Int { 2 * n - 1 - c }
    /// The column on the left page that a cell stacks onto when closed.
    public func proj(_ c: Int) -> Int { c < n ? c : mirror(c) }
    public func isRight(_ c: Int) -> Bool { c >= n }
    public func posture(_ a: Double) -> Posture { config.posture(for: a) }

    /// JavaScript's Math.round (half rounds towards +infinity), so shadows land on the same cells as on the web.
    @inline(__always) static func jsRound(_ x: Double) -> Int { Int((x + 0.5).rounded(.down)) }

    // MARK: shadows

    /// A stone d cells from the hinge on the leaning right page shades the left cell round(d * -cos a) from the hinge.
    public func shadowOffset(_ d: Int, _ a: Double) -> Int { Rules.jsRound(Double(d) * -cos((a * Double.pi) / 180)) }
    /// The left-page column shaded by a stone in right-page column c, or -1.
    public func shadowColumn(_ c: Int, _ a: Double) -> Int {
        let e = shadowOffset(c - n + 1, a)
        return e < 1 ? -1 : n - e
    }
    /// Shadowed left-page cells -> the source stone's column. Empty unless shadeMin <= a < foldMin.
    public func shadows(_ b: Board, _ a: Double) -> [Cell: Int] {
        var out: [Cell: Int] = [:]
        if a < config.shadeMin || a >= config.foldMin { return out }
        for r in 0..<b.h {
            for c in n..<(2 * n) where b[c, r].isOpaque {
                let q = shadowColumn(c, a)
                if q >= 0 && out[Cell(q, r)] == nil { out[Cell(q, r)] = c }
            }
        }
        return out
    }

    // MARK: movement

    /// Walkable stacked position (q in 0..<N) when closed.
    public func foldOpen(_ b: Board, _ q: Int, _ r: Int) -> Bool {
        let L = b[q, r], R = b[mirror(q), r]
        if L.isBlock || R.isBlock { return false }
        return L.isFloor || R.isFloor
    }

    /// The actual cell the character lands on when entering stack q from fromC: stay on this page if possible.
    public func land(_ b: Board, _ fromC: Int, _ q: Int, _ r: Int) -> Cell {
        let here = isRight(fromC) ? mirror(q) : q
        if b[here, r].isFloor { return Cell(here, r) }
        return Cell(isRight(fromC) ? q : mirror(q), r)
    }

    static let dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]

    /// Neighbours while open: no crease crossing, except standing tabs; shadows are floor.
    public func openNeighbours(_ b: Board, _ c: Int, _ r: Int, _ p: Posture, _ sh: [Cell: Int]) -> [Cell] {
        var out: [Cell] = []
        for (dc, dr) in Rules.dirs {
            let nc = c + dc, nr = r + dr
            if nc < 0 || nc >= b.w || nr < 0 || nr >= b.h { continue }
            let crosses = (c == n - 1 && nc == n) || (c == n && nc == n - 1)
            if crosses {
                if p == .standing && b[c, r] == .tab && b[nc, nr] == .tab { out.append(Cell(nc, nr)) }
                continue
            }
            let t = b[nc, nr]
            if t.isFloor || (sh[Cell(nc, nr)] != nil && !t.isBlock) { out.append(Cell(nc, nr)) }
        }
        return out
    }

    /// Closing drops the right page's stones onto their mirror cells: a character on the left page under one
    /// is crushed (design-review-ch3 §2). A ridden shadow ends in that same cell, so the two readings agree.
    /// Stones on the left page never move, so standing on the right page above one only blocks, never crushes —
    /// unless you stand on glue: then the stone below is pulled up onto your square (design-v2c1.md §1).
    public func crushed(_ b: Board, _ from: Cell, _ a: Double) -> Bool {
        a >= config.foldMin && b[mirror(from.c), from.r].isOpaque && (!isRight(from.c) || b[from] == .glue)
    }

    /// Standing on nothing but a shadow? The shadow carries the character. nil means it falls (or is crushed).
    public func ride(_ b: Board, _ from: Cell, _ src: Int?, _ a: Double) -> Cell? {
        if crushed(b, from, a) { return nil }
        if b[from].isFloor { return from }
        guard let src else { return nil }
        let q = shadowColumn(src, a)
        if q < 0 || a >= config.foldMin || b[q, from.r].isBlock { return nil }
        return Cell(q, from.r)
    }

    /// One step from `from` in posture p (sh = shadows(b, angle)).
    public func neighbours(_ b: Board, _ from: Cell, _ p: Posture, _ sh: [Cell: Int]) -> [Cell] {
        if p != .closed { return openNeighbours(b, from.c, from.r, p, sh) }
        let q = proj(from.c)
        var out: [Cell] = []
        for (dq, dr) in Rules.dirs {
            let nq = q + dq, nr = from.r + dr
            if nq < 0 || nq >= n || nr < 0 || nr >= b.h { continue }
            if foldOpen(b, nq, nr) { out.append(land(b, from.c, nq, nr)) }
        }
        return out
    }

    /// BFS from `from` to `target`. Closed, the target matches by stack (proj(c), r). [] = already there, nil = unreachable.
    public func findPath(_ b: Board, from: Cell, to target: Cell, _ p: Posture, _ sh: [Cell: Int]) -> [Cell]? {
        func key(_ x: Cell) -> Cell { p == .closed ? Cell(proj(x.c), x.r) : x }
        let goal = key(target), startK = key(from)
        if startK == goal { return [] }
        var prev: [Cell: Cell] = [:], cell: [Cell: Cell] = [startK: from]
        var seen: Set<Cell> = [startK]
        var queue = [from], head = 0
        while head < queue.count {
            let cur = queue[head]; head += 1
            for nb in neighbours(b, cur, p, sh) {
                let k = key(nb)
                if seen.contains(k) { continue }
                seen.insert(k); prev[k] = key(cur); cell[k] = nb
                if k == goal {
                    var path: [Cell] = [], at = k
                    while at != startK { path.insert(cell[at]!, at: 0); at = prev[at]! }
                    return path
                }
                queue.append(nb)
            }
        }
        return nil
    }

    /// Every cell reachable from `from` right now.
    public func reachable(_ b: Board, from: Cell, _ p: Posture, _ sh: [Cell: Int]) -> Set<Cell> {
        var seen: Set<Cell> = [from], queue = [from], head = 0
        while head < queue.count {
            let cur = queue[head]; head += 1
            for nb in neighbours(b, cur, p, sh) where !seen.contains(nb) { seen.insert(nb); queue.append(nb) }
        }
        return seen
    }

    // MARK: pressing the pages together

    public struct Stamp: Sendable, Equatable {
        public enum Kind: String, Sendable { case door, ink, glue }
        public var kind: Kind
        /// door / ink: [source, target]. glue: [the stone's old cell, the glue cell it lands on].
        public var cells: [Cell]
    }

    /// Keys open the door they touch; wet ink prints onto bare paper; glue pulls the stone it touches onto itself (the
    /// stone changes page, its old square becomes paper, the glue is used up). Mutates the board.
    @discardableResult
    public func stamp(_ b: inout Board) -> [Stamp] {
        var events: [Stamp] = []
        for r in 0..<b.h {
            for q in 0..<n {
                let m = mirror(q)
                for (a, c) in [(q, m), (m, q)] {
                    let A = b.grid[r][a], B = b.grid[r][c]
                    if A == .key && B == .door {
                        b.grid[r][a] = .paper; b.grid[r][c] = .openDoor
                        events.append(Stamp(kind: .door, cells: [Cell(a, r), Cell(c, r)]))
                    } else if A == .ink && B == .empty {
                        b.grid[r][c] = .ink
                        events.append(Stamp(kind: .ink, cells: [Cell(a, r), Cell(c, r)]))
                    } else if A == .glue && B == .stone {
                        b.grid[r][a] = .stone; b.grid[r][c] = .paper
                        events.append(Stamp(kind: .glue, cells: [Cell(c, r), Cell(a, r)]))
                    }
                }
            }
        }
        return events
    }

    // MARK: the shadow lock (design-review-ch3 §3, judged as rewritten in design-review-ch4 §2 / design-spec §5)

    /// The shadows that lie on gaps (bare squares of the bottom page) at fold angle `a`. Shadows on paper or on a
    /// stone do not count.
    public func gapShadows(_ b: Board, _ a: Double) -> [Cell] {
        shadows(b, a).keys.filter { !isRight($0.c) && b[$0] == .empty }.sorted { ($0.r, $0.c) < ($1.r, $1.c) }
    }

    /// Locked = at least one shadow lies on a gap, and every such shadow is connected to what the figure standing at
    /// `from` can reach right now (the shadow joins the path). Returns the locked gaps, or nil.
    public func lockCells(_ b: Board, from: Cell, _ a: Double) -> [Cell]? {
        guard a >= config.shadeMin && a < config.foldMin else { return nil }
        let gaps = gapShadows(b, a)
        guard !gaps.isEmpty else { return nil }
        let r = reachable(b, from: from, posture(a), shadows(b, a))
        return gaps.allSatisfy(r.contains) ? gaps : nil
    }

    /// Every stretch of the leaning window (fold shadeMin..<foldMin, sampled every `step`°) where the shadows lock,
    /// for a figure standing at `from`. Consecutive samples with the same gaps merge into one window.
    public func lockWindows(_ b: Board, from: Cell, step: Double = 0.25) -> [LockWindow] {
        var out: [LockWindow] = []
        var a = config.shadeMin
        while a < config.foldMin {
            if let cells = lockCells(b, from: from, a) {
                if let last = out.last, last.cells == cells, abs(last.hi - (a - step)) < 1e-6 { out[out.count - 1].hi = a }
                else { out.append(LockWindow(lo: a, hi: a, cells: cells)) }
            }
            a += step
        }
        return out
    }

    public func isWin(_ b: Board, _ ch: Cell, _ p: Posture) -> Bool {
        if b[ch] == .goal { return true }
        return p == .closed && b[mirror(ch.c), ch.r] == .goal
    }
}
