import Foundation

/// Something the UI should react to (sound, haptics, VoiceOver).
public enum GameEvent: Sendable, Equatable {
    case postureChanged(from: Posture, to: Posture)
    case stamped(Rules.Stamp)
    /// New cells became reachable after the hinge moved.
    case connected
    /// The goal became reachable after the hinge moved (playtest 10/20: "a path connects" is only said for this;
    /// new squares that do not reach the goal are `connected` alone).
    case goalInReach
    /// Some cells stopped being reachable.
    case lost
    case shadeChanged
    case slid(to: Cell)
    case fell(crushed: Bool)
    case stepped(to: Cell)
    case blocked
    case won
    /// The goal can no longer be reached from here without undo or restart (vol. 2 dead ends, design-review-v2c1 §3):
    /// checked as the book shuts and as it opens again; sent once, on the move that made it so.
    case deadEnd
    /// The closed book was turned over (vol. 2 ch. 6 「翻」): `face` 1 = the third page now faces the left page.
    case flipped(face: Int)
    /// The turn brought a stone down on the figure (its cause; logic.js flip `crush`): the level starts again — grids
    /// and face as they began, the figure on the start, the book still shut (logic.js restart). Sent after `.flipped`
    /// (which carries the face the turn came to); a crushing turn presses nothing, so no `.stamped`.
    case flipCrushed(Rules.CrushCause)
    /// The lifted page passed upright (vol. 3 ch. 9 「滚」): these loose stones rolled one cell towards the crease, nearest
    /// the crease first (logic.js roll events). Sent before the shadows of the same sub-step are read.
    case rolled([Rules.Roll])
    /// The crane the figure stood on flew at the press (vol. 3 ch. 10 「鹤」, logic.js `carried`): she is on its landing, on
    /// the other page (closed, the same stack — the open book shows it). Sent after the press's `.stamped` events.
    case carried(to: Cell)
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
    /// The book has been shut at least once: keys, ink and glue have acted (the solver's `st`).
    public private(set) var closedOnce = false
    /// The goal is out of reach for good (a dead end); undo or restart.
    public private(set) var stuck = false
    /// The cells walked so far, in order, starting at the start cell: the vermilion thread (design-spec §0.3).
    /// A fall starts it again; undo restores it.
    public private(set) var trail: [Cell]
    /// The trail index the book was last shut at (0: never shut since the thread began): steps from here on are the
    /// live thread, earlier ones the faded old stitches (thread-aging spec). A fall or a restart starts it again.
    public private(set) var lastCloseStep = 0
    private var rideSrc: Int?

    private struct Snapshot {
        var board: Board; var char: Cell; var angle: Double; var trail: [Cell]; var closedOnce: Bool; var stuck: Bool
        var lastCloseStep = 0
        /// Only on a restart's snapshot: the 折数 and resting angle before it, which undoing the restart brings back
        /// (Codex review 18 #2).
        var tally: FoldTally? = nil
    }
    private var undoStack: [Snapshot] = []
    public var canUndo: Bool { !undoStack.isEmpty }
    /// 折数 so far (the app notes rests and turns). A restart zeroes it and undoing the restart restores it (count and
    /// resting angle); other undos leave it (a fold that was made and taken back was still made).
    public var tally = FoldTally()

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
    /// Where the goal is on any page (face nil = the left page; 1 = on the third page, at that visible cell once turned).
    public var goalAnywhere: (cell: Cell, face: Int?)? { board.locate(.goal) }
    /// Which face of the right leaf faces the left page (0 right page, 1 third page).
    public var face: Int { board.face }
    /// Why 「翻」 is refused right now, or nil when the book can be turned over.
    public var flipBlock: Rules.FlipBlock? { rules.flipBlock(board, char, angle) }
    public func path(to target: Cell) -> [Cell]? { rules.findPath(board, from: char, to: target, posture, shade) }
    /// The goal can be walked to from here, now (without moving the hinge).
    public var goalInReach: Bool { goal.map { path(to: $0) != nil } ?? false }

    // MARK: hinge

    /// Move the hinge to `target` degrees (clamped to 0...180), passing through intermediate angles.
    @discardableResult
    public func setAngle(_ target: Double) -> [GameEvent] {
        let target = min(180, max(0, target))
        var events: [GameEvent] = []
        let before = reachable, wasPosture = posture, goalBefore = goalInReach
        while angle != target {
            let next = target > angle ? min(target, angle + Self.subStep) : max(target, angle - Self.subStep)
            apply(next, &events)
        }
        if !won {
            let now = reachable
            if !now.subtracting(before).isEmpty { events.append(.connected) }
            if goalInReach && !goalBefore { events.append(.goalInReach) }
            else if now.count < before.count { events.append(.lost) }
            // the shut and the opening are where a vol. 2 dead end begins: a stone glued away, a road blocked
            // vol. 3: a roll changes the board without a close (a stone rolled into the only gap you could cross on)
            let rolled = events.contains { if case .rolled = $0 { return true } else { return false } }
            if !stuck && (rolled || (posture != wasPosture && (posture == .closed || wasPosture == .closed))) { checkDeadEnd(&events) }
        }
        return events
    }

    private func apply(_ a: Double, _ events: inout [GameEvent]) {
        let before = angle
        angle = a
        // won: the aha / finale shuts the book on the winning square; nothing moves, falls or is crushed any more
        // (Codex review 12: 5-7 is won leaning at (0,0) under the stone at (7,0), and the finale's close sent her home)
        if won { shade = rules.shadows(board, a); posture = rules.posture(a); return }
        // shadows move; a character standing on nothing but shadow goes with them
        var previous = shade
        // vol. 3 ch. 9: the lifted page passed upright — the loose stones roll first (the figure holds the one she stands
        // in front of), and the rest of this sub-step (shadows, a ride, the crush) is judged on the rolled board
        // (check.js move: roll, then ride / fall / crush, then the press)
        if rules.passes(before, a) {
            let rolls = rules.roll(&board, fig: char)
            if !rolls.isEmpty { events.append(.rolled(rolls)); previous = rules.shadows(board, before) }
            rideSrc = nil
        }
        shade = rules.shadows(board, a)
        // on nothing but a shadow, or (closing) under a stone: on the bottom page, or on top-page glue facing one
        if !board[char].isFloor || rules.crushed(board, char, a) {
            if rideSrc == nil { rideSrc = previous[char] ?? shade[char] }
            if let to = rules.ride(board, char, rideSrc, a) {
                if to.c != char.c {
                    char = to; trail.append(to); events.append(.slid(to: to))
                    // a ride that lands on her square delivers it, as the solver already counts it (Codex review 20 #4;
                    // fold-proto logic.js / main.js only check on steps and posture changes — port upstream)
                    checkWin(&events)
                }
            } else {
                // crushed only where the stone really comes down: on the figure's own square (design-review-ch4 §3.1:
                // a shadow giving way under you at the shut is a fall, and only a crush gets the dent)
                events.append(.fell(crushed: rules.crushed(board, char, a)))
                char = board.start; trail = [board.start]; lastCloseStep = 0; rideSrc = nil
            }
        } else { rideSrc = nil }
        if Set(shade.keys) != Set(previous.keys) { events.append(.shadeChanged) }
        let next = rules.posture(a)
        if next != posture {
            let prev = posture
            posture = next
            events.append(.postureChanged(from: prev, to: next))
            if next == .closed {
                let stamps = rules.stamp(&board)
                stamps.forEach { events.append(.stamped($0)) }; closedOnce = true
                carry(stamps, &events)
                lastCloseStep = trail.count - 1
            }
            checkWin(&events)
        }
    }

    /// Vol. 3 ch. 10: after a press, the figure goes where the crane it stood on flew (logic.js `carried`).
    private func carry(_ stamps: [Rules.Stamp], _ events: inout [GameEvent]) {
        let to = rules.carried(stamps, char)
        guard to != char else { return }
        char = to; trail.append(to); events.append(.carried(to: to))
    }

    /// Vol. 2 dead ends: glue (a stone glued away), a third page (a turn that blocks a stack) or wet ink (a blot that
    /// grew over the road or spoiled the glue) can end the level. Wet ink and turns change the board press by press, so
    /// those levels are checked against the live board, not "the start board stamped once" (Codex review 19 #1).
    private func checkDeadEnd(_ events: inout [GameEvent]) {
        let all = level.map.joined(), wet = all.contains("I") || all.contains("r") || all.contains("h")   // wet ink, loose stones, cranes: the live board
        guard !stuck, !won, all.contains("g") || board.pages > 2 || wet else { return }
        let solver = Solver(config)
        let ok = board.pages > 2 || wet
            ? solver.canStillWin(level, board: board, from: char, angle: posture == .closed ? 180 : angle)
            : solver.canStillWin(level, from: char, angle: posture == .closed ? 180 : angle, closedOnce: closedOnce)
        if !ok { stuck = true; events.append(.deadEnd) }
    }

    // MARK: turning the page

    /// 「翻」: turn the closed book over (logic.js flip). Refused (returns [.blocked], nothing changes) unless closed, on
    /// the left page, in a three-page book — read `flipBlock` for the reason. The press stamps like a close; a stone on
    /// the new facing page over the figure restarts the level: grids and face as they began, the figure on the start
    /// (else on 6-3, whose start lies under a third-page stone, the next opening crushes her again). The book stays
    /// shut and undo still steps back to before the turn. Call pushUndo first.
    @discardableResult
    public func flip() -> [GameEvent] {
        guard !won, flipBlock == nil else { return [.blocked] }
        let before = reachable, goalBefore = goalInReach
        let (stamps, crush) = rules.flip(&board, char)
        var events: [GameEvent] = [.flipped(face: board.face)]
        if let crush {
            events.append(.flipCrushed(crush))
            board = try! Board(level: level, columnsPerPage: config.columnsPerPage)
            char = board.start; trail = [board.start]; lastCloseStep = 0; closedOnce = false; stuck = false
        } else {
            stamps.forEach { events.append(.stamped($0)) }
            closedOnce = true
            carry(stamps, &events)   // vol. 3 ch. 10: a crane under your feet flies to the page you turned to, with you
        }
        shade = rules.shadows(board, angle); rideSrc = nil
        checkWin(&events)
        if !won {
            let now = reachable
            if !now.subtracting(before).isEmpty { events.append(.connected) }
            if goalInReach && !goalBefore { events.append(.goalInReach) }
            else if now.count < before.count { events.append(.lost) }
            checkDeadEnd(&events)
        }
        return events
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
        undoStack.append(Snapshot(board: board, char: char, angle: angle, trail: trail, closedOnce: closedOnce, stuck: stuck,
                                  lastCloseStep: lastCloseStep))
        if undoStack.count > 200 { undoStack.removeFirst() }
    }

    /// The game moved on since the last pushUndo (a key used, ink printed, a stone glued, a step, a fall), even if the
    /// hinge came back to where it was: the snapshot must stay (Codex review 11).
    public var changedSinceUndo: Bool {
        guard let s = undoStack.last else { return false }
        return s.board != board || s.char != char || s.trail != trail || s.closedOnce != closedOnce || s.stuck != stuck
    }

    /// Forget the last pushUndo (a drag that ended where it started).
    public func dropUndo() { _ = undoStack.popLast() }

    @discardableResult
    public func undo() -> Bool {
        guard let s = undoStack.popLast() else { return false }
        board = s.board; char = s.char; angle = s.angle; trail = s.trail; closedOnce = s.closedOnce; stuck = s.stuck
        lastCloseStep = s.lastCloseStep
        if let t = s.tally { tally = t }
        posture = rules.posture(angle); shade = rules.shadows(board, angle); rideSrc = nil; won = false
        return true
    }

    /// The player's 「重新开始」: the level as it began (grids and face, the figure on the start, the trail, the book
    /// flat) — but undoable: the state before is pushed first, so one undo steps back to before the restart and the
    /// older history is still there under it.
    public func restart() {
        pushUndo()
        undoStack[undoStack.count - 1].tally = tally
        tally = FoldTally(restAngle: 0)
        board = try! Board(level: level, columnsPerPage: config.columnsPerPage)
        char = board.start; trail = [board.start]; lastCloseStep = 0; angle = 0; posture = rules.posture(0); shade = rules.shadows(board, 0)
        rideSrc = nil; won = false; closedOnce = false; stuck = false
    }

    public func reset() {
        board = try! Board(level: level, columnsPerPage: config.columnsPerPage)
        char = board.start; trail = [board.start]; lastCloseStep = 0; angle = 0; posture = .open; shade = [:]; rideSrc = nil; won = false; undoStack = []
        tally = FoldTally()
        closedOnce = false; stuck = false
    }
}
