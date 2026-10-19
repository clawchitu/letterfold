import Foundation

/// The difficulty metric of fold-proto/tools/check.js `analyse()` (design-difficulty.md §2), ported 1:1.
/// Explores every reachable state (cell, angle, stamped) and scores
/// par + [forks = 1] + [walk ≥ 8] + [trap] + [window ≤ 2] + [combo ≥ 3]   (0–8).
public struct Difficulty: Sendable {
    /// Score ranges per tier, lowest first (check.js TIERS).
    public static let tiers: [(name: String, range: ClosedRange<Int>)] =
        [("teach", 0...2), ("easy", 3...4), ("mid", 5...6), ("hard", 7...8), ("final", 8...8)]
    public static func range(of tier: String) -> ClosedRange<Int>? { tiers.first { $0.name == tier }?.range }

    /// What levels.json ships under `expect.difficulty`.
    public struct Summary: Sendable, Codable, Equatable {
        public var score: Int
        public var tier: String
        public var dead: Int
        public var forks: Int
        public var walk: Int
        public var window: Int
        public var combo: Int
    }

    public struct Report: Sendable {
        public var par, walk, states, explore, dead, kills, forks, window, combo, score: Int
        public var trap: Bool
        public var tier: String
        public var summary: Summary { Summary(score: score, tier: tier, dead: dead, forks: forks, walk: walk, window: window, combo: combo) }
    }

    public let solver: Solver
    public init(_ solver: Solver) { self.solver = solver }
    var rules: Rules { solver.rules }

    /// What the player feels they did at a sampled angle: fold / lean / pop / open.
    enum Feel: Hashable { case fold, lean, pop, open }
    func feel(_ a: Double) -> Feel {
        let c = rules.config
        return a >= c.foldMin ? .fold : a >= c.shadeMin ? .lean : a >= c.popMin ? .pop : .open
    }

    private struct State: Hashable { var c: Int; var r: Int; var a: Double; var st: Int }

    public func analyse(_ level: Level) -> Report? {
        guard let best = solver.solve(level), let base = try? Board(level: level, columnsPerPage: rules.n) else { return nil }
        var stamped = base
        rules.stamp(&stamped)
        let grids = [base, stamped]
        let cfg = rules.config
        let angles = Solver.angles
        let shade = angles.filter { $0 >= cfg.shadeMin && $0 < cfg.foldMin }
        func board(_ s: State) -> Board { grids[s.st] }
        func cell(_ s: State) -> Cell { Cell(s.c, s.r) }
        func won(_ s: State) -> Bool { rules.isWin(board(s), cell(s), rules.posture(s.a)) }
        func moved(_ s: State, _ to: Cell, _ a: Double) -> State { State(c: to.c, r: to.r, a: a, st: a >= cfg.foldMin ? 1 : s.st) }
        func steps(_ s: State) -> [State] {
            let b = board(s)
            return rules.neighbours(b, cell(s), rules.posture(s.a), rules.shadows(b, s.a)).map { State(c: $0.c, r: $0.r, a: s.a, st: s.st) }
        }

        // every reachable state, its reverse edges, the winning ones, and the ones a hinge move kills from solid paper
        let start = State(c: base.start.c, r: base.start.r, a: 0, st: 0)
        var nodes: Set<State> = [start], order: [State] = [start]
        var rev: [State: [State]] = [:]
        var wins: Set<State> = [], traps: Set<State> = []
        var kills = 0, head = 0
        while head < order.count {
            let s = order[head]; head += 1
            if won(s) { wins.insert(s); continue }
            var out: [State] = []
            for a in angles where a != s.a {
                guard let to = solver.turn(board(s), cell(s), s.a, a) else {
                    kills += 1
                    if board(s)[cell(s)].isFloor { traps.insert(s) }
                    continue
                }
                out.append(moved(s, to, a))
            }
            out += steps(s)
            for n in out {
                rev[n, default: []].append(s)
                if nodes.insert(n).inserted { order.append(n) }
            }
        }
        var alive = wins, back = Array(wins), bh = 0
        while bh < back.count {
            let k = back[bh]; bh += 1
            for p in rev[k] ?? [] where alive.insert(p).inserted { back.append(p) }
        }
        struct Collapsed: Hashable { var c: Int; var r: Int; var feel: Feel; var st: Int }
        func collapse(_ s: State) -> Collapsed { Collapsed(c: s.c, r: s.r, feel: feel(s.a), st: s.st) }
        let aliveC = Set(alive.map(collapse))
        let deadC = Set(nodes.subtracting(alive).map(collapse)).subtracting(aliveC)

        // distinct minimal posture sequences
        func closure(_ s: State) -> [State] {
            var seen: Set<State> = [s], q = [s], i = 0
            while i < q.count { let x = q[i]; i += 1; for n in steps(x) where seen.insert(n).inserted { q.append(n) } }
            return q
        }
        func label(_ a0: Double, _ a: Double) -> String {
            let p = feel(a), p0 = feel(a0)
            if p == .lean || (p0 == .lean && p != .fold) { return a > a0 ? "lean+" : "lean-" }
            return "\(p)"
        }
        var seqs: Set<[String]> = []
        func rec(_ s: State, _ depth: Int, _ labels: [String]) {
            let cl = closure(s)
            if cl.contains(where: won) { seqs.insert(labels); return }
            if depth == 0 { return }
            for a in angles {
                if a == s.a || (feel(a) == feel(s.a) && feel(a) != .lean) { continue }
                var nexts: Set<State> = []
                for x in cl { if let to = solver.turn(board(x), cell(x), x.a, a) { nexts.insert(moved(x, to, a)) } }
                for n in nexts { rec(n, depth - 1, labels + [label(s.a, a)]) }
            }
        }
        rec(start, best.cost, [])

        let bestCells = Set(best.steps.map(\.cell))
        let trap = traps.contains { bestCells.contains(cell($0)) }
        let explore = Set(nodes.map(collapse)).count
        let usesLean = best.steps.contains { feel($0.angle) == .lean }
        let window = usesLean ? shade.filter { keep in
            solver.solve(level, angles: angles.filter { !shade.contains($0) || $0 == keep })?.cost == best.cost
        }.count : shade.count
        let flags = solver.report(level, withDifficulty: false)
        let combo = [flags.needsFold, flags.needsPop, flags.needsShade == true, flags.needsRide == true,
                     flags.needsKey == true, flags.needsInk == true].filter { $0 }.count
        let forks = seqs.count, walk = best.walk
        let score = best.cost + (forks == 1 ? 1 : 0) + (walk >= 8 ? 1 : 0) + (trap ? 1 : 0) + (window <= 2 ? 1 : 0) + (combo >= 3 ? 1 : 0)
        let tier = Self.tiers.first { $0.range.contains(score) }?.name ?? "?"
        return Report(par: best.cost, walk: walk, states: nodes.count, explore: explore, dead: deadC.count, kills: kills,
                      forks: forks, window: window, combo: combo, score: score, trap: trap, tier: tier)
    }
}
