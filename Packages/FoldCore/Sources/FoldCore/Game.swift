import Foundation

/// Something the UI should react to (sound, haptics, VoiceOver).
public enum GameEvent: Sendable, Equatable {
    case postureChanged(from: Posture, to: Posture)
    case stamped(Rules.Stamp)
    /// New cells became reachable after the hinge moved.
    case connected
    /// Some cells stopped being reachable.
    case lost
    case shadeChanged
    case slid(to: Cell)
    case fell(crushed: Bool)
    case stepped(to: Cell)
    case blocked
    case won
}

/// A level being played: the stateful half of main.js (angle, riding shadows, stamping, undo).
public final class FoldGame {
    public let level: Level
    public let rules: Rules
    public private(set) var board: Board
    public private(set) var char: Cell
    public private(set) var angle: Double = 0
    public private(set) var posture: Posture = .open
    public private(set) var shade: [Cell: Int] = [:]
    public private(set) var won = false
    /// The cells walked so far, in order, starting at the start cell: the vermilion thread (design-spec §0.3).
    /// A fall starts it again; undo restores it.
    public private(set) var trail: [Cell]
    private var rideSrc: Int?

    private struct Snapshot { var board: Board; var char: Cell; var angle: Double; var trail: [Cell] }
    private var undoStack: [Snapshot] = []
    public var canUndo: Bool { !undoStack.isEmpty }

    /// The hinge is simulated in steps of at most this many degrees, so riding a shadow does not depend on frame rate.
    public static let subStep = 5.0

    public init(level: Level, config: FoldConfig = .standard) throws {
        self.level = level
        rules = Rules(config)
        board = try Board(level: level, columnsPerPage: config.columnsPerPage)
        char = board.start
        trail = [board.start]
    }

    public var config: FoldConfig { rules.config }
    public var neighbours: [Cell] { rules.neighbours(board, char, posture, shade) }
    public var reachable: Set<Cell> { rules.reachable(board, from: char, posture, shade) }
    public var goal: Cell? { board.first(.goal) }
    public func path(to target: Cell) -> [Cell]? { rules.findPath(board, from: char, to: target, posture, shade) }

    // MARK: hinge

    /// Move the hinge to `target` degrees (clamped to 0...180), passing through intermediate angles.
    @discardableResult
    public func setAngle(_ target: Double) -> [GameEvent] {
        let target = min(180, max(0, target))
        var events: [GameEvent] = []
        let before = reachable
        while angle != target {
            let next = target > angle ? min(target, angle + Self.subStep) : max(target, angle - Self.subStep)
            apply(next, &events)
        }
        if !won {
            let now = reachable
            if !now.subtracting(before).isEmpty { events.append(.connected) }
            else if now.count < before.count { events.append(.lost) }
        }
        return events
    }

    private func apply(_ a: Double, _ events: inout [GameEvent]) {
        angle = a
        // shadows move; a character standing on nothing but shadow goes with them
        let previous = shade
        shade = rules.shadows(board, a)
        if !rules.isRight(char.c) && (!board[char].isFloor || rules.crushed(board, char, a)) {
            if rideSrc == nil { rideSrc = previous[char] ?? shade[char] }
            if let to = rules.ride(board, char, rideSrc, a) {
                if to.c != char.c { char = to; trail.append(to); events.append(.slid(to: to)) }
            } else {
                events.append(.fell(crushed: a >= config.foldMin))
                char = board.start; trail = [board.start]; rideSrc = nil
            }
        } else { rideSrc = nil }
        if Set(shade.keys) != Set(previous.keys) { events.append(.shadeChanged) }
        let next = rules.posture(a)
        if next != posture {
            let prev = posture
            posture = next
            events.append(.postureChanged(from: prev, to: next))
            if next == .closed { rules.stamp(&board).forEach { events.append(.stamped($0)) } }
            checkWin(&events)
        }
    }

    // MARK: walking

    /// Take one step to a neighbouring cell. Returns [.blocked] if it is not a neighbour.
    @discardableResult
    public func step(to n: Cell) -> [GameEvent] {
        guard !won, neighbours.contains(n) else { return [.blocked] }
        char = n
        trail.append(n)
        rideSrc = board[n].isFloor ? nil : shade[n]
        var events: [GameEvent] = [.stepped(to: n)]
        checkWin(&events)
        return events
    }

    /// Walk the whole way at once (tests, VoiceOver). nil if unreachable.
    @discardableResult
    public func walk(to target: Cell) -> [GameEvent]? {
        guard let path = path(to: target) else { return nil }
        return path.flatMap { step(to: $0) }
    }

    private func checkWin(_ events: inout [GameEvent]) {
        if !won && rules.isWin(board, char, posture) { won = true; events.append(.won) }
    }

    // MARK: undo

    public func pushUndo() {
        undoStack.append(Snapshot(board: board, char: char, angle: angle, trail: trail))
        if undoStack.count > 200 { undoStack.removeFirst() }
    }

    /// Forget the last pushUndo (a drag that ended where it started).
    public func dropUndo() { _ = undoStack.popLast() }

    @discardableResult
    public func undo() -> Bool {
        guard let s = undoStack.popLast() else { return false }
        board = s.board; char = s.char; angle = s.angle; trail = s.trail
        posture = rules.posture(angle); shade = rules.shadows(board, angle); rideSrc = nil; won = false
        return true
    }

    public func reset() {
        board = try! Board(level: level, columnsPerPage: config.columnsPerPage)
        char = board.start; trail = [board.start]; angle = 0; posture = .open; shade = [:]; rideSrc = nil; won = false; undoStack = []
    }
}
