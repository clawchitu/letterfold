import Foundation

/// The difficulty metric of fold-proto/tools/check.js `analyse()` (design-difficulty.md §2 and §7, metric v2), ported
/// 1:1. Explores every reachable state (cell, angle, stamped) and measures
///   structure (v1): par + [forks = 1] + [walk ≥ 8] + [trap] + [window ≤ 2] + [combo ≥ 3]
///   insight (v2, what the owner actually feels): 2·[misdirect] + 2·[deadEnds ≥ 1] + [dead ≥ 12] + 2·[before]
///     + 2·[made] + [greedy ≥ 40] + [undo ≥ 1] + [away ≥ 3]
///   score = ⌈structure / 2⌉ + insight.
public struct Difficulty: Sendable {
    /// Score ranges per tier, lowest first (check.js TIERS, v2): vol. 1 ends at mid, vol. 2 starts at hard.
    public static let tiers: [(name: String, range: ClosedRange<Int>)] =
        [("teach", 0...2), ("easy", 3...4), ("mid", 5...7), ("hard", 8...10), ("final", 11...99)]
    public static func range(of tier: String) -> ClosedRange<Int>? { tiers.first { $0.name == tier }?.range }
    /// The mechanics `combo` counts (check.js MECHANICS).
    static let mechanics = ["needsFold", "needsPop", "needsShade", "needsRide", "needsKey", "needsInk", "needsGlue"]

    /// What levels.json ships under `expect.difficulty`.
    public struct Summary: Sendable, Codable, Equatable {
        public var score: Int
        public var tier: String
        public var dead: Int
        public var deadEnds: Int
        public var forks: Int
        public var walk: Int
        public var window: Int
        public var combo: Int
        public var greedy: Int
        public var misdirect: Bool
        public var undo: Int
        public var away: Int
        public var before: Bool
        public var made: Bool
    }

    public struct Report: Sendable {
        public var par, walk, states, explore, dead, deadEnds, deadDepth, kills, forks, window, combo: Int
        public var trap: Bool
        public var greedy: Int
        public var misdirect: Bool
        public var undo, away: Int
        public var before, made: Bool
        public var structure, insight, score: Int
        public var tier: String
        public var summary: Summary {
            Summary(score: score, tier: tier, dead: dead, deadEnds: deadEnds, forks: forks, walk: walk, window: window, combo: combo,
                    greedy: greedy, misdirect: misdirect, undo: undo, away: away, before: before, made: made)
        }
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

    private typealias State = FoldState
    private struct Collapsed: Hashable { var c: Int; var r: Int; var feel: Feel; var st: Int }

    /// How far the goal looks from here to a player who reads the board and not the rules (check.js hOf): Manhattan
    /// distance, in stacked columns when the book is closed, plus two for "on the other page" when it is open.
    func apparent(_ s: FoldState, _ g: Cell?) -> Int {
        guard let g else { return 0 }
        if rules.posture(s.a) == .closed { return abs(rules.proj(s.c) - rules.proj(g.c)) + abs(s.r - g.r) }
        return abs(s.c - g.c) + abs(s.r - g.r) + (rules.isRight(s.c) != rules.isRight(g.c) ? 2 : 0)
    }

    public func analyse(_ level: Level) -> Report? {
        guard let best = solver.solve(level), let grids = solver.grids(level) else { return nil }
        let base = grids[0], goal = base.first(.goal)
        let cfg = rules.config
        let angles = Solver.angles
        let shade = angles.filter { $0 >= cfg.shadeMin && $0 < cfg.foldMin }
        func board(_ s: State) -> Board { grids[s.st] }
        func cell(_ s: State) -> Cell { Cell(s.c, s.r) }
        func won(_ s: State) -> Bool { rules.isWin(board(s), cell(s), rules.posture(s.a)) }
        func moved(_ s: State, _ to: Cell, _ a: Double) -> State { State(c: to.c, r: to.r, a: a, st: solver.after(s, a)) }
        func steps(_ s: State) -> [State] {
            let b = board(s)
            return rules.neighbours(b, cell(s), rules.posture(s.a), rules.shadows(b, s.a)).map { State(c: $0.c, r: $0.r, a: s.a, st: s.st) }
        }
        func collapse(_ s: State) -> Collapsed { Collapsed(c: s.c, r: s.r, feel: feel(s.a), st: s.st) }
        /// Every state reachable by walking alone from s, in BFS order (check.js closure).
        func closure(_ s: State) -> [State] {
            var seen: Set<State> = [s], q = [s], i = 0
            while i < q.count { let x = q[i]; i += 1; for n in steps(x) where seen.insert(n).inserted { q.append(n) } }
            return q
        }

        // every reachable state, its edges both ways, the winning ones, and the ones a hinge move kills from solid paper
        let start = State(c: base.start.c, r: base.start.r, a: 0, st: 0)
        var nodes: Set<State> = [start], order: [State] = [start]
        var rev: [State: [State]] = [:], fwd: [State: [State]] = [:]
        var wins: Set<State> = [], traps: Set<State> = []
        var kills = 0, head = 0
        while head < order.count {
            let s = order[head]; head += 1
            fwd[s] = []
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
                rev[n, default: []].append(s); fwd[s, default: []].append(n)
                if nodes.insert(n).inserted { order.append(n) }
            }
        }
        var alive = wins, back = Array(wins), bh = 0
        while bh < back.count {
            let k = back[bh]; bh += 1
            for p in rev[k] ?? [] where alive.insert(p).inserted { back.append(p) }
        }
        let aliveC = Set(alive.map(collapse))
        let deadStates = order.filter { !alive.contains($0) }
        let deadC = Set(deadStates.map(collapse)).subtracting(aliveC)
        // dead basins: components of the dead region (undirected over moves), sized in collapsed states
        var seenDead: Set<State> = [], deadEnds = 0, deadDepth = 0
        for k0 in deadStates where !seenDead.contains(k0) {
            var comp: Set<Collapsed> = [], q = [k0], qi = 0
            seenDead.insert(k0)
            while qi < q.count {
                let k = q[qi]; qi += 1
                comp.insert(collapse(k))
                for n in (fwd[k] ?? []) + (rev[k] ?? []) where !alive.contains(n) && seenDead.insert(n).inserted { q.append(n) }
            }
            let size = comp.subtracting(aliveC).count
            if size >= 3 { deadEnds += 1 }
            deadDepth = max(deadDepth, size)
        }

        // distinct minimal posture sequences
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
                var nexts: [State] = [], seen: Set<State> = []
                for x in cl { if let to = solver.turn(board(x), cell(x), x.a, a) { let n = moved(x, to, a); if seen.insert(n).inserted { nexts.append(n) } } }
                for n in nexts { rec(n, depth - 1, labels + [label(s.a, a)]) }
            }
        }
        rec(start, best.cost, [])

        let path = best.steps.map { State(c: $0.cell.c, r: $0.cell.r, a: $0.angle, st: $0.st) }
        let bestCells = Set(best.steps.map(\.cell))
        let trap = traps.contains { bestCells.contains(cell($0)) }
        let explore = Set(nodes.map(collapse)).count
        let usesLean = best.steps.contains { feel($0.angle) == .lean }
        let window = usesLean ? shade.filter { keep in
            solver.solve(level, angles: angles.filter { !shade.contains($0) || $0 == keep })?.cost == best.cost
        }.count : shade.count
        let flags = solver.report(level, withDifficulty: false)
        let combo = Self.mechanics.filter { flags.flag($0) == true }.count
        let forks = seqs.count, walk = best.walk

        // ---- v2: the naive player ----
        let naive = greedy(level, grids: grids, goal: goal)
        // the goal-direct first move: from wherever you can walk at the start, the hinge move that makes the goal look
        // closest (ties: the fuller close — closing is what a player does first)
        var direct: (h: Int, a: Double, from: State)?
        for x in closure(start) { for a in angles where a != 0 {
            let h = apparent(State(c: x.c, r: x.r, a: a, st: solver.after(x, a)), goal)
            if direct == nil || h < direct!.h || (h == direct!.h && a > direct!.a) { direct = (h, a, x) }
        } }
        var misdirect = false
        if let d = direct {
            if let to = solver.turn(board(d.from), cell(d.from), 0, d.a) {
                let rest = solver.solve(level, angles: angles, from: State(c: to.c, r: to.r, a: d.a, st: solver.after(d.from, d.a)))
                misdirect = rest == nil || rest!.cost > best.cost
            } else { misdirect = true }                                   // crushed or dropped
        }
        // insight moves along the optimal path: hinge moves with no step between, and steps away from the goal
        var undo = 0, away = 0
        for i in 1..<max(1, path.count) {
            let p = path[i - 1], s = path[i]
            if s.a != p.a { if i + 1 < path.count && path[i + 1].a != s.a { undo += 1 } }
            else if apparent(s, goal) > apparent(p, goal) { away += 1 }
        }
        // twist: something must happen before the first close (it takes it away); the walked shadow was built
        let before = solver.solve(level, angles: angles, from: State(c: start.c, r: start.r, a: 0, st: 1)) == nil
        let made = path.contains { s in
            guard s.st == 1, feel(s.a) == .lean, !rules.isRight(s.c), !board(s)[cell(s)].isFloor,
                  let src = rules.shadows(board(s), s.a)[cell(s)] else { return false }
            return base[src, s.r] != .stone
        }
        let structure = best.cost + (forks == 1 ? 1 : 0) + (walk >= 8 ? 1 : 0) + (trap ? 1 : 0) + (window <= 2 ? 1 : 0) + (combo >= 3 ? 1 : 0)
        let insight = 2 * (misdirect ? 1 : 0) + 2 * (deadEnds >= 1 ? 1 : 0) + (deadC.count >= 12 ? 1 : 0) + 2 * (before ? 1 : 0)
            + 2 * (made ? 1 : 0) + (naive >= 40 ? 1 : 0) + (undo >= 1 ? 1 : 0) + (away >= 3 ? 1 : 0)
        let score = (structure + 1) / 2 + insight
        let tier = Self.tiers.first { $0.range.contains(score) }?.name ?? "?"
        return Report(par: best.cost, walk: walk, states: nodes.count, explore: explore, dead: deadC.count, deadEnds: deadEnds,
                      deadDepth: deadDepth, kills: kills, forks: forks, window: window, combo: combo, trap: trap, greedy: naive,
                      misdirect: misdirect, undo: undo, away: away, before: before, made: made, structure: structure,
                      insight: insight, score: score, tier: tier)
    }

    /// A naive player (check.js greedy): best-first search that always expands the state that looks closest to the
    /// goal, preferring fewer hinge moves on ties, then the earlier found (JS's stable sort). Returns how many
    /// collapsed states it visits before winning.
    func greedy(_ level: Level, grids: [Board], goal: Cell?) -> Int {
        let base = grids[0]
        let start = State(c: base.start.c, r: base.start.r, a: 0, st: 0)
        var seen: Set<State> = [start], visited: Set<Collapsed> = []
        var open: [(h: Int, hc: Int, seq: Int, s: State)] = [(apparent(start, goal), 0, 0, start)]
        var seq = 1
        while !open.isEmpty {
            var bi = 0
            for i in 1..<open.count {
                let x = open[i], y = open[bi]
                if (x.h, x.hc, x.seq) < (y.h, y.hc, y.seq) { bi = i }
            }
            let (_, hc, _, s) = open.remove(at: bi)
            visited.insert(Collapsed(c: s.c, r: s.r, feel: feel(s.a), st: s.st))
            let b = grids[s.st], p = rules.posture(s.a), here = Cell(s.c, s.r)
            if rules.isWin(b, here, p) { return visited.count }
            func push(_ n: State, _ cost: Int) {
                if seen.insert(n).inserted { open.append((apparent(n, goal), cost, seq, n)); seq += 1 }
            }
            for n in rules.neighbours(b, here, p, rules.shadows(b, s.a)) { push(State(c: n.c, r: n.r, a: s.a, st: s.st), hc) }
            for a in Solver.angles where a != s.a {
                if let to = solver.turn(b, here, s.a, a) { push(State(c: to.c, r: to.r, a: a, st: solver.after(s, a)), hc + 1) }
            }
        }
        return visited.count
    }
}
