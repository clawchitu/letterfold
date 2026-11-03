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
    /// Lamp on the left bank (logic.js `shadowColumnL`): a left-page stone d cells from the hinge shades the lifted
    /// page's cell round(d * -cos a) from the hinge — the mirror of shadowColumn; closed, the stone's mirror cell.
    public func shadowColumnL(_ c: Int, _ a: Double) -> Int {
        let e = shadowOffset(n - c, a)
        return e < 1 ? -1 : n - 1 + e
    }
    /// The lean window (logic.js `lit`): shadows are cast and angle gates stand open.
    public func lit(_ a: Double) -> Bool { a >= config.shadeMin && a < config.foldMin }
    /// The `shadows` value of an open angle gate (logic.js maps it to 'A'): no stone casts it.
    public static let gateSource = -1
    /// Whether the angle gate at `c` stands open (walkable): any shadow entry does, a stone's shadow landing on it
    /// (two lamps) as much as `gateSource` — the entry, not its source, is what makes it floor (Codex review 20 #1).
    public static func gateStands(_ shadows: [Cell: Int], _ c: Cell) -> Bool { shadows[c] != nil }

    /// Everything that is floor only while the page leans (logic.js `shadows`): cell -> the column of the stone that
    /// shades it (right-page stones onto the left page under the right lamp, then left-page stones onto the facing page
    /// under the left lamp, first come first served), then each open angle gate -> `Rules.gateSource`. Empty unless lit.
    public func shadows(_ b: Board, _ a: Double) -> [Cell: Int] {
        var out: [Cell: Int] = [:]
        if !lit(a) { return out }
        let right = b.lamp.contains("R"), left = b.lamp.contains("L")
        for r in 0..<b.h {
            if right {
                for c in n..<b.w where b[c, r].isOpaque {   // trifold face 0: the third page's stones shade too (logic.js vw)
                    let q = shadowColumn(c, a)
                    if q >= 0 && out[Cell(q, r)] == nil { out[Cell(q, r)] = c }
                }
            }
            if left {
                for c in stride(from: n - 1, through: 0, by: -1) where b[c, r].isOpaque {
                    let q = shadowColumnL(c, a)
                    if q >= 0 && out[Cell(q, r)] == nil { out[Cell(q, r)] = c }
                }
            }
            for c in 0..<(2 * n) where b[c, r] == .gate && out[Cell(c, r)] == nil { out[Cell(c, r)] = Rules.gateSource }
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
        if c < 0 { return out }   // trifold face 2: on the left page, aside from the third page's book — out of reach
        for (dc, dr) in Rules.dirs {
            let nc = c + dc, nr = r + dr
            if nc < 0 || nc >= b.w || nr < 0 || nr >= b.h { continue }
            if (c == 2 * n - 1 && nc == 2 * n) || (c == 2 * n && nc == 2 * n - 1) { continue }   // trifold face 0: the second crease
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
    /// `.off` (vol. 3 ch. 12): the book closed with the third page lying open and the figure on it — it swung out past
    /// the left page's outer edge and lies face down on the table (logic.js `offBook`).
    public enum CrushCause: String, Sendable { case glue, stone, off }
    public func crushCause(_ b: Board, _ from: Cell, _ a: Double) -> CrushCause? {
        if offBook(b, from, a) { return .off }
        guard crushed(b, from, a) else { return nil }
        return isRight(from.c) ? .glue : .stone
    }
    /// Trifold face 0 (logic.js `offBook`): the book closes with the third page flat — whoever stands on it goes with it.
    public func offBook(_ b: Board, _ from: Cell, _ a: Double) -> Bool {
        a >= config.foldMin && b.trifold && b.face == 0 && from.c >= 2 * n
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
        if r < 0 || r >= b.h || c < 0 || c >= b.w || (p == .closed && c >= 2 * n) { return .edge }
        if p == .closed {
            let q = proj(c), L = b[q, r], R = b[mirror(q), r]
            if foldOpen(b, q, r) { return nil }
            if R.isOpaque || (L.isOpaque && !R.isFloor) { return .stone }
            if L.isOpaque { return .card }
            if L == .door || R == .door || L == .gate || R == .gate { return .door }
            return .gap
        }
        let t = b[c, r]
        if t.isOpaque { return .stone }
        if t == .door || (t == .gate && sh[Cell(c, r)] == nil) { return .door }
        if t.isFloor || sh[Cell(c, r)] != nil { return nil }
        return .gap
    }

    /// Why one step (dc, dr) from `from` is refused, or nil if it is allowed. Shut, dc moves along the stacks.
    public func stepBlock(_ b: Board, _ from: Cell, _ dc: Int, _ dr: Int, _ p: Posture, _ sh: [Cell: Int]) -> Blocker? {
        func col(_ x: Cell) -> Int { p == .closed ? proj(x.c) : x.c }
        if neighbours(b, from, p, sh).contains(where: { col($0) == col(from) + dc && $0.r == from.r + dr }) { return nil }
        let c = col(from) + dc, r = from.r + dr
        if r < 0 || r >= b.h || c < 0 || c >= (p == .closed ? n : b.w) { return Blocker(.edge, c, r) }
        if p != .closed && ((from.c == n - 1 && dc == 1) || (from.c == n && dc == -1) || (from.c == 2 * n - 1 && dc == 1) || (from.c == 2 * n && dc == -1)) { return Blocker(.crease, c, r) }   // trifold: the second crease too
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
    /// On an angle gate the figure stays while the lean lasts and falls when it ends (the flap lies down). The formula
    /// follows the page the source stone is on (ch. 8: left-page stones shade the lifted page).
    public func ride(_ b: Board, _ from: Cell, _ src: Int?, _ a: Double) -> Cell? {
        if from.c < 0 { return from }   // trifold face 2: on the left page, beside the third page's book — nothing there moves
        if crushed(b, from, a) || offBook(b, from, a) { return nil }
        if b[from].isFloor { return from }
        if b[from] == .gate { return lit(a) ? from : nil }
        guard let src, src != Rules.gateSource else { return nil }
        let q = isRight(src) ? shadowColumn(src, a) : shadowColumnL(src, a)
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
        public enum Kind: String, Sendable { case door, ink, glue, bleed, crane, crack, freeze }
        public var kind: Kind
        /// door / ink: [source, target]. glue: [the stone's old cell, the glue cell it lands on]. bleed: every square the
        /// wet ink spread onto in this press (one ring).
        public var cells: [Cell]
        /// ink: the print is wet ink (logic.js `{ type: 'ink', wet: true }`).
        public var wet: Bool = false
        /// bleed: what each of `cells` was before the ink covered it (`.empty` or `.glue`), logic.js `cells[].was`.
        public var was: [Tile] = []
        /// crack (vol. 4 ch. 13): every ice / water square a stone came down on (a gap now, for good). freeze: every water
        /// square that froze back at the end of the press.
        /// crane (vol. 3 ch. 10): `cells` = [the crane, its landing] — or [the crane] alone when it was soaked (`inked`).
        /// `glued`: it landed on glue — it carried over one last time and both squares are plain paper.
        public var inked: Bool = false
        public var glued: Bool = false
        /// crane: where whoever stood on `cells[0]` is carried (logic.js crane event `to`), nil when soaked.
        public var to: Cell? { kind == .crane && !inked && cells.count == 2 ? cells[1] : nil }
        public init(kind: Kind, cells: [Cell], wet: Bool = false, was: [Tile] = [], inked: Bool = false, glued: Bool = false) {
            self.kind = kind; self.cells = cells; self.wet = wet; self.was = was; self.inked = inked; self.glued = glued
        }
    }

    /// Wet ink (vol. 2 ch. 7 「墨晕」, logic.js `bleed`): each wet square on the two pressed pages (a snapshot taken
    /// first) spreads into the gap and glue squares beside it on its own page — paper, stones, doors, the hinge and the
    /// page edge stop it; glue it covers is spoiled. One ring per press: new squares do not spread again this press.
    /// Returns the new squares in logic.js order, with what they were. Mutates the board.
    @discardableResult
    public func bleed(_ b: inout Board) -> (cells: [Cell], was: [Tile]) {
        var wet: [Cell] = []
        for r in 0..<b.h { for c in 0..<(2 * n) where b[c, r] == .wetInk { wet.append(Cell(c, r)) } }   // only the two pressed pages (trifold)
        var cells: [Cell] = [], was: [Tile] = [], seen: Set<Cell> = []
        for w in wet {
            for (dc, dr) in Rules.dirs {
                let nc = w.c + dc, nr = w.r + dr, k = Cell(nc, nr)
                if nc < 0 || nc >= 2 * n || nr < 0 || nr >= b.h || isRight(nc) != isRight(w.c) || seen.contains(k) { continue }
                let t = b[nc, nr]
                if t == .empty || t == .glue { seen.insert(k); b[nc, nr] = .wetInk; cells.append(k); was.append(t) }
            }
        }
        return (cells, was)
    }

    /// Wet ink bleeds a ring first (a `.bleed` event before all others); then keys open the door they touch, ink (dry or
    /// wet) prints itself onto the gap it touches, glue pulls the stone it touches onto itself (the stone changes page,
    /// its old square becomes paper, the glue is used up). Mutates the board.
    @discardableResult
    public func stamp(_ b: inout Board) -> [Stamp] {
        var events: [Stamp] = []
        let bled = bleed(&b)
        if !bled.cells.isEmpty { events.append(Stamp(kind: .bleed, cells: bled.cells, was: bled.was)) }
        let cracked = crushIce(&b)   // vol. 4 ch. 13: the stones come down on the ice before anything is glued or printed
        if !cracked.isEmpty { events.append(Stamp(kind: .crack, cells: cracked)) }
        for r in 0..<b.h {
            for q in 0..<n {
                let m = mirror(q)
                for (a, c) in [(q, m), (m, q)] {
                    let A = b[a, r], B = b[c, r]
                    if A == .key && B == .door {
                        b[a, r] = .paper; b[c, r] = .openDoor
                        events.append(Stamp(kind: .door, cells: [Cell(a, r), Cell(c, r)]))
                    } else if (A == .ink || A == .wetInk) && B == .empty {
                        b[c, r] = A
                        events.append(Stamp(kind: .ink, cells: [Cell(a, r), Cell(c, r)], wet: A == .wetInk))
                    } else if A == .glue && B.isOpaque {   // a loose stone the glue takes is held: it arrives as a stone
                        b[a, r] = .stone; b[c, r] = .paper
                        events.append(Stamp(kind: .glue, cells: [Cell(c, r), Cell(a, r)]))
                    }
                }
            }
        }
        events += fly(&b)   // vol. 3 ch. 10: last of all, the cranes fly (after the roll of the sweep, the bleed, the keys, the ink, the glue)
        let froze = freeze(&b)   // vol. 4 ch. 13: closed, the river is frozen (the lamp is shut out) — unless it is spring (thaw)
        if !froze.isEmpty { events.append(Stamp(kind: .freeze, cells: froze)) }
        return events
    }

    // MARK: ice (vol. 4 ch. 13 「冰」, fold-proto design-ch13.md §1, logic.js litCols / melt / freeze / crushIce / meltCause)

    /// The lit page's visible columns: under the right-bank lamp the flat LEFT page (the lifted page's stones shade it);
    /// under the left-bank lamp the LIFTED page; two lamps light both. The page that faces away from its lamp never melts.
    public func litCols(_ b: Board) -> [Int] {
        var out: [Int] = []
        if b.lamp.contains("R") { out += Array(0..<n) }
        if b.lamp.contains("L") { out += Array(n..<b.w) }
        return out
    }

    /// The page came to REST at fold angle `a` (the finger let go and the page settled; the solver: a sampled angle was
    /// reached). In the lamp window every ice square on the lit page that no shadow covers melts: `.ice` → `.water`. Moving
    /// through the window melts nothing — only the rest does. `noShelter` is the player model in which shadows do not
    /// protect the ice (check.js needsShelter). Returns the melted cells (row by row, lit columns in order). Mutates the board.
    @discardableResult
    public func melt(_ b: inout Board, _ a: Double, noShelter: Bool = false) -> [Cell] {
        guard lit(a) else { return [] }
        let sh = noShelter ? [:] : shadows(b, a)
        var out: [Cell] = []
        let cols = litCols(b)
        for r in 0..<b.h { for c in cols where b[c, r] == .ice && sh[Cell(c, r)] == nil {
            b[c, r] = .water; out.append(Cell(c, r))
        } }
        return out
    }

    /// The water that would melt if the page rested at `a` now (the UI's mist before the rest lands). Does not mutate.
    public func wouldMelt(_ b: Board, _ a: Double) -> [Cell] { var w = b; return melt(&w, a) }

    /// Laid flat (or pressed), the water freezes back into ice: `.water` → `.ice` on every page (raw grid). Spring
    /// (`Board.thaw`) skips it. Returns the frozen cells (grid columns). Mutates the board.
    @discardableResult
    public func freeze(_ b: inout Board) -> [Cell] {
        guard !b.thaw else { return [] }
        var out: [Cell] = []
        for r in 0..<b.h { for c in 0..<b.grid[r].count where b.grid[r][c] == .water { b.grid[r][c] = .ice; out.append(Cell(c, r)) } }
        return out
    }

    /// The press: every stone (fixed or loose) facing ice or water crushes it — the square is a gap from then on (`.empty`).
    /// Read through the visible columns, so after a turn it is the third page's stones that crush. Returns the crushed
    /// cells. Mutates the board.
    @discardableResult
    public func crushIce(_ b: inout Board) -> [Cell] {
        var out: [Cell] = []
        for r in 0..<b.h { for q in 0..<n {
            let m = mirror(q), L = b[q, r], R = b[m, r]
            if R.isOpaque && (L == .ice || L == .water) { b[q, r] = .empty; out.append(Cell(q, r)) }
            else if L.isOpaque && (R == .ice || R == .water) { b[m, r] = .empty; out.append(Cell(m, r)) }
        } }
        return out
    }

    /// After a melt: did the figure's own square turn to water? (logic.js `meltCause` — 'melt'.)
    public func meltedUnder(_ b: Board, _ fig: Cell) -> Bool { b[fig] == .water }

    /// Paper crane (vol. 3 ch. 10 「鹤」, logic.js `fly`): at every press each crane flies to its mirror cell, all of them
    /// listed on the board as it is after the glue and judged one by one in reading order. Paper or a gap: it lands there
    /// (its old square is paper). Wet ink: it is soaked — it stays, as wet ink, and never flies again. Glue: it is stuck —
    /// it carries over one last time and both squares are plain paper. Anything else (a stone, a loose stone, a door, a
    /// key, dry ink, her square, the start, another crane): it cannot fly. Mutates the board.
    public func fly(_ b: inout Board) -> [Stamp] {
        var cranes: [Cell] = [], events: [Stamp] = []
        for r in 0..<b.h { for c in 0..<(2 * n) where b[c, r] == .crane { cranes.append(Cell(c, r)) } }   // only the two pressed pages (trifold)
        for x in cranes {
            let m = mirror(x.c), t = b[m, x.r]
            if t == .empty || t == .paper {
                b[m, x.r] = .crane; b[x.c, x.r] = .paper
                events.append(Stamp(kind: .crane, cells: [x, Cell(m, x.r)]))
            } else if t == .wetInk {
                b[x.c, x.r] = .wetInk
                events.append(Stamp(kind: .crane, cells: [x], inked: true))
            } else if t == .glue {
                b[m, x.r] = .paper; b[x.c, x.r] = .paper
                events.append(Stamp(kind: .crane, cells: [x, Cell(m, x.r)], glued: true))
            }
        }
        return events
    }

    /// Where the figure stands after a press (logic.js `carried`): carried by the crane it stood on, or where it was.
    public func carried(_ events: [Stamp], _ fig: Cell) -> Cell {
        events.first { $0.kind == .crane && $0.cells[0] == fig }?.to ?? fig
    }

    // MARK: loose stones (vol. 3 ch. 9 「滚」, logic.js STAND / standing / passes / roll)

    /// The lifted page is upright or past it: loose stones roll when the hinge crosses this (logic.js STAND).
    public static let stand = 90.0
    public func standing(_ a: Double) -> Bool { a >= Rules.stand }
    /// The hinge moved from a0 to a1: did the lifted page pass upright (so loose stones roll)?
    public func passes(_ a0: Double, _ a1: Double) -> Bool { standing(a0) != standing(a1) }

    /// One loose stone's roll: `from` -> `to` (one cell towards the crease); `filled` = it dropped into a gap, which is
    /// paper from then on (the stone is gone).
    ///
    /// Vol. 4 ch. 14 「滑」 (logic.js roll, design-ch14.md §1): `slid` = the ice squares it slid across; `sank` = it sank in
    /// water, or broke through the last ice square (`filled` too: the stone is gone and `to` is paper for good).
    public struct Roll: Sendable, Equatable {
        public enum Sank: String, Sendable { case water, ice }
        public let from: Cell, to: Cell, filled: Bool
        public var slid: Int = 0
        public var sank: Sank? = nil
        public init(from: Cell, to: Cell, filled: Bool, slid: Int = 0, sank: Sank? = nil) {
            self.from = from; self.to = to; self.filled = filled; self.slid = slid; self.sank = sank
        }
    }

    /// The lifted page passed upright: every loose stone on the facing page (read through columns N..<2N, so after a turn
    /// the third page's) rolls one cell towards the crease — onto paper it rolls, into a gap it drops and fills it; against
    /// anything else, or the figure standing crease-side of it (`fig`), it stays. The stone nearest the crease rolls
    /// first, so a line of them rolls together. Left-page stones never roll. Returns the rolls, nearest the crease first.
    /// Mutates the board.
    ///
    /// Vol. 4 ch. 14 「滑」: a stone that rolls onto ICE does not stop. It slides along the continuous ice to the first
    /// square that is not ice: paper stops it (it rests there), a gap it drops into and fills, WATER it sinks in (paper
    /// from then on). Anything else ahead of the ice — a stone, a door, ink, glue, a key, her square, the start, the
    /// figure, the crease — and it breaks through the LAST ice square and sinks (paper too). It never rests on ice; rolling
    /// straight into water sinks it the same way. `noSlide` is the ch. 9 player's model (Solver needsSlide): ice is paper,
    /// water a gap — one square and stop.
    @discardableResult
    public func roll(_ b: inout Board, fig: Cell?, noSlide: Bool = false) -> [Roll] {
        var out: [Roll] = []
        func held(_ c: Int, _ r: Int) -> Bool { if let f = fig { return f.c == c && f.r == r }; return false }
        func moves(_ t: Tile) -> Bool { t == .paper || t == .empty || t == .ice || t == .water }
        for r in 0..<b.h {
            for c in (n + 1)..<b.w where b[c, r] == .loose {   // trifold face 0: the third page rolls with the right page
                if held(c - 1, r) { continue }
                var ahead = b[c - 1, r]
                if noSlide { if ahead == .ice { ahead = .paper } else if ahead == .water { ahead = .empty } }
                guard moves(ahead) else { continue }
                b[c, r] = .paper
                var d = c - 1, slid = 0
                var sank: Roll.Sank?
                while ahead == .ice {   // sliding: the next square is ice too, or something stops the stone on this ice
                    let next: Tile? = d - 1 >= n && !held(d - 1, r) ? b[d - 1, r] : nil
                    if let t = next, moves(t) { d -= 1; slid += 1; ahead = t } else { sank = .ice; break }
                }
                if ahead == .water { sank = .water }
                b[d, r] = ahead == .paper ? .loose : .paper
                out.append(Roll(from: Cell(c, r), to: Cell(d, r), filled: ahead != .paper, slid: slid, sank: sank))
            }
        }
        return out
    }

    // MARK: turning the page (vol. 2 ch. 6 「翻」, logic.js flipBlock / flip)

    /// Why the book cannot be turned over: no third page, not closed, or the figure stands on the right leaf.
    public enum FlipBlock: String, Sendable { case single, open, leaf }
    public func flipBlock(_ b: Board, _ char: Cell, _ a: Double) -> FlipBlock? {
        if b.pages < 3 || b.trifold { return .single }
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
        return (crush == nil ? stamp(&b) : [], crush)
    }

    // MARK: the second crease (vol. 3 ch. 12 「三折」, logic.js flapIn / flapOut / flapBlock)

    /// Taking hold of the third page's crease re-reads the figure in its view (face 2): from face 0, one page to the left;
    /// from face 3 on the folded leaf, on its top layer — the third page where it has paper, the right page through a hole.
    public func flapIn(_ b: Board, _ fig: Cell) -> Cell {
        if b.face == 3 && fig.c >= n { return Cell(b.colOf(fig.c, fig.r) - n, fig.r) }
        return Cell(fig.c - n, fig.r)
    }
    /// The third page reached flat (face 0) or folded (face 3): where the figure stands in that view, or nil when the
    /// folded leaf has a stone under its feet (refused before it gets there: `flapBlock`).
    public func flapOut(_ b: Board, _ fig: Cell, folded: Bool) -> Cell? {
        let c = fig.c + n
        if !folded { return Cell(c, fig.r) }
        let v = c < 2 * n ? c : 4 * n - 1 - c
        var w = b; w.face = 3
        return w[v, fig.r].isFloor ? Cell(v, fig.r) : nil
    }
    /// Why the third page will not fold down (logic.js flapBlock; a refused fold with a toast, never a death):
    /// `.stone` you stand on the lifted third page over a right-page stone (glue under your feet is not a block);
    /// `.cover` you stand on the flat right page and the third page's square coming down over you is paper — it would lie
    /// on you (a hole comes down around you; a stone crushes you, as every press does).
    public enum FlapBlock: String, Sendable { case stone, cover }
    public func flapBlock(_ b: Board, _ fig: Cell) -> FlapBlock? {
        guard b.trifold, b.face == 2, fig.c >= 0 else { return nil }
        if fig.c < n { return b[mirror(fig.c), fig.r].isFloor ? .cover : nil }
        if b[fig] == .glue { return nil }
        return b[mirror(fig.c), fig.r].isBlock ? .stone : nil
    }

    // MARK: the shadow lock (design-review-ch3 §3, judged as rewritten in design-review-ch4 §2 / design-spec §5)

    /// The shadows that lie on gaps (bare squares) at fold angle `a`, on either page: the right lamp shades the bottom
    /// page, the left lamp the lifted one (Codex review 20 #3). Shadows on paper, a stone or a gate do not count.
    public func gapShadows(_ b: Board, _ a: Double) -> [Cell] {
        shadows(b, a).keys.filter { b[$0] == .empty || b[$0] == .water }.sorted { ($0.r, $0.c) < ($1.r, $1.c) }
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
        var a = config.shadeMin, lastSources: [Int?] = [], lastIce: [Cell] = []
        while a < config.foldMin {
            if let cells = lockCells(b, from: from, a) {
                // the same gaps shaded by other stones are another lock: under two lamps a gap can change hands inside
                // one stretch, and resting at the merged middle put 8-7's figure on the wrong stone's shadow
                let sh = shadows(b, a), sources = cells.map { sh[$0] }
                // vol. 4 ch. 13: a lock is also split where the ice it shelters changes, so the page that rests at the
                // window's middle melts what it would have melted where the finger let go
                let iceKey = sh.keys.filter { b[$0] == .ice }.sorted { ($0.r, $0.c) < ($1.r, $1.c) }
                if let last = out.last, last.cells == cells, sources == lastSources, iceKey == lastIce, abs(last.hi - (a - step)) < 1e-6 { out[out.count - 1].hi = a }
                else { out.append(LockWindow(lo: a, hi: a, cells: cells)) }
                lastSources = sources; lastIce = iceKey
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
