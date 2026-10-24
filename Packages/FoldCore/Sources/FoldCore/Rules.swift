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

    /// Why the book crushed the figure at `from` (fold-proto e613f80 `crushCause`): `.glue` when it stood on top-page
    /// glue and the glue pulled the stone below up onto its square, `.stone` when a top-page stone came down on it.
    public enum CrushCause: String, Sendable { case glue, stone }
    public func crushCause(_ b: Board, _ from: Cell, _ a: Double) -> CrushCause? {
        guard crushed(b, from, a) else { return nil }
        return isRight(from.c) ? .glue : .stone
    }

    /// Why a square cannot be entered or a step is refused (fold-proto e613f80 `cellBlock` / `stepBlock` / `pathBlock`).
    /// `card`: shut, a page lies on a stone. `crease`: open, the pages only join when shut or on standing tabs.
    public enum Block: String, Sendable { case edge, stone, card, door, gap, crease }
    /// A blocker and where it is: `c` is the actual column open, the bottom-page (stack) column shut.
    public struct Blocker: Sendable, Equatable {
        public let why: Block; public let c: Int; public let r: Int
        public init(_ why: Block, _ c: Int, _ r: Int) { self.why = why; self.c = c; self.r = r }
    }

    /// Why the square (c, r) cannot be entered in posture p (shut: its stack), or nil if it can.
    public func cellBlock(_ b: Board, _ c: Int, _ r: Int, _ p: Posture, _ sh: [Cell: Int]) -> Block? {
        if r < 0 || r >= b.h || c < 0 || c >= b.w { return .edge }
        if p == .closed {
            let q = proj(c), L = b[q, r], R = b[mirror(q), r]
            if foldOpen(b, q, r) { return nil }
            if R == .stone || (L == .stone && !R.isFloor) { return .stone }
            if L == .stone { return .card }
            if L == .door || R == .door { return .door }
            return .gap
        }
        let t = b[c, r]
        if t == .stone { return .stone }
        if t == .door { return .door }
        if t.isFloor || sh[Cell(c, r)] != nil { return nil }
        return .gap
    }

    /// Why one step (dc, dr) from `from` is refused, or nil if it is allowed. Shut, dc moves along the stacks.
    public func stepBlock(_ b: Board, _ from: Cell, _ dc: Int, _ dr: Int, _ p: Posture, _ sh: [Cell: Int]) -> Blocker? {
        func col(_ x: Cell) -> Int { p == .closed ? proj(x.c) : x.c }
        if neighbours(b, from, p, sh).contains(where: { col($0) == col(from) + dc && $0.r == from.r + dr }) { return nil }
        let c = col(from) + dc, r = from.r + dr
        if r < 0 || r >= b.h || c < 0 || c >= (p == .closed ? n : b.w) { return Blocker(.edge, c, r) }
        if p != .closed && ((from.c == n - 1 && dc == 1) || (from.c == n && dc == -1)) { return Blocker(.crease, c, r) }
        return Blocker(cellBlock(b, c, r, p, sh) ?? .gap, c, r)
    }

    /// Why the figure at `from` cannot walk to `target`: the target itself, or else the blocker on the edge of what it
    /// can reach that lies closest to the target (doors, cards and stones before the crease and gaps on a tie).
    /// nil if a path exists.
    public func pathBlock(_ b: Board, from: Cell, to target: Cell, _ p: Posture, _ sh: [Cell: Int]) -> Blocker? {
        if findPath(b, from: from, to: target, p, sh) != nil { return nil }
        func col(_ c: Int) -> Int { p == .closed ? proj(c) : c }
        if let own = cellBlock(b, target.c, target.r, p, sh) { return Blocker(own, col(target.c), target.r) }
        func key(_ x: Cell) -> Cell { Cell(col(x.c), x.r) }
        var seen: Set<Cell> = [key(from)], queue = [from], head = 0
        var cands: [Blocker] = []
        while head < queue.count {
            let cur = queue[head]; head += 1
            for nb in neighbours(b, cur, p, sh) where seen.insert(key(nb)).inserted { queue.append(nb) }
            for (dc, dr) in Rules.dirs {
                if let x = stepBlock(b, cur, dc, dr, p, sh), x.why != .edge { cands.append(x) }
            }
        }
        let rank: [Block: Int] = [.door: 0, .card: 1, .stone: 2, .crease: 3, .gap: 4]
        func dist(_ x: Blocker) -> Int { abs(x.c - col(target.c)) + abs(x.r - target.r) }
        let best = cands.enumerated().min { l, m in
            (dist(l.element), rank[l.element.why]!, l.offset) < (dist(m.element), rank[m.element.why]!, m.offset)
        }
        return best?.element ?? Blocker(.gap, col(target.c), target.r)
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
        // The search runs over real cells — closed, the page you stand on decides where the next step lands (`land`),
        // so reaching a stack on one page is not the same as reaching it on the other (playtest 10/20: tap-to-walk
        // refused routes single steps allowed). Only the target matches by stack.
        func key(_ x: Cell) -> Cell { p == .closed ? Cell(proj(x.c), x.r) : x }
        let goal = key(target)
        if key(from) == goal { return [] }
        var prev: [Cell: Cell] = [:]
        var seen: Set<Cell> = [from]
        var queue = [from], head = 0
        while head < queue.count {
            let cur = queue[head]; head += 1
            for nb in neighbours(b, cur, p, sh) where seen.insert(nb).inserted {
                prev[nb] = cur
                if key(nb) == goal {
                    var path: [Cell] = [], at = nb
                    while at != from { path.insert(at, at: 0); at = prev[at]! }
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
                    let A = b[a, r], B = b[c, r]
                    if A == .key && B == .door {
                        b[a, r] = .paper; b[c, r] = .openDoor
                        events.append(Stamp(kind: .door, cells: [Cell(a, r), Cell(c, r)]))
                    } else if A == .ink && B == .empty {
                        b[c, r] = .ink
                        events.append(Stamp(kind: .ink, cells: [Cell(a, r), Cell(c, r)]))
                    } else if A == .glue && B == .stone {
                        b[a, r] = .stone; b[c, r] = .paper
                        events.append(Stamp(kind: .glue, cells: [Cell(c, r), Cell(a, r)]))
                    }
                }
            }
        }
        return events
    }

    // MARK: turning the page (vol. 2 ch. 6 「翻」, logic.js flipBlock / flip)

    /// Why the book cannot be turned over: no third page, not closed, or the figure stands on the right leaf.
    public enum FlipBlock: String, Sendable { case single, open, leaf }
    public func flipBlock(_ b: Board, _ char: Cell, _ a: Double) -> FlipBlock? {
        if b.pages < 3 { return .single }
        if a < config.foldMin { return .open }
        if isRight(char.c) { return .leaf }
        return nil
    }

    /// Turn the closed book over: the other face of the right leaf presses on the left page. The press stamps as a close
    /// does; `crush` is what the new facing page did to the figure, judged before the stamp (the caller sends it home).
    @discardableResult
    public func flip(_ b: inout Board, _ char: Cell) -> (stamps: [Stamp], crush: CrushCause?) {
        b.face ^= 1
        let crush = crushCause(b, char, config.foldMin)
        return (stamp(&b), crush)
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
