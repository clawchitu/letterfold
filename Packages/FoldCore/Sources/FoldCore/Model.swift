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

    /// Something you can stand on.
    public var isFloor: Bool { [.paper, .start, .goal, .key, .ink, .openDoor, .tab].contains(self) }
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
    public var stepped15: Bool
}

public struct Level: Sendable, Codable, Identifiable, Equatable {
    public var id: String
    public var map: [String]
    public var expect: Expectation?
    public init(id: String, map: [String], expect: Expectation? = nil) { self.id = id; self.map = map; self.expect = expect }
}

/// levels.json, exported from fold-proto by `node tools/export.js`.
public struct LevelPack: Sendable, Codable {
    public struct Thresholds: Sendable, Codable { public var foldMin, popMin, popMax, shadeMin: Double }
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

/// The mutable grid of a level.
public struct Board: Sendable, Equatable {
    public var grid: [[Tile]]
    public let h: Int
    public let w: Int
    public let start: Cell

    public init(level: Level, columnsPerPage n: Int = 4) throws {
        var start: Cell?
        grid = try level.map.enumerated().map { r, row in
            guard row.count == 2 * n else { throw FoldError.ragged }
            return try row.enumerated().map { c, ch in
                guard let t = Tile(rawValue: ch) else { throw FoldError.badTile(ch) }
                if t == .start { start = Cell(c, r) }
                return t
            }
        }
        guard let start else { throw FoldError.noStart }
        self.start = start
        h = grid.count
        w = 2 * n
    }

    public subscript(c: Int, r: Int) -> Tile {
        get { r >= 0 && r < h && c >= 0 && c < w ? grid[r][c] : .empty }
        set { grid[r][c] = newValue }
    }
    public subscript(cell: Cell) -> Tile { self[cell.c, cell.r] }

    public func first(_ t: Tile) -> Cell? {
        for r in 0..<h { for c in 0..<w where grid[r][c] == t { return Cell(c, r) } }
        return nil
    }
}
