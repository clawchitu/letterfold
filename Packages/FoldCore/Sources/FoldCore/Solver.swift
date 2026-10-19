import Foundation

/// Brute-force solver: a port of fold-proto/tools/check.js.
/// The hinge is sampled at a few angles; moving between two samples walks the angle in 5° steps,
/// so a character standing on a shadow rides it (or falls) exactly as in the game.
/// Cost = number of angle changes (0-1 BFS: steps are free).
public struct Solver: Sendable {
    public static let angles: [Double] = [0, 90, 100, 110, 120, 125, 130, 140, 150, 180]
    public static let steps15: [Double] = (0...12).map { Double($0 * 15) }

    public let rules: Rules
    public init(_ config: FoldConfig = .standard) { rules = Rules(config) }

    public struct Step: Sendable, Equatable { public var posture: Posture; public var angle: Double; public var cell: Cell }
    public struct Solution: Sendable {
        public var cost: Int
        public var steps: [Step]
        /// Cells walked (state transitions that were not hinge moves), as check.js counts `walk`.
        public var walk: Int { steps.count - 1 - cost }
    }

    private struct State: Hashable { var c: Int; var r: Int; var a: Double; var st: Int }

    /// The character cell after turning the hinge from a0 to a1, or nil if it falls.
    public func turn(_ b: Board, _ from: Cell, _ a0: Double, _ a1: Double) -> Cell? {
        var cur = from
        var src: Int?
        let step = a1 > a0 ? 5.0 : -5.0
        var a = a0 + step
        while step > 0 ? a <= a1 : a >= a1 {
            // design-review-ch3 §2: a figure on paper under a top-page stone is crushed when the book shuts
            if !rules.isRight(cur.c) && (!b[cur].isFloor || rules.crushed(b, cur, a)) {
                if src == nil { src = rules.shadows(b, a - step)[cur] }
                guard let to = rules.ride(b, cur, src, a) else { return nil }
                cur = to
            } else { src = nil }
            a += step
        }
        return cur
    }

    public func solve(_ level: Level, angles: [Double] = Solver.angles) -> Solution? {
        guard let base = try? Board(level: level, columnsPerPage: rules.n) else { return nil }
        var stamped = base
        rules.stamp(&stamped)
        let grids = [base, stamped]
        let start = State(c: base.start.c, r: base.start.r, a: 0, st: 0)
        var parent: [State: State] = [:]
        var dist: [State: Int] = [start: 0]
        // deque: `front` is a stack (unshift), `back` a queue (push)
        var front: [(State, Int)] = [], back: [(State, Int)] = [(start, 0)], head = 0
        while !front.isEmpty || head < back.count {
            let (s, cost): (State, Int)
            if let f = front.popLast() { (s, cost) = f } else { (s, cost) = back[head]; head += 1 }
            if cost > dist[s]! { continue }
            let p = rules.posture(s.a)
            let b = grids[s.st]
            let here = Cell(s.c, s.r)
            if rules.isWin(b, here, p) {
                var chain: [State] = [s], k = s
                while let up = parent[k] { chain.insert(up, at: 0); k = up }
                let steps = chain.map { Step(posture: rules.posture($0.a), angle: $0.a, cell: Cell($0.c, $0.r)) }
                return Solution(cost: cost, steps: steps)
            }
            var next: [(State, Int)] = []
            for a in angles where a != s.a {
                if let to = turn(b, here, s.a, a) {
                    next.append((State(c: to.c, r: to.r, a: a, st: a >= rules.config.foldMin ? 1 : s.st), 1))
                }
            }
            let sh = rules.shadows(b, s.a)
            for nb in rules.neighbours(b, here, p, sh) { next.append((State(c: nb.c, r: nb.r, a: s.a, st: s.st), 0)) }
            for (nState, w) in next {
                if let d = dist[nState], d <= cost + w { continue }
                dist[nState] = cost + w; parent[nState] = s
                if w > 0 { back.append((nState, cost + w)) } else { front.append((nState, cost)) }
            }
        }
        return nil
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
            // like JS row.replace(ch, '.'): the first occurrence in each row
            let map = level.map.map { row -> String in
                guard let i = row.firstIndex(of: ch) else { return row }
                var s = row; s.replaceSubrange(i...i, with: "."); return s
            }
            return solve(Level(id: level.id, map: map))
        }
        var e = Expectation(solvable: full != nil, changes: full?.cost, needsFold: noFold == nil, needsPop: noPop == nil,
                            stepped15: solve(level, angles: Solver.steps15) != nil)
        if level.map.contains(where: { $0.dropFirst(rules.n).contains("x") }) {
            e.needsShade = solve(level, angles: Solver.angles.filter { !shade.contains($0) }) == nil
            let oneShade = shade.contains { keep in solve(level, angles: Solver.angles.filter { !shade.contains($0) || $0 == keep }) != nil }
            e.needsRide = !oneShade
        }
        if all.contains("k") { e.needsKey = without("k") == nil }
        if all.contains("i") { e.needsInk = without("i") == nil }
        if withDifficulty, full != nil { e.difficulty = Difficulty(self).analyse(level)?.summary }
        return e
    }
}
