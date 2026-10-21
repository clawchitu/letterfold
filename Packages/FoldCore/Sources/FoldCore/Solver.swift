import Foundation

/// A point of the search: the figure's cell, the hinge angle (fold degrees), and whether the book has been closed
/// yet (`st` 1 = stamped: keys used, ink printed, glue pulled). check.js keys states the same way.
struct FoldState: Hashable, Sendable { var c: Int; var r: Int; var a: Double; var st: Int }

/// Brute-force solver: a port of fold-proto/tools/check.js.
/// The hinge is sampled at a few angles; moving between two samples walks the angle in 5° steps,
/// so a character standing on a shadow rides it (or falls) exactly as in the game.
/// Cost = number of angle changes (0-1 BFS: steps are free).
public struct Solver: Sendable {
    public static let angles: [Double] = [0, 90, 100, 110, 120, 125, 130, 140, 150, 180]
    public static let steps15: [Double] = (0...12).map { Double($0 * 15) }

    public let rules: Rules
    public init(_ config: FoldConfig = .standard) { rules = Rules(config) }

    public struct Step: Sendable, Equatable {
        public var posture: Posture; public var angle: Double; public var cell: Cell
        /// 1 once the book has been closed (the board is the stamped one).
        public var st: Int = 0
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
            if !rules.isRight(cur.c) && !b[cur].isFloor {
                if src == nil { src = rules.shadows(b, a - step)[cur] }
            } else { src = nil }
            guard let to = rules.ride(b, cur, src, a) else { return nil }
            cur = to
            a += step
        }
        return cur
    }

    /// The unstamped and the stamped board (all glue, keys and ink act at once on the first close).
    func grids(_ level: Level) -> [Board]? {
        guard let base = try? Board(level: level, columnsPerPage: rules.n) else { return nil }
        var stamped = base
        rules.stamp(&stamped)
        return [base, stamped]
    }
    func after(_ s: FoldState, _ a: Double) -> Int { a >= rules.config.foldMin ? 1 : s.st }

    public func solve(_ level: Level, angles: [Double] = Solver.angles) -> Solution? { solve(level, angles: angles, from: nil) }

    /// 0-1 BFS from `from` (default: the level's start, flat, unstamped): angle changes cost 1, steps cost 0.
    func solve(_ level: Level, angles: [Double] = Solver.angles, from: FoldState?) -> Solution? {
        guard let grids = grids(level) else { return nil }
        let base = grids[0]
        let start = from ?? FoldState(c: base.start.c, r: base.start.r, a: 0, st: 0)
        var parent: [FoldState: FoldState] = [:]
        var dist: [FoldState: Int] = [start: 0]
        // deque: `front` is a stack (unshift), `back` a queue (push)
        var front: [(FoldState, Int)] = [], back: [(FoldState, Int)] = [(start, 0)], head = 0
        while !front.isEmpty || head < back.count {
            let (s, cost): (FoldState, Int)
            if let f = front.popLast() { (s, cost) = f } else { (s, cost) = back[head]; head += 1 }
            if cost > dist[s]! { continue }
            let p = rules.posture(s.a)
            let b = grids[s.st]
            let here = Cell(s.c, s.r)
            if rules.isWin(b, here, p) {
                var chain: [FoldState] = [s], k = s
                while let up = parent[k] { chain.insert(up, at: 0); k = up }
                let steps = chain.map { Step(posture: rules.posture($0.a), angle: $0.a, cell: Cell($0.c, $0.r), st: $0.st) }
                return Solution(cost: cost, steps: steps)
            }
            var next: [(FoldState, Int)] = []
            for a in angles where a != s.a {
                if let to = turn(b, here, s.a, a) { next.append((FoldState(c: to.c, r: to.r, a: a, st: after(s, a)), 1)) }
            }
            let sh = rules.shadows(b, s.a)
            for nb in rules.neighbours(b, here, p, sh) { next.append((FoldState(c: nb.c, r: nb.r, a: s.a, st: s.st), 0)) }
            for (nState, w) in next {
                if let d = dist[nState], d <= cost + w { continue }
                dist[nState] = cost + w; parent[nState] = s
                if w > 0 { back.append((nState, cost + w)) } else { front.append((nState, cost)) }
            }
        }
        return nil
    }

    /// The shortest solution as tools/gen.js `bestPath` measures it: fewest posture changes, then fewest steps
    /// (cost 1000 · hinge + 1 · step). `len` = par + steps is the v3 length the tiers gate (difficulty-postmortem.md §6).
    public func shortest(_ level: Level, angles: [Double] = Solver.angles) -> (par: Int, steps: Int, path: [Step])? {
        guard let grids = grids(level) else { return nil }
        let base = grids[0]
        let start = FoldState(c: base.start.c, r: base.start.r, a: 0, st: 0)
        var dist: [FoldState: Int] = [start: 0], parent: [FoldState: FoldState] = [:], done: Set<FoldState> = []
        var open: [FoldState: Int] = [start: 0]
        while let (s, cost) = open.min(by: { $0.value < $1.value }) {
            open[s] = nil
            if !done.insert(s).inserted { continue }
            let b = grids[s.st], here = Cell(s.c, s.r), p = rules.posture(s.a)
            if rules.isWin(b, here, p) {
                var chain = [s], k = s
                while let up = parent[k] { chain.insert(up, at: 0); k = up }
                return (cost / 1000, cost % 1000, chain.map { Step(posture: rules.posture($0.a), angle: $0.a, cell: Cell($0.c, $0.r), st: $0.st) })
            }
            var next: [(FoldState, Int)] = []
            for a in angles where a != s.a {
                if let to = turn(b, here, s.a, a) { next.append((FoldState(c: to.c, r: to.r, a: a, st: after(s, a)), 1000)) }
            }
            for nb in rules.neighbours(b, here, p, rules.shadows(b, s.a)) { next.append((FoldState(c: nb.c, r: nb.r, a: s.a, st: s.st), 1)) }
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
        solve(level, angles: Solver.angles, from: FoldState(c: cell.c, r: cell.r, a: angle, st: closedOnce ? 1 : 0)) != nil
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
            solve(Level(id: level.id, map: level.map.map { String($0.map { $0 == ch ? "." : $0 }) }))
        }
        var e = Expectation(solvable: full != nil, changes: full?.cost, needsFold: noFold == nil, needsPop: noPop == nil,
                            stepped15: solve(level, angles: Solver.steps15) != nil)
        if level.map.contains(where: { $0.dropFirst(rules.n).contains("x") }) || (all.contains("g") && all.contains("x")) {
            e.needsShade = solve(level, angles: Solver.angles.filter { !shade.contains($0) }) == nil
            let oneShade = shade.contains { keep in solve(level, angles: Solver.angles.filter { !shade.contains($0) || $0 == keep }) != nil }
            e.needsRide = !oneShade
        }
        if all.contains("k") { e.needsKey = without("k") == nil }
        if all.contains("i") { e.needsInk = without("i") == nil }
        if all.contains("g") {
            e.needsGlue = without("g") == nil
            if var b = try? Board(level: level, columnsPerPage: rules.n) { e.glueFires = rules.stamp(&b).contains { $0.kind == .glue } }
        }
        if withDifficulty, full != nil { e.difficulty = Difficulty(self).analyse(level)?.summary }
        return e
    }
}
