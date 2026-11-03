import Foundation

/// The 「?」's visual solution (hint-skip ②, owner 11/02: "纯文字的就会像刚才一样我看不懂"): the proto solver's shortest
/// solution (`Level.solution`, tools/level-extras.js) cut into the steps a player takes — a walk (one or more squares at
/// one angle, drawn as a dotted route), a fold (to one angle, shown by a ghost page and fingertip), a turn of the book
/// (ch. 6) or a change of crease / face (ch. 12). Nothing is hand-authored, so every level with a solution has one.
public enum Guide {
    public enum Kind: Equatable, Sendable {
        /// The squares in order, the first being where she stands when the step starts.
        case walk([Cell])
        /// Fold (0 flat … 180 shut) to this angle.
        case fold(Double)
        /// 「翻」: turn the shut book over (ch. 6).
        case turn
        /// Ch. 12: another face of the trifold (2 = the third page on its own crease, 3 = the book with it folded, 0 = back),
        /// and the angle it comes to rest at when that changes too (`drop`: face 2 at 125°).
        case face(Int, Double?)
    }

    public struct Step: Equatable, Sendable {
        public var kind: Kind
        /// Solution indices of the state the step starts from and the one it ends on.
        public var from: Int
        public var to: Int
    }

    /// One solution state: [c, r, fold angle, stamped, face?].
    public struct State: Equatable, Sendable {
        public var cell: Cell
        public var angle: Double
        public var face: Int
        public init(cell: Cell, angle: Double, face: Int) { self.cell = cell; self.angle = angle; self.face = face }
        public init(_ s: [Int]) { cell = Cell(s[0], s[1]); angle = Double(s[2]); face = s.count > 4 ? s[4] : 0 }
    }

    public static func steps(_ solution: [[Int]], trifold: Bool = false) -> [Step] {
        let s = solution.map(State.init)
        var out: [Step] = []
        var i = 1
        while i < s.count {
            let a = s[i - 1], b = s[i]
            if a.face != b.face {
                out.append(Step(kind: trifold ? .face(b.face, a.angle != b.angle ? b.angle : nil) : .turn, from: i - 1, to: i)); i += 1; continue
            }
            if a.angle != b.angle {
                out.append(Step(kind: .fold(b.angle), from: i - 1, to: i)); i += 1; continue
            }
            var cells = [a.cell, b.cell]
            var j = i + 1
            while j < s.count, s[j].face == s[j - 1].face, s[j].angle == s[j - 1].angle, s[j].cell != s[j - 1].cell {
                cells.append(s[j].cell); j += 1
            }
            out.append(Step(kind: .walk(cells), from: i - 1, to: j - 1))
            i = j
        }
        return out
    }

    /// The solver samples a few angles (Solver.angles) and picks any that works, so 1-2's last step reads 110° where any
    /// open page does. Two angles are "the same rest" for the guide when they are in the same regime: posture and lean.
    public static func sameRegime(_ a: Double, _ b: Double, config: FoldConfig) -> Bool {
        config.posture(for: a) == config.posture(for: b) && config.isLeaning(a) == config.isLeaning(b)
    }

    /// Finding the player's place on the route again (after an undo, a restart, a detour): the first solution index at
    /// or after `from` with her square, face and angle regime (11-1 `fro`: back on (7, 0) at 130° is state 1, not the
    /// flat start); failing that, the first with her square and face and the book shut or not as she has it (ch. 1–2
    /// rest at detents the solver's angle only resembles). nil: off the route.
    public static func match(_ solution: [[Int]], from: Int, now: State, config: FoldConfig) -> Int? {
        guard from < solution.count else { return nil }
        let states = solution[from...].map(State.init)
        let here = states.indices.filter { states[$0].cell == now.cell && states[$0].face == now.face }
        if let j = here.first(where: { sameRegime(states[$0].angle, now.angle, config: config) }) { return from + j }
        let shut = now.angle >= config.foldMin
        return here.first { (states[$0].angle >= config.foldMin) == shut }.map { from + $0 }
    }

    /// The step to show when the player stands on solution state `j`: the one that starts there or contains it;
    /// `steps.count` once she stands on the last state.
    public static func stepIndex(_ steps: [Step], at j: Int) -> Int {
        steps.firstIndex { j >= $0.from && j < $0.to } ?? steps.count
    }
}
