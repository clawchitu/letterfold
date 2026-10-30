import Foundation

/// A point of the search: the figure's cell, the hinge angle (fold degrees), which face of the right leaf faces the
/// left page, and `g`, an index into the level's grid chain (check.js keys states the same way: c, r, a, face, g).
/// g > 0 means the book has been closed (the old `st` bit).
struct FoldState: Hashable, Sendable {
    var c: Int; var r: Int; var a: Double; var face: Int = 0; var g: Int = 0
    var st: Int { g > 0 ? 1 : 0 }
}

/// The board's grids as a chain of presses (check.js `grids`): press(g, face) is grid g after the left page is pressed
/// against the page of `face` (a close, or a turn of the closed book). Pressed grids are deduplicated by content among
/// themselves but never with grid 0. Two-page levels without wet ink only ever see g 0 and 1; wet ink grows a ring per press until it saturates.
final class GridChain: @unchecked Sendable {
    private(set) var table: [Board]
    private var sig: [[[Tile]]: Int] = [:]
    private var memo: [Int: Int] = [:]
    let rules: Rules
    var base: Board { table[0] }
    var pages: Int { table[0].pages }
    init(_ base: Board, _ rules: Rules) { var b = base; b.face = 0; table = [b]; self.rules = rules }
    func press(_ g: Int, _ face: Int) -> Int {
        let k = g * 4 + face   // faces 0–1 (ch. 6), 2–3 (trifold, ch. 12)
        if let m = memo[k] { return m }
        var b = table[g]; b.face = face
        let ev = rules.stamp(&b)
        flights[k] = Dictionary(ev.compactMap { e in e.to.map { (e.cells[0], $0) } }, uniquingKeysWith: { a, _ in a })
        b.face = 0
        let idx: Int
        if let i = sig[b.grid] { idx = i } else { idx = table.count; table.append(b); sig[b.grid] = idx }
        memo[k] = idx
        return idx
    }
    /// Vol. 3 ch. 10 (check.js grids().carry): the figure's cell after press(g, face) — carried by the crane it stood on,
    /// or unchanged. The grid a press makes does not depend on where the figure stands, so flights sit beside the memo.
    private var flights: [Int: [Cell: Cell]] = [:]
    func carry(_ g: Int, _ face: Int, _ fig: Cell) -> Cell {
        _ = press(g, face)
        return flights[g * 4 + face]?[fig] ?? fig
    }
    /// The lifted page passed upright (vol. 3 ch. 9, check.js grids().roll): grid g with the loose stones on the page of
    /// `face` rolled, unless the figure holds one. Keyed on the figure's cell only when it stands on the facing page —
    /// on the left page it is in nobody's way. No roll: g itself.
    private struct RollKey: Hashable { let g: Int, face: Int, held: Cell? }
    private var rollMemo: [RollKey: Int] = [:]
    func roll(_ g: Int, _ face: Int, _ fig: Cell) -> Int {
        let held: Cell? = rules.isRight(fig.c) ? fig : nil
        let k = RollKey(g: g, face: face, held: held)
        if let m = rollMemo[k] { return m }
        var b = table[g]; b.face = face
        let ev = rules.roll(&b, fig: held)
        if ev.isEmpty { rollMemo[k] = g; return g }
        b.face = 0
        let idx: Int
        if let i = sig[b.grid] { idx = i } else { idx = table.count; table.append(b); sig[b.grid] = idx }
        rollMemo[k] = idx
        return idx
    }
    /// The board a state sees.
    func world(_ s: FoldState) -> Board { var b = table[s.g]; b.face = s.face; return b }
}

/// Brute-force solver: a port of fold-proto/tools/check.js.
/// The hinge is sampled at a few angles; moving between two samples walks the angle in 5° steps,
/// so a character standing on a shadow rides it (or falls) exactly as in the game.
/// Cost = number of angle changes and page turns, priced by FoldTally (0-1 BFS: steps are free) — the game's 折数.
public struct Solver: Sendable {
    public static let angles: [Double] = [0, 90, 100, 110, 120, 125, 130, 140, 150, 180]
    public static let steps15: [Double] = (0...12).map { Double($0 * 15) }

    public let rules: Rules
    public init(_ config: FoldConfig = .standard) { rules = Rules(config) }

    public struct Step: Sendable, Equatable {
        public var posture: Posture; public var angle: Double; public var cell: Cell
        /// 1 once the book has been closed (the board is the stamped one).
        public var st: Int = 0
        /// Which face of the right leaf faces the left page (vol. 2 ch. 6); a step that only changes it is a turn.
        /// Trifold (ch. 12): 2 = the third page on its own crease (`angle` is its angle), 3 = the book with it folded.
        public var face: Int = 0
        /// The grid chain index of this state (check.js keeps it on the path's states; the metrics read it).
        var g: Int = 0
    }
    public struct Solution: Sendable {
        public var cost: Int
        public var steps: [Step]
        /// Cells walked (state transitions that were not hinge moves), as check.js counts `walk`.
        public var walk: Int { steps.count - 1 - cost }
    }

    /// The player models check.js `move` opts stand for (vol. 3 ch. 11 「来回」). `noFro`: passes roll only on the sweep of
    /// a close or of the opening after one (the ch. 9/10 player's model). `openPass`: every opening of the closed book rolls,
    /// as if it always went flat (a forced roll at the first 5° step of an opening that stays on the closed side of upright).
    public struct Options: Sendable, Equatable {
        public var noFro = false, openPass = false
        /// Vol. 3 ch. 12: the second crease never moves (check.js `noFlap`, the needsTrifold model).
        public var noFlap = false
        public init(noFro: Bool = false, openPass: Bool = false, noFlap: Bool = false) { self.noFro = noFro; self.openPass = openPass; self.noFlap = noFlap }
    }

    /// The character cell after turning the hinge from a0 to a1, or nil if it falls (or is crushed): check.js `turn`.
    public func turn(_ b: Board, _ from: Cell, _ a0: Double, _ a1: Double) -> Cell? {
        var cur = from
        var src: Int?
        let step = a1 > a0 ? 5.0 : -5.0
        var a = a0 + step
        while step > 0 ? a <= a1 : a >= a1 {
            // a figure on nothing but a shadow rides it; on paper under a stone (or on glue facing one) it is crushed
            // a shadow on either page (ch. 8 lamp), or an open angle gate (check.js `onShadow`)
            if !b[cur].isFloor {
                if src == nil { src = rules.shadows(b, a - step)[cur] }
            } else { src = nil }
            guard let to = rules.ride(b, cur, src, a) else { return nil }
            cur = to
            a += step
        }
        return cur
    }

    /// One hinge move (check.js `move`): the state after turning the hinge from s.a to a, or nil if the figure falls or is
    /// crushed. The angle walks in 5° steps and a figure on a shadow rides it; each time the lifted page passes upright
    /// (vol. 3: the hinge crosses 90°) the loose stones roll first — the rest of the sweep (shadows, the crush when the
    /// book closes) is judged on the rolled board. Reaching a close presses the pages after the sweep.
    func move(_ B: GridChain, _ s: FoldState, _ a1: Double, _ opts: Options = Options()) -> FoldState? {
        if case let .to(n) = outcome(B, s, a1, opts) { return n }
        return nil
    }

    /// What one hinge move does (check.js `move`): `.refused` (trifold: a third-page fold that is not allowed here — not a
    /// death), `.dead` (fell or crushed), or the state after it. In the third page's view (face 2) the hinge being turned
    /// is the third page's (flapOf).
    enum Outcome { case refused, dead, to(FoldState) }
    func outcome(_ B: GridChain, _ s: FoldState, _ a1: Double, _ opts: Options = Options()) -> Outcome {
        if s.face == 2 { return flapOf(B, s, a1, opts) }
        return sweep(B, s, a1, opts).map(Outcome.to) ?? .dead
    }

    /// Trifold (vol. 3 ch. 12, check.js flapOf): turning the SECOND crease to b. Only while the book lies flat — from face
    /// 0 (third page flat) or face 3 (folded) at a = 0, or from face 2 (s.a = its angle). The sweep runs in its view (face 2:
    /// right page flat, third page lifted). Reaching flat or folded leaves that view: face 0 / face 3 at a = 0, so a flat
    /// book has one state per third-page posture. A fold over a stone under your feet, or of paper onto you, is refused.
    func flapOf(_ B: GridChain, _ s: FoldState, _ b: Double, _ opts: Options = Options()) -> Outcome {
        guard B.base.trifold, !opts.noFlap else { return .refused }
        let b0: Double? = s.face == 2 ? s.a : s.a != 0 ? nil : s.face == 3 ? 180 : 0
        guard let b0, b != b0 else { return .refused }
        let fm = rules.config.foldMin
        var from = s
        if s.face != 2 {
            let f = rules.flapIn(B.world(s), Cell(s.c, s.r))
            from = FoldState(c: f.c, r: f.r, a: b0, face: 2, g: s.g)
        }
        if b >= fm && rules.flapBlock(B.world(from), Cell(from.c, from.r)) != nil { return .refused }
        guard let n = sweep(B, from, b, opts) else { return .dead }
        // judged again on the rolled board (a stone that rolled off the square over you leaves paper there)
        if b >= fm && rules.flapBlock(B.world(n), Cell(n.c, n.r)) != nil { return .refused }
        if b > 0 && b < fm { return .to(n) }
        guard let out = rules.flapOut(B.world(n), Cell(n.c, n.r), folded: b >= fm) else { return .refused }
        return .to(FoldState(c: out.c, r: out.r, a: 0, face: b >= fm ? 3 : 0, g: n.g))
    }

    /// Every third-page move from s that is not already a move() (check.js flaps): from a flat book only, [dead = nil].
    func flaps(_ B: GridChain, _ s: FoldState, _ angles: [Double] = Solver.angles, _ opts: Options = Options()) -> [FoldState?] {
        guard B.base.trifold, s.face != 2, s.a == 0, !opts.noFlap else { return [] }
        var out: [FoldState?] = []
        for b in angles {
            switch flapOf(B, s, b, opts) {
            case .refused: break
            case .dead: out.append(nil)
            case let .to(n): out.append(n)
            }
        }
        return out
    }

    /// One sweep of the hinge in view (check.js `sweep`).
    func sweep(_ B: GridChain, _ s: FoldState, _ a1: Double, _ opts: Options = Options()) -> FoldState? {
        var cur = Cell(s.c, s.r), g = s.g
        var src: Int?
        var b = B.world(s)
        let step = a1 > s.a ? 5.0 : -5.0
        let fm = rules.config.foldMin
        let rolls = !opts.noFro || a1 >= fm || s.a >= fm
        let forced = opts.openPass && s.a >= fm && a1 < fm && !rules.passes(s.a, a1)
        var a = s.a + step
        while step > 0 ? a <= a1 : a >= a1 {
            if (rolls && rules.passes(a - step, a)) || (forced && a == s.a + step) {
                let ng = B.roll(g, s.face, cur)
                if ng != g { g = ng; b = B.world(FoldState(c: cur.c, r: cur.r, a: a, face: s.face, g: g)) }
                src = nil
            }
            if !b[cur].isFloor {
                if src == nil { src = rules.shadows(b, a - step)[cur] }
            } else { src = nil }
            guard let to = rules.ride(b, cur, src, a) else { return nil }
            cur = to
            a += step
        }
        if a1 >= rules.config.foldMin { cur = B.carry(g, s.face, cur); g = B.press(g, s.face) }   // vol. 3 ch. 10: the crane you stand on carries you across
        return FoldState(c: cur.c, r: cur.r, a: a1, face: s.face, g: g)
    }

    /// The level's grid chain (check.js grids), or nil for a bad map.
    func chain(_ level: Level) -> GridChain? {
        guard let base = try? Board(level: level, columnsPerPage: rules.n) else { return nil }
        return GridChain(base, rules)
    }
    func after(_ B: GridChain, _ s: FoldState, _ a: Double) -> Int { a >= rules.config.foldMin ? B.press(s.g, s.face) : s.g }
    func startOf(_ B: GridChain) -> FoldState { FoldState(c: B.base.start.c, r: B.base.start.r, a: 0, face: 0, g: 0) }

    /// Turning the closed book over (check.js flipOf): `.notAllowed` (open, on the leaf, no third page), `.crushed` (a
    /// stone on the new facing page over the figure), or the state after it.
    enum Flip { case notAllowed, crushed, to(FoldState) }
    func flipOf(_ B: GridChain, _ s: FoldState) -> Flip {
        let w = B.world(s), here = Cell(s.c, s.r)
        if rules.flipBlock(w, here, s.a) != nil { return .notAllowed }
        var turned = w; turned.face ^= 1
        if rules.crushed(turned, here, s.a) { return .crushed }
        let to = B.carry(s.g, s.face ^ 1, here)   // a crane under your feet flies to the page you turned to, with you
        return .to(FoldState(c: to.c, r: to.r, a: s.a, face: s.face ^ 1, g: B.press(s.g, s.face ^ 1)))
    }
    func step(_ s: FoldState) -> Step { Step(posture: rules.posture(s.a), angle: s.a, cell: Cell(s.c, s.r), st: s.st, face: s.face, g: s.g) }

    public func solve(_ level: Level, angles: [Double] = Solver.angles) -> Solution? { solve(level, angles: angles, from: nil) }
    public func solve(_ level: Level, angles: [Double] = Solver.angles, options: Options) -> Solution? { solve(level, angles: angles, from: nil, options: options) }

    /// 0-1 BFS from `from` (default: the level's start, flat, unpressed): angle changes and page turns cost 1, steps 0.
    /// A `from` state's g indexes `chain`, so pass that chain when starting mid-game.
    func solve(_ level: Level, angles: [Double] = Solver.angles, from: FoldState?, chain: GridChain? = nil, noFlip: Bool = false, options: Options = Options()) -> Solution? {
        guard let B = chain ?? self.chain(level) else { return nil }
        let start = from ?? startOf(B)
        var parent: [FoldState: FoldState] = [:]
        var dist: [FoldState: Int] = [start: 0]
        // deque: `front` is a stack (unshift), `back` a queue (push)
        var front: [(FoldState, Int)] = [], back: [(FoldState, Int)] = [(start, 0)], head = 0
        while !front.isEmpty || head < back.count {
            let (s, cost): (FoldState, Int)
            if let f = front.popLast() { (s, cost) = f } else { (s, cost) = back[head]; head += 1 }
            if cost > dist[s]! { continue }
            let p = rules.posture(s.a)
            let b = B.world(s)
            let here = Cell(s.c, s.r)
            if rules.isWin(b, here, p) {
                var chain: [FoldState] = [s], k = s
                while let up = parent[k] { chain.insert(up, at: 0); k = up }
                return Solution(cost: cost, steps: chain.map(step))
            }
            var next: [(FoldState, Int)] = []
            for a in angles where FoldTally.cost(from: s.a, to: a) > 0 {
                if let n = move(B, s, a, options) { next.append((n, FoldTally.cost(from: s.a, to: a))) }
            }
            if !noFlip, case let .to(f) = flipOf(B, s) { next.append((f, FoldTally.turnCost)) }
            for case let f? in flaps(B, s, angles, options) { next.append((f, 1)) }   // trifold: the second crease
            let sh = rules.shadows(b, s.a)
            for nb in rules.neighbours(b, here, p, sh) { next.append((FoldState(c: nb.c, r: nb.r, a: s.a, face: s.face, g: s.g), 0)) }
            for (nState, w) in next {
                if let d = dist[nState], d <= cost + w { continue }
                dist[nState] = cost + w; parent[nState] = s
                if w > 0 { back.append((nState, cost + w)) } else { front.append((nState, cost)) }
            }
        }
        return nil
    }

    /// The shortest solution as tools/gen.js `bestPath` measures it: fewest posture changes (a page turn is one), then
    /// fewest steps (cost 1000 · hinge + 1 · step). `len` = par + steps is the v3 length the tiers gate.
    public func shortest(_ level: Level, angles: [Double] = Solver.angles) -> (par: Int, steps: Int, path: [Step])? {
        guard let B = chain(level) else { return nil }
        let start = startOf(B)
        var dist: [FoldState: Int] = [start: 0], parent: [FoldState: FoldState] = [:], done: Set<FoldState> = []
        var open: [FoldState: Int] = [start: 0]
        while let (s, cost) = open.min(by: { $0.value < $1.value }) {
            open[s] = nil
            if !done.insert(s).inserted { continue }
            let b = B.world(s), here = Cell(s.c, s.r), p = rules.posture(s.a)
            if rules.isWin(b, here, p) {
                var chain = [s], k = s
                while let up = parent[k] { chain.insert(up, at: 0); k = up }
                return (cost / 1000, cost % 1000, chain.map(step))
            }
            var next: [(FoldState, Int)] = []
            for a in angles where FoldTally.cost(from: s.a, to: a) > 0 {
                if let n = move(B, s, a) { next.append((n, 1000 * FoldTally.cost(from: s.a, to: a))) }
            }
            if case let .to(f) = flipOf(B, s) { next.append((f, 1000 * FoldTally.turnCost)) }
            for case let f? in flaps(B, s, angles) { next.append((f, 1000)) }   // trifold: the second crease (gen.js explore)
            for nb in rules.neighbours(b, here, p, rules.shadows(b, s.a)) { next.append((FoldState(c: nb.c, r: nb.r, a: s.a, face: s.face, g: s.g), 1)) }
            for (n, w) in next where !done.contains(n) {
                if let d = dist[n], d <= cost + w { continue }
                dist[n] = cost + w; parent[n] = s; open[n] = cost + w
            }
        }
        return nil
    }

    /// gen.js measure (ch. 11): `passes` = hinge moves of the shortest solution that take the lifted page through upright;
    /// `fros` = leans that come back — two consecutive hinge moves that both pass, no end closed, no turn between (a pair is spent).
    public func passesAndFros(_ level: Level) -> (passes: Int, fros: Int)? {
        guard let path = shortest(level)?.path else { return nil }
        var hinge: [Int] = []
        for i in 1..<max(1, path.count) where path[i].face == path[i - 1].face && path[i].angle != path[i - 1].angle { hinge.append(i) }
        let isPass = { (i: Int) in rules.passes(path[i - 1].angle, path[i].angle) }
        let shut = { (i: Int) in path[i].posture == .closed }
        var fros = 0, k = 0
        while k + 1 < hinge.count {
            let i = hinge[k], j = hinge[k + 1]
            if isPass(i) && isPass(j) && !shut(i - 1) && !shut(i) && !shut(j) && !(i + 1..<j + 1).contains(where: { path[$0].face != path[$0 - 1].face && $0 < j }) { fros += 1; k += 2 } else { k += 1 }
        }
        return (hinge.filter(isPass).count, fros)
    }

    /// Can the goal still be reached from here (the game's dead-end check, design-review-v2c1 §3)? `closedOnce`: the
    /// first close has happened (the board in play is the stamped one).
    public func canStillWin(_ level: Level, from cell: Cell, angle: Double, closedOnce: Bool) -> Bool {
        guard let B = chain(level) else { return false }
        return solve(level, angles: Solver.angles, from: FoldState(c: cell.c, r: cell.r, a: angle, face: 0, g: closedOnce ? B.press(0, 0) : 0), chain: B) != nil
    }

    /// The same, from a live board (vol. 2 ch. 6: after turns the grid is not just "stamped once"). The chain is seeded
    /// with the board as it is now; `closedOnce` keeps g > 0 semantics (a pressed board) for the metrics' sake.
    public func canStillWin(_ level: Level, board: Board, from cell: Cell, angle: Double) -> Bool {
        var b = board; var face = b.face, cell = cell, angle = angle
        // trifold: the third page's view laid flat or folded is the book's flat state (the solver's canonical face 0 / 3)
        if b.trifold && face == 2 && (angle <= 0.5 || angle >= rules.config.foldMin) {
            let folded = angle >= rules.config.foldMin
            if let out = rules.flapOut(b, cell, folded: folded) { cell = out; face = folded ? 3 : 0; angle = 0 }
        }
        b.face = 0
        let B = GridChain(b, rules)
        return solve(level, angles: Solver.angles, from: FoldState(c: cell.c, r: cell.r, a: angle, face: face, g: 0), chain: B) != nil
    }

    /// Everything check.js reports about a level, in the same shape as levels.json `expect`.
    public func report(_ level: Level, withDifficulty: Bool = true) -> Expectation {
        let cfg = rules.config
        let shade = Solver.angles.filter { $0 >= cfg.shadeMin && $0 < cfg.foldMin }
        let full = solve(level)
        let noFold = solve(level, angles: Solver.angles.filter { $0 < cfg.foldMin })
        let noPop = solve(level, angles: Solver.angles.filter { $0 < cfg.popMin || $0 > cfg.popMax })
        let all = level.map.joined()
        func without(_ ch: Character) -> Solution? {
            // like JS row.split(ch).join('.'): every occurrence
            solve(Level(id: level.id, map: level.map.map { String($0.map { $0 == ch ? "." : $0 }) }, lamp: level.lamp, trifold: level.trifold))
        }
        var e = Expectation(solvable: full != nil, changes: full?.cost, needsFold: noFold == nil, needsPop: noPop == nil,
                            stepped15: solve(level, angles: Solver.steps15) != nil)
        func stoneIn(_ x: Substring) -> Bool { x.contains("x") || x.contains("r") }
        if stoneIn(Substring(all)) && (level.map.contains(where: { stoneIn($0.dropFirst(rules.n)) }) || all.contains("g") || (level.lamp ?? "").contains("L")) {
            e.needsShade = solve(level, angles: Solver.angles.filter { !shade.contains($0) }) == nil
            let oneShade = shade.contains { keep in solve(level, angles: Solver.angles.filter { !shade.contains($0) || $0 == keep }) != nil }
            e.needsRide = !oneShade
        }
        if let lamp = level.lamp, lamp != "R" { var r = level; r.lamp = "R"; e.needsLamp = solve(r) == nil }   // the lamp back on the right bank
        if all.contains("r") {   // vol. 3 ch. 9: unsolvable with the loose stones glued down
            e.needsRoll = solve(Level(id: level.id, map: level.map.map { String($0.map { $0 == "r" ? "x" : $0 }) }, lamp: level.lamp, trifold: level.trifold)) == nil
        }
        if all.contains("r") {   // vol. 3 ch. 11: unsolvable, or dearer, without a lean that comes back / a re-close from a lean
            let nf = solve(level, options: Options(noFro: true)), nh = solve(level, options: Options(openPass: true))
            e.needsFro = nf == nil || (full != nil && nf!.cost > full!.cost)
            e.needsHover = nh == nil || (full != nil && nh!.cost > full!.cost)
        }
        if all.contains("h") { e.needsCrane = without("h") == nil }   // vol. 3 ch. 10: the cranes unfolded into plain paper
        if all.contains("A") { e.needsGate = without("A") == nil }   // the angle gate laid down as paper
        if all.contains("k") { e.needsKey = without("k") == nil }
        if all.contains("i") { e.needsInk = without("i") == nil }
        if all.contains("I") { e.needsWet = without("I") == nil }   // the wet ink dried into plain paper
        if all.contains("g") {
            e.needsGlue = without("g") == nil
            if var b = try? Board(level: level, columnsPerPage: rules.n) { e.glueFires = rules.stamp(&b).contains { $0.kind == .glue } }
        }
        if level.isTrifold { e.needsTrifold = solve(level, options: Options(noFlap: true)) == nil }   // vol. 3 ch. 12: without the second crease
        else if (level.map.first?.count ?? 0) > 2 * rules.n { e.needsFlip = solve(level, angles: Solver.angles, from: nil, noFlip: true) == nil }
        if withDifficulty, full != nil { e.difficulty = Difficulty(self).analyse(level)?.summary }
        return e
    }
}
