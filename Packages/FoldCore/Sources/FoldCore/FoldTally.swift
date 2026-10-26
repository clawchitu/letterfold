/// 折数 (design-review-onboarding §4 ②) counted exactly as the solver prices a solution (`Solver.solve`, the levels'
/// `expect.changes` = par): every move of the hinge that comes to rest at another angle costs one — a sweep from flat
/// to shut is one, and so is a move between two leaning angles of the same posture (3-1's 0° → 130°) — a page turn
/// costs one, steps and intermediate sweep frames cost nothing.
public struct FoldTally: Sendable, Equatable {
    /// Two resting angles closer than this are the same angle (float noise, a snap landing on its target).
    public static let tolerance = 0.5
    /// What moving the hinge from `a0` to `a1` costs (Solver.solve's edge weight).
    public static func cost(from a0: Double, to a1: Double) -> Int { abs(a0 - a1) > tolerance ? 1 : 0 }
    /// What turning the closed book over costs.
    public static let turnCost = 1

    public private(set) var count = 0
    /// The fold angle the book last came to rest at.
    public private(set) var restAngle: Double

    public init(restAngle: Double = 0) { self.restAngle = restAngle }

    /// The hinge has come to rest at `angle` (only committed rests, never frames of a sweep).
    public mutating func rest(at angle: Double) {
        let c = Self.cost(from: restAngle, to: angle)
        if c > 0 { count += c; restAngle = angle }
    }
    /// The closed book was turned over.
    public mutating func turn() { count += Self.turnCost }
}
