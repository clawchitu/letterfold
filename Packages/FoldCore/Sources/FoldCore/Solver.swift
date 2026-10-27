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
        let k = g * 2 + face
        if let m = memo[k] { return m }
        var b = table[g]; b.face = face
        rules.stamp(&b)
        b.face = 0
        let idx: Int
        if let i = sig[b.grid] { idx = i } else { idx = table.count; table.append(b); sig[b.grid] = idx }
        memo[k] = idx
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
        public var face: Int = 0
    }
    public struct Solution: Sendable {
        public var cost: Int
        public var steps: [Step]
        /// Cells walked (state transitions that were not hinge moves), as check.js counts `walk`.
        public var walk: Int { steps.count - 1 - cost }
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
        return .to(FoldState(c: s.c, r: s.r, a: s.a, face: s.face ^ 1, g: B.press(s.g, s.face ^ 1)))
    }
    func step(_ s: FoldState) -> Step { Step(posture: rules.posture(s.a), angle: s.a, cell: Cell(s.c, s.r), st: s.st, face: s.face) }

    public func solve(_ level: Level, angles: [Double] = Solver.angles) -> Solution? { solve(level, angles: angles, from: nil) }

    /// 0-1 BFS from `from` (default: the level's start, flat, unpressed): angle changes and page turns cost 1, steps 0.
    /// A `from` state's g indexes `chain`, so pass that chain when starting mid-game.
    func solve(_ level: Level, angles: [Double] = Solver.angles, from: FoldState?, chain: GridChain? = nil, noFlip: Bool = false) -> Solution? {
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
                if let to = turn(b, here, s.a, a) { next.append((FoldState(c: to.c, r: to.r, a: a, face: s.face, g: after(B, s, a)), FoldTally.cost(from: s.a, to: a))) }
            }
            if !noFlip, case let .to(f) = flipOf(B, s) { next.append((f, FoldTally.turnCost)) }
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
                if let to = turn(b, here, s.a, a) { next.append((FoldState(c: to.c, r: to.r, a: a, face: s.face, g: after(B, s, a)), 1000 * FoldTally.cost(from: s.a, to: a))) }
            }
            if case let .to(f) = flipOf(B, s) { next.append((f, 1000 * FoldTally.turnCost)) }
            for nb in rules.neighbours(b, here, p, rules.shadows(b, s.a)) { next.append((FoldState(c: nb.c, r: nb.r, a: s.a, face: s.face, g: s.g), 1)) }
            for (n, w) in next where !done.contains(n) {
                if let d = dist[n], d <= cost + w { continue }
                dist[n] = cost + w; parent[n] = s; open[n] = cost + w
            }
        }
        return nil
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
        var b = board; let face = b.face; b.face = 0
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
            solve(Level(id: level.id, map: level.map.map { String($0.map { $0 == ch ? "." : $0 }) }, lamp: level.lamp))
        }
        var e = Expectation(solvable: full != nil, changes: full?.cost, needsFold: noFold == nil, needsPop: noPop == nil,
                            stepped15: solve(level, angles: Solver.steps15) != nil)
        if all.contains("x") && (level.map.contains(where: { $0.dropFirst(rules.n).contains("x") }) || all.contains("g") || (level.lamp ?? "").contains("L")) {
            e.needsShade = solve(level, angles: Solver.angles.filter { !shade.contains($0) }) == nil
            let oneShade = shade.contains { keep in solve(level, angles: Solver.angles.filter { !shade.contains($0) || $0 == keep }) != nil }
            e.needsRide = !oneShade
        }
        if let lamp = level.lamp, lamp != "R" { var r = level; r.lamp = "R"; e.needsLamp = solve(r) == nil }   // the lamp back on the right bank
        if all.contains("A") { e.needsGate = without("A") == nil }   // the angle gate laid down as paper
        if all.contains("k") { e.needsKey = without("k") == nil }
        if all.contains("i") { e.needsInk = without("i") == nil }
        if all.contains("I") { e.needsWet = without("I") == nil }   // the wet ink dried into plain paper
        if all.contains("g") {
            e.needsGlue = without("g") == nil
            if var b = try? Board(level: level, columnsPerPage: rules.n) { e.glueFires = rules.stamp(&b).contains { $0.kind == .glue } }
        }
        if (level.map.first?.count ?? 0) > 2 * rules.n { e.needsFlip = solve(level, angles: Solver.angles, from: nil, noFlip: true) == nil }
        if withDifficulty, full != nil { e.difficulty = Difficulty(self).analyse(level)?.summary }
        return e
    }
}
