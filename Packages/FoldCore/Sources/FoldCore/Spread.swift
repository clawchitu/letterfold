import Foundation

/// How the open sheet is laid out on screen. The rules always work in map coordinates (Cell: column c across both
/// pages, row r); this maps them to page slots and back.
///
/// - `.horizontalCrease` (phone, portrait; design-spec §4): the crease runs left-right. The top page is the map's
///   right page (columns 2N-1 ... N from the top down) and folds down onto the bottom page, which is the map's left
///   page (columns N-1 ... 0 from the crease down). A map *row* is a screen *column*, left to right. Closing lays
///   column c onto column 2N-1-c, which is exactly the slot mirrored across the crease.
/// - `.verticalCrease` (iPhone Duo, iPad landscape): the web layout. Left page columns 0 ..< N, right page N ..< 2N,
///   rows top to bottom; the right page folds over to the left.
public struct Spread: Sendable, Equatable {
    public enum Orientation: String, Sendable { case horizontalCrease, verticalCrease }
    /// The page that stays put (the map's left page) and the one that folds onto it (the map's right page).
    public enum Page: Sendable, Equatable { case fixed, folding }

    public let orientation: Orientation
    public let columnsPerPage: Int
    public let rows: Int

    public init(_ orientation: Orientation, columnsPerPage n: Int = 4, rows: Int) {
        self.orientation = orientation; columnsPerPage = n; self.rows = rows
    }

    /// Slots across and down one page.
    public var slotsAcross: Int { orientation == .horizontalCrease ? rows : columnsPerPage }
    public var slotsDown: Int { orientation == .horizontalCrease ? columnsPerPage : rows }

    public func page(of c: Int) -> Page { c >= columnsPerPage ? .folding : .fixed }

    /// The slot of a cell on its own page, measured from that page's top-left corner as drawn face up.
    public func slot(_ cell: Cell) -> (x: Int, y: Int) {
        let n = columnsPerPage
        switch orientation {
        case .horizontalCrease:
            return (cell.r, cell.c >= n ? 2 * n - 1 - cell.c : n - 1 - cell.c)
        case .verticalCrease:
            return (cell.c >= n ? cell.c - n : cell.c, cell.r)
        }
    }

    /// The cell at a slot of a page.
    public func cell(page: Page, x: Int, y: Int) -> Cell {
        let n = columnsPerPage
        switch orientation {
        case .horizontalCrease:
            return Cell(page == .folding ? 2 * n - 1 - y : n - 1 - y, x)
        case .verticalCrease:
            return Cell(page == .folding ? x + n : x, y)
        }
    }

    /// Where a cell ends up when the book is closed: the slot on the fixed page it stacks onto.
    public func stackSlot(_ cell: Cell) -> (x: Int, y: Int) {
        let n = columnsPerPage
        return slot(Cell(cell.c >= n ? 2 * n - 1 - cell.c : cell.c, cell.r))
    }

    /// Screen directions, for the step buttons and VoiceOver: one slot up/down/left/right on screen.
    public enum Direction: String, Sendable, CaseIterable { case up, down, left, right }

    /// The map-coordinate step that moves one slot in a screen direction, for a cell on `page`
    /// (or on the closed stack, which is drawn on the fixed page).
    public func delta(_ d: Direction, on page: Page) -> (dc: Int, dr: Int) {
        switch orientation {
        case .horizontalCrease:
            // Up the screen is towards higher columns on both pages (the bottom page counts up towards the crease,
            // the top page counts up away from it); left and right walk along a map row.
            switch d { case .up: return (1, 0); case .down: return (-1, 0); case .left: return (0, -1); case .right: return (0, 1) }
        case .verticalCrease:
            switch d { case .up: return (0, -1); case .down: return (0, 1); case .left: return (-1, 0); case .right: return (1, 0) }
        }
    }
}
