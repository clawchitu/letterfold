import Foundation

/// A cell on the open sheet. `c` runs 0..<2N across both pages (0..<N left, N..<2N right), `r` top to bottom.
public struct Cell: Hashable, Sendable, Codable, CustomStringConvertible {
    public var c: Int
    public var r: Int
    public init(_ c: Int, _ r: Int) { self.c = c; self.r = r }
    public var description: String { "\(c),\(r)" }
}

/// One square of a level map. Raw values are the characters of the shared text format (levels.js).
public enum Tile: Character, Sendable, Codable, CaseIterable {
    case empty = "-", paper = ".", start = "S", goal = "G", stone = "x", key = "k"
    case door = "D", openDoor = "o", ink = "i", tab = "p"
    /// Glue (vol. 2, design-v2c1 §1): paper you can stand on; the first close pulls the stone facing it onto itself.
    case glue = "g"

    /// Something you can stand on.
    public var isFloor: Bool { [.paper, .start, .goal, .key, .ink, .openDoor, .tab, .glue].contains(self) }
    /// Something that blocks the stacked cell when the book is closed.
    public var isBlock: Bool { self == .stone || self == .door }
    /// Stones block the light; paper and ink let it through.
    public var isOpaque: Bool { self == .stone }
}

/// The three postures of the book. The web prototype calls them open / pop / fold.
public enum Posture: String, Sendable, Codable { case open, standing, closed }

/// Angle thresholds, in degrees of fold (0 = flat, 90 = standing L, 180 = closed).
public struct FoldConfig: Sendable, Codable, Equatable {
    public var columnsPerPage: Int
    /// At or above: closed, stacked tiles connect.
    public var foldMin: Double
    /// Between popMin and popMax (inclusive): standing, pop-up tabs bridge the crease.
    public var popMin: Double
    public var popMax: Double
    /// From shadeMin until foldMin the leaning right page casts shadows onto the left page.
    public var shadeMin: Double

    public init(columnsPerPage: Int = 4, foldMin: Double = 155, popMin: Double = 60, popMax: Double = 120, shadeMin: Double = 91) {
        self.columnsPerPage = columnsPerPage; self.foldMin = foldMin; self.popMin = popMin; self.popMax = popMax; self.shadeMin = shadeMin
    }
    public static let standard = FoldConfig()

    public func posture(for a: Double) -> Posture {
        if a >= foldMin { return .closed }
        if a >= popMin && a <= popMax { return .standing }
        return .open
    }
    /// Open, but leaning far enough to cast shadows (the UI calls this 'lean').
    public func isLeaning(_ a: Double) -> Bool { posture(for: a) != .closed && a >= shadeMin }
}

/// What the JS solver (tools/check.js) said about a level; the Swift solver must agree.
public struct Expectation: Sendable, Codable, Equatable {
    public var solvable: Bool
    public var changes: Int?
    public var needsFold: Bool
    public var needsPop: Bool
    public var needsShade: Bool?
    public var needsRide: Bool?
    public var needsKey: Bool?
    public var needsInk: Bool?
    /// Vol. 2: unsolvable with the glue wiped off (glue as a tool).
    public var needsGlue: Bool?
    /// Vol. 2: closing really moves a stone across (glue as a trap).
    public var glueFires: Bool?
    /// Vol. 2 ch. 6: unsolvable without turning the page (three-page levels only).
    public var needsFlip: Bool?
    public var stepped15: Bool
    /// tools/check.js `analyse()` (design-difficulty.md §2); the Swift `Difficulty` port must agree.
    public var difficulty: Difficulty.Summary?

    /// The solver flag a level declares in `needs` ("needsFold", …), or nil for an unknown name.
    public func flag(_ name: String) -> Bool? {
        switch name {
        case "needsFold": return needsFold
        case "needsPop": return needsPop
        case "needsShade": return needsShade
        case "needsRide": return needsRide
        case "needsKey": return needsKey
        case "needsInk": return needsInk
        case "needsGlue": return needsGlue
        case "glueFires": return glueFires
        case "needsFlip": return needsFlip
        default: return nil
        }
    }
}

public struct Level: Sendable, Codable, Identifiable, Equatable {
    public var id: String
    public var map: [String]
    public var expect: Expectation?
    /// The difficulty band the designer declared (levels.js `tier`: teach / easy / mid / hard / final).
    public var tier: String?
    /// Solver flags that must stay true (levels.js `needs`), so an edit cannot quietly remove the level's mechanic.
    public var needs: [String]?
    /// 「暗信」 (difficulty-postmortem.md §4): an optional side letter, outside the strict chapter unlock and the chapter count.
    public var optional: Bool?
    /// The declared minimal solution length (posture changes + steps, gen.js `len`), checked against `Solver.shortest`.
    public var len: Int?
    /// The proto solver's shortest solution (gen.js bestPath) as [c, r, fold angle, stamped] states (tools/level-extras.js).
    public var solution: [[Int]]?
    public var isOptional: Bool { optional == true }
    public init(id: String, map: [String], expect: Expectation? = nil, tier: String? = nil, needs: [String]? = nil) {
        self.id = id; self.map = map; self.expect = expect; self.tier = tier; self.needs = needs
    }
}

/// levels.json, exported from fold-proto by `node tools/export.js`.
public struct LevelPack: Sendable, Codable {
    /// levels.json v2 ships physical page angles (plan.md §12.1: 180° flat, 0° shut): closedMax 25, popMin 60,
    /// popMax 120, shadeMax 89. The rules still reason in fold degrees (= 180 − physical); this is the one conversion.
    /// v1 files (foldMin / shadeMin in fold degrees) still decode.
    public struct Thresholds: Sendable, Codable {
        public var foldMin, popMin, popMax, shadeMin: Double
        enum CodingKeys: String, CodingKey { case closedMax, popMin, popMax, shadeMax, foldMin, shadeMin }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            let lo = try c.decode(Double.self, forKey: .popMin), hi = try c.decode(Double.self, forKey: .popMax)
            if let closed = try c.decodeIfPresent(Double.self, forKey: .closedMax) {
                foldMin = 180 - closed
                shadeMin = 180 - (try c.decode(Double.self, forKey: .shadeMax))
                popMin = 180 - hi; popMax = 180 - lo
            } else {
                foldMin = try c.decode(Double.self, forKey: .foldMin); shadeMin = try c.decode(Double.self, forKey: .shadeMin)
                popMin = lo; popMax = hi
            }
        }
        public func encode(to e: Encoder) throws {
            var c = e.container(keyedBy: CodingKeys.self)
            try c.encode(180 - foldMin, forKey: .closedMax); try c.encode(180 - popMax, forKey: .popMin)
            try c.encode(180 - popMin, forKey: .popMax); try c.encode(180 - shadeMin, forKey: .shadeMax)
        }
    }
    public var version: Int
    public var columnsPerPage: Int
    public var thresholds: Thresholds
    public var levels: [Level]

    public var config: FoldConfig {
        FoldConfig(columnsPerPage: columnsPerPage, foldMin: thresholds.foldMin, popMin: thresholds.popMin,
                   popMax: thresholds.popMax, shadeMin: thresholds.shadeMin)
    }

    public static func decode(_ data: Data) throws -> LevelPack { try JSONDecoder().decode(LevelPack.self, from: data) }

    /// The levels shipped inside FoldCore.
    public static func bundled() throws -> LevelPack {
        guard let url = Bundle.module.url(forResource: "levels", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try decode(Data(contentsOf: url))
    }
}

public enum FoldError: Error, Equatable { case badTile(Character), noStart, ragged }

/// The mutable grid of a level. A map row is 2N columns (left | right page) or 3N (left | right | third page, the
/// back of the right leaf: vol. 2 ch. 6 「翻」, fold-proto design-ch6.md). Only two pages are visible: columns N..<2N
/// read whichever page faces the left page (`face` 0 = right, 1 = third), so every rule works on the facing page.
public struct Board: Sendable, Equatable {
    public var grid: [[Tile]]
    public let h: Int
    /// Visible width: always 2N.
    public let w: Int
    public let start: Cell
    /// 2 or 3.
    public let pages: Int
    /// Which page of the right leaf faces the left page: 0 = right page, 1 = third page.
    public var face: Int = 0
    let n: Int

    public init(level: Level, columnsPerPage n: Int = 4) throws {
        var start: Cell?
        let width = level.map.first?.count ?? 0
        guard width == 2 * n || width == 3 * n else { throw FoldError.ragged }
        grid = try level.map.enumerated().map { r, row in
            guard row.count == width else { throw FoldError.ragged }
            return try row.enumerated().map { c, ch in
                guard let t = Tile(rawValue: ch) else { throw FoldError.badTile(ch) }
                if t == .start { start = Cell(c, r) }
                return t
            }
        }
        guard let start, start.c < 2 * n else { throw FoldError.noStart }
        self.start = start
        self.n = n
        pages = width / n
        h = grid.count
        w = 2 * n
    }

    /// The grid column behind a visible column (logic.js colOf).
    @inline(__always) public func colOf(_ c: Int) -> Int { face == 1 && c >= n ? c + n : c }

    public subscript(c: Int, r: Int) -> Tile {
        get { r >= 0 && r < h && c >= 0 && c < w ? grid[r][colOf(c)] : .empty }
        set { grid[r][colOf(c)] = newValue }
    }
    public subscript(cell: Cell) -> Tile { self[cell.c, cell.r] }

    /// The first visible cell holding `t` (the facing page only).
    public func first(_ t: Tile) -> Cell? {
        for r in 0..<h { for c in 0..<w where self[c, r] == t { return Cell(c, r) } }
        return nil
    }

    /// Where a tile lies on any page: its visible cell and the face it shows on (nil = the left page, always visible).
    public func locate(_ t: Tile) -> (cell: Cell, face: Int?)? {
        for r in 0..<h { for c in 0..<grid[r].count where grid[r][c] == t {
            if c < n { return (Cell(c, r), nil) }
            return c < 2 * n ? (Cell(c, r), 0) : (Cell(c - n, r), 1)
        } }
        return nil
    }
}
