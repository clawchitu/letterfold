import Foundation

/// The difficulty metric of fold-proto/tools/check.js `analyse()` (design-difficulty.md §2 and §7, metric v2), ported
/// 1:1. Explores every reachable state (cell, angle, stamped) and measures
///   structure (v1): par + [forks = 1] + [walk ≥ 8] + [trap] + [window ≤ 2] + [combo ≥ 3]
///   insight (v2, what the owner actually feels): 2·[misdirect] + 2·[deadEnds ≥ 1] + [dead ≥ 12] + 2·[before]
///     + 2·[made] + [greedy ≥ 40] + [undo ≥ 1] + [away ≥ 3]
///   score = ⌈structure / 2⌉ + insight.
public struct Difficulty: Sendable {
    /// Score ranges per tier, lowest first (check.js TIERS since the 卷一 retune, difficulty-postmortem.md §1.6 / §6): the
    /// v2 score is a ceiling for teach–mid and only a weak floor for hard / final; the tier name of a score is the lowest
    /// range it fits. The gates that track time-to-solve are v3 (`gates`: solution length, wrong turns, decoys).
    public static let tiers: [(name: String, range: ClosedRange<Int>)] =
        [("teach", 0...2), ("easy", 0...6), ("mid", 0...99), ("hard", 5...99), ("final", 6...99)]
    /// check.js GATES (v3): the minimal solution length (posture changes + steps) a tier must reach, or may not exceed.
    public static let lenMin: [String: Int] = ["easy": 6, "mid": 11, "hard": 15, "final": 18, "dark": 18]
    public static let lenMax: [String: Int] = ["teach": 10]
    /// check.js PAR_MAX / CLOSES_MAX (postmortem §1.4): posture changes and full closes per tier; 「暗信」 = dark.
    /// final par 4 → 5 and final closes 2 → 3 (fold-proto c4b9d48 / 82e0990, difficulty-v3.md §6).
    public static let parMax: [String: Int] = ["teach": 3, "easy": 3, "mid": 3, "hard": 4, "final": 5, "dark": 6]
    /// wet: chapter 7 「墨晕」's main path, where closes are the chapter's resource (check.js CLOSES_MAX.wet, WET_CHAPTER).
    public static let closesMax: [String: Int] = ["main": 2, "final": 3, "dark": 3, "wet": 3]
    /// The full-close budget of a level: 「暗信」 3, a main-path final 3, chapter 7 (`wet`) 3, everything else 2.
    public static func closesMax(optional: Bool, tier: String?, wet: Bool = false) -> Int {
        closesMax[optional ? "dark" : tier == "final" ? "final" : wet ? "wet" : "main"]!
    }
    /// check.js gates chapter 7 by its chapter number; FoldCore has no chapters, and wet ink is chapter 7's tile (8-7
    /// reuses it under the lamp: chapter 8 carries `lamp`).
    public static func isWetChapter(_ level: Level) -> Bool { level.lamp == nil && level.map.contains { $0.contains("I") } && !level.map.contains { $0.contains("h") } }   // ch. 10-5 soak has wet ink and cranes: not the wet chapter (check.js WET_CHAPTER = 7)
    /// check.js PAR_MAX_CH = {11: {hard: 5, final: 6}}: ch. 11 「来回」 (a lean that comes back costs 2 changes and no
    /// close) raises hard 4 -> 5 and final 5 -> 6. FoldCore has no chapters and ch. 11 shares its tiles with ch. 9/10, so no
    /// structural rule separates it (needsFro is also true on 9-3 / 9-5 / 10-4): it is recognised by its level ids.
    public static let chapter11: Set<String> = ["fro", "still", "hover", "past", "park"]
    public static func parMax(for level: Level) -> Int {
        if level.isOptional { return parMax["dark"]! }
        if chapter11.contains(level.id), let t = level.tier, let m = ["hard": 5, "final": 6][t] { return m }
        return parMax[level.tier ?? ""] ?? 3
    }
    public static func range(of tier: String) -> ClosedRange<Int>? { tiers.first { $0.name == tier }?.range }
    /// The mechanics `combo` counts (check.js MECHANICS).
    static let mechanics = ["needsFold", "needsPop", "needsShade", "needsRide", "needsKey", "needsInk", "needsGlue", "needsFlip", "needsWet", "needsLamp", "needsGate", "needsRoll", "needsCrane", "needsFro", "needsHover"]

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
    private struct Collapsed: Hashable { var c: Int; var r: Int; var feel: Feel; var face: Int; var g: Int }

    /// How far the goal looks from here to a player who reads the board and not the rules (check.js hOf): Manhattan
    /// distance, in stacked columns when the book is closed, plus two for "on the other page" when it is open.
    /// Plus two more when the goal is on a page that is not facing now (you would have to turn the book).
    func apparent(_ s: FoldState, _ goal: (cell: Cell, face: Int?)?) -> Int {
        guard let goal else { return 0 }
        let g = goal.cell
        let turned = goal.face != nil && goal.face != s.face ? 2 : 0
        if rules.posture(s.a) == .closed { return abs(rules.proj(s.c) - rules.proj(g.c)) + abs(s.r - g.r) + turned }
        return abs(s.c - g.c) + abs(s.r - g.r) + (rules.isRight(s.c) != rules.isRight(g.c) ? 2 : 0) + turned
    }

    public func analyse(_ level: Level) -> Report? {
        guard let best = solver.solve(level), let B = solver.chain(level) else { return nil }
        let base = B.base, goal = base.locate(.goal)
        let cfg = rules.config
        let angles = Solver.angles
        let shade = angles.filter { $0 >= cfg.shadeMin && $0 < cfg.foldMin }
        func board(_ s: State) -> Board { B.world(s) }
        func cell(_ s: State) -> Cell { Cell(s.c, s.r) }
        func won(_ s: State) -> Bool { rules.isWin(board(s), cell(s), rules.posture(s.a)) }
        func steps(_ s: State) -> [State] {
            let b = board(s)
            return rules.neighbours(b, cell(s), rules.posture(s.a), rules.shadows(b, s.a)).map { State(c: $0.c, r: $0.r, a: s.a, face: s.face, g: s.g) }
        }
        func collapse(_ s: State) -> Collapsed { Collapsed(c: s.c, r: s.r, feel: feel(s.a), face: s.face, g: s.g) }
        /// Every state reachable by walking alone from s, in BFS order (check.js closure).
        func closure(_ s: State) -> [State] {
            var seen: Set<State> = [s], q = [s], i = 0
            while i < q.count { let x = q[i]; i += 1; for n in steps(x) where seen.insert(n).inserted { q.append(n) } }
            return q
        }

        // every reachable state, its edges both ways, the winning ones, and the ones a hinge move kills from solid paper
        let start = solver.startOf(B)
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
                guard let n = solver.move(B, s, a) else {
                    kills += 1
                    if board(s)[cell(s)].isFloor { traps.insert(s) }
                    continue
                }
                out.append(n)
            }
            switch solver.flipOf(B, s) {   // turning the book onto a stone is a crush from paper
            case .crushed: kills += 1; traps.insert(s)
            case let .to(f): out.append(f)
            case .notAllowed: break
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
                for x in cl { if let n = solver.move(B, x, a), seen.insert(n).inserted { nexts.append(n) } }
                for n in nexts { rec(n, depth - 1, labels + [label(s.a, a)]) }
            }
            var flips: [State] = [], seenF: Set<State> = []
            for x in cl { if case let .to(f) = solver.flipOf(B, x), seenF.insert(f).inserted { flips.append(f) } }
            for n in flips { rec(n, depth - 1, labels + ["flip"]) }
        }
        rec(start, min(best.cost, 3), [])   // exponential in par: past 3 forks are reported as 1 (check.js, postmortem §6)

        // the path's states, with their grids (the steps carry only st / face; replay the presses along the way)
        var path: [State] = []
        for (i, st) in best.steps.enumerated() {
            if i == 0 { path.append(start); continue }
            let p = path[i - 1]
            var g = p.g
            if st.face != p.face { g = B.press(p.g, st.face) } else if st.angle != p.a { g = solver.move(B, p, st.angle)?.g ?? p.g }
            path.append(State(c: st.cell.c, r: st.cell.r, a: st.angle, face: st.face, g: g))
        }
        let bestCells = Set(best.steps.map(\.cell))
        let trap = traps.contains { bestCells.contains(cell($0)) }
        let explore = Set(nodes.map(collapse)).count
        let usesLean = best.steps.contains { feel($0.angle) == .lean }
        let window = usesLean ? shade.filter { keep in
            solver.solve(level, angles: angles.filter { !shade.contains($0) || $0 == keep })?.cost == best.cost
        }.count : shade.count
        let flags = solver.report(level, withDifficulty: false)
        let combo = Self.mechanics.filter { flags.flag($0) == true }.count
        let forks = best.cost > 3 ? 1 : seqs.count, walk = best.walk

        // ---- v2: the naive player ----
        let naive = greedy(level, chain: B, goal: goal)
        // the goal-direct first move: from wherever you can walk at the start, the hinge move that makes the goal look
        // closest (ties: the fuller close — closing is what a player does first)
        var direct: (h: Int, a: Double, from: State)?
        for x in closure(start) { for a in angles where a != 0 {
            let h = apparent(State(c: x.c, r: x.r, a: a, face: 0, g: 0), goal)   // check.js 7808fad: imagined on the start grid
            if direct == nil || h < direct!.h || (h == direct!.h && a > direct!.a) { direct = (h, a, x) }
        } }
        var misdirect = false
        if let d = direct {
            if let n = solver.move(B, d.from, d.a) {
                let rest = solver.solve(level, angles: angles, from: n, chain: B)
                misdirect = rest == nil || rest!.cost > best.cost
            } else { misdirect = true }                                   // crushed or dropped
        }
        // insight moves along the optimal path: hinge moves with no step between, and steps away from the goal
        var undo = 0, away = 0
        for i in 1..<max(1, path.count) {
            let p = path[i - 1], s = path[i]
            if s.a != p.a { if i + 1 < path.count && path[i + 1].a != s.a { undo += 1 } }
            else if s.face == p.face && apparent(s, goal) > apparent(p, goal) { away += 1 }
        }
        // twist: something must happen before the first close (it takes it away); the walked shadow was built
        let before = solver.solve(level, angles: angles, from: State(c: start.c, r: start.r, a: 0, face: 0, g: B.press(0, 0)), chain: B) == nil
        let made = path.contains { s in
            // either page (fold-proto 15c073d: under the left lamp a glued stone shades the lifted page, ch. 8)
            guard s.g != 0, feel(s.a) == .lean, !board(s)[cell(s)].isFloor,
                  let src = rules.shadows(board(s), s.a)[cell(s)] else { return false }
            return !base.grid[s.r][s.face == 1 && src >= rules.n ? src + rules.n : src].isOpaque   // a rolled loose stone's shadow is made too
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
    func greedy(_ level: Level, chain B: GridChain, goal: (cell: Cell, face: Int?)?) -> Int {
        let start = solver.startOf(B)
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
            visited.insert(Collapsed(c: s.c, r: s.r, feel: feel(s.a), face: s.face, g: s.g))
            let b = B.world(s), p = rules.posture(s.a), here = Cell(s.c, s.r)
            if rules.isWin(b, here, p) { return visited.count }
            func push(_ n: State, _ cost: Int) {
                if seen.insert(n).inserted { open.append((apparent(n, goal), cost, seq, n)); seq += 1 }
            }
            for n in rules.neighbours(b, here, p, rules.shadows(b, s.a)) { push(State(c: n.c, r: n.r, a: s.a, face: s.face, g: s.g), hc) }
            for a in Solver.angles where a != s.a {
                if let n = solver.move(B, s, a) { push(n, hc + 1) }
            }
            if case let .to(f) = solver.flipOf(B, s) { push(f, hc + 1) }
        }
        return visited.count
    }
}
