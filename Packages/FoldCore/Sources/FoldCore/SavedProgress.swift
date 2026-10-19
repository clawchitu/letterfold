import Foundation

/// Saved progress: the IDs of the levels delivered. Up to 0.1 (8) the app saved positions in the level pack
/// (`fold.done`), which 0.1 (9) shifts by inserting two chapter-2 levels (Codex review 7 #1). `load` reads the ID
/// list, or once converts an old positional save through the layout it was written against.
public enum SavedProgress {
    /// UserDefaults keys: the ID list (0.1 (9) on) and the old positional list (0.1 (8) and earlier).
    public static let idsKey = "fold.doneIDs"
    public static let legacyKey = "fold.done"

    /// The level order of 0.1 (1)–(8): chapters 1–3, 17 levels (earlier builds were prefixes of it).
    public static let legacyLayout: [String] = [
        "bridge", "facing", "back", "key", "ink",
        "stand", "twoBridges", "standClose", "doorBridge", "inkBridge", "crease",
        "shadow", "press", "lock", "ride", "rideBack", "lamp",
    ]

    /// The delivered level IDs from what is saved: the ID list if there is one, else the old positions mapped
    /// through `legacyLayout` (positions outside it are dropped).
    public static func migrate(ids: [String]?, legacyIndices: [Int]?) -> Set<String> {
        if let ids { return Set(ids) }
        return Set((legacyIndices ?? []).compactMap { legacyLayout.indices.contains($0) ? legacyLayout[$0] : nil })
    }

    /// Reads (and, the first time, migrates) the saved progress. After a migration the ID list is written and the
    /// positional list removed, so it runs once.
    public static func load(_ d: UserDefaults = .standard) -> Set<String> {
        let ids = d.stringArray(forKey: idsKey)
        let set = migrate(ids: ids, legacyIndices: d.array(forKey: legacyKey) as? [Int])
        if ids == nil { save(set, d) }
        return set
    }

    public static func save(_ set: Set<String>, _ d: UserDefaults = .standard) {
        d.set(set.sorted(), forKey: idsKey)
        d.removeObject(forKey: legacyKey)
    }

    public static func reset(_ d: UserDefaults = .standard) {
        d.removeObject(forKey: idsKey); d.removeObject(forKey: legacyKey)
    }
}
