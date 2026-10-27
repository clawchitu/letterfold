import Foundation

/// What a square says to VoiceOver, as facts (the app turns them into words in four languages): a port of a11y.js
/// `label()` for the open book, and — new in 0.1 (14), from the 10/20 blind playtest — the shut book described as it
/// is: one stack per square, what lies on top, which page you are on, and why a stack cannot be entered. Open-book
/// predictions ("closing lays the card here", "closing here crushes you") are never said about a shut book.
public struct CellFacts: Sendable, Equatable {
    public enum Note: Sendable, Equatable {
        // open book (a11y.js): what closing will do here
        case fallsHere(Tile), doorKey, glueTakes, stoneGlued(col: Int), crushedHere, inkPrints, tabBridge
        case stoneShadow(col: Int), keyOpens(col: Int), inkTo(col: Int), covers(col: Int)
        // shut book
        /// Paper on one page, a stone (or a locked door) on the other: the stack cannot be entered.
        case stackBlocked
        /// Nothing on the top page here: you would stand on the bottom page, through the gap.
        case throughGap
    }
    public enum Here: Sendable, Equatable {
        /// The figure is on this square (shut: in this stack, on the top page when `onTop`).
        case you(onTop: Bool?)
    }
    /// The tile to name: open, the square's own; shut, what shows on top of the stack (the top page unless it is a gap).
    public var tile: Tile
    /// Open: a gap with a shadow on it (walkable).
    public var shadow = false
    /// Open: an angle gate — true while it stands (walkable), false while it lies down; nil elsewhere. A gate is never
    /// `shadow`: it stays put, a shadow moves (Codex review 20 #2).
    public var gateOpen: Bool?
    /// Standing tabs (the bridge is up).
    public var tabUp = false
    /// Shut: the goal lies in this stack under or over what is named.
    public var goalInStack = false
    public var here: Here?
    public var note: Note?
}

extension Rules {
    /// The facts about the square at `cell` (shut: the stack whose bottom-page cell this is; a top-page cell names the
    /// same stack). `figure` is where the figure is drawn (the app may show it under a stone while being crushed).
    /// `angle`: the hinge now (fold degrees); below upright the next close first passes it, so the notes are read off
    /// the board that pass leaves (loose stones rolled, the figure holding hers; Codex review 21 #3).
    public func facts(_ b: Board, _ cell: Cell, posture p: Posture, shade: [Cell: Int], figure: Cell, angle: Double? = nil) -> CellFacts {
        if p == .closed { return stackFacts(b, Cell(proj(cell.c), cell.r), figure: figure) }
        let c = cell.c, r = cell.r
        let tl = b[cell], m = mirror(c)
        var f = CellFacts(tile: tl)
        f.shadow = shade[cell] != nil && !tl.isFloor && tl != .gate
        if tl == .gate { f.gateOpen = Rules.gateStands(shade, cell) }
        f.tabUp = tl == .tab && p == .standing
        if figure == cell { f.here = .you(onTop: nil) }
        // the notes predict the next close, and every press bleeds the wet ink first: read both squares off the bled
        // board (a blot that covers glue spoils it, so the facing stone stays put; Codex review 19 #2)
        var nb = b
        if let a = angle, !standing(a) { roll(&nb, fig: figure) }
        let (T, M) = closeTiles(nb, cell, m)
        if !isRight(c) {
            if T == .empty && (M.isFloor || M.isOpaque) { f.note = .fallsHere(M) }
            else if T == .door && M == .key { f.note = .doorKey }
            else if T == .glue && M.isOpaque { f.note = .glueTakes }
            else if T.isOpaque && M == .glue { f.note = .stoneGlued(col: m + 1) }
            else if T.isFloor && M.isOpaque { f.note = .crushedHere }
            else if (T == .ink || T == .wetInk) && M == .empty { f.note = .inkPrints }
            else if T == .tab && c == n - 1 && M == .tab { f.note = .tabBridge }
        } else {
            if T.isOpaque && M == .glue { f.note = .stoneGlued(col: m + 1) }
            else if T.isOpaque { f.note = .stoneShadow(col: m + 1) }
            else if T == .glue && M.isOpaque { f.note = .glueTakes }
            else if T == .key && M == .door { f.note = .keyOpens(col: m + 1) }
            else if (T == .ink || T == .wetInk) && M == .empty { f.note = .inkTo(col: m + 1) }
            else if T == .tab && c == n && M == .tab { f.note = .tabBridge }
            else if T.isFloor && M == .empty { f.note = .covers(col: m + 1) }
        }
        return f
    }

    /// This square and its facing square as the next press finds them: after the wet ink has bled one ring.
    func closeTiles(_ b: Board, _ cell: Cell, _ m: Int) -> (Tile, Tile) {
        guard b.grid.contains(where: { $0.contains(.wetInk) }) else { return (b[cell], b[m, cell.r]) }
        var pb = b
        _ = bleed(&pb)
        return (pb[cell], pb[m, cell.r])
    }

    /// The shut book: the stack at bottom-page column q. The right page lies on top of the left.
    func stackFacts(_ b: Board, _ q: Cell, figure: Cell) -> CellFacts {
        let bottom = b[q], topCell = Cell(mirror(q.c), q.r), top = b[topCell]
        var f = CellFacts(tile: top == .empty ? bottom : top)
        f.goalInStack = (top == .goal || bottom == .goal) && f.tile != .goal
        if figure == q { f.here = .you(onTop: false) } else if figure == topCell { f.here = .you(onTop: true) }
        if !foldOpen(b, q.c, q.r) {
            // a stone or a locked door on either page shuts the stack, paper or not (the rule the playtest never saw)
            if (top.isFloor && bottom.isBlock) || (bottom.isFloor && top.isBlock) { f.note = .stackBlocked }
        } else if top == .empty && bottom.isFloor {
            f.note = .throughGap
        }
        return f
    }
}
