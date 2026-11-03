import Foundation

/// Saved progress: the IDs of the levels delivered. Up to 0.1 (8) the app saved positions in the level pack
/// (`fold.done`), which 0.1 (9) shifts by inserting two chapter-2 levels (Codex review 7 #1). `load` reads the ID
/// list, or once converts an old positional save through the layout it was written against.
public enum SavedProgress {
    /// UserDefaults keys: the ID list (0.1 (9) on) and the old positional list (0.1 (8) and earlier).
    public static let idsKey = "fold.doneIDs"
    public static let legacyKey = "fold.done"
    /// 「跳过这一封」 (hint-skip): the levels set aside without a win. Not delivered: they only open the next level
    /// inside their chapter (`levelOpen`); chapters, 暗信, letters and endings still count `done` alone. A save
    /// without the key (every save before this build) reads as no skips.
    public static let skippedKey = "fold.skippedIDs"

    /// The level order of 0.1 (1)–(8): chapters 1–3, 17 levels (earlier builds were prefixes of it).
    public static let legacyLayout: [String] = [
        "bridge", "facing", "back", "key", "ink",
        "stand", "twoBridges", "standClose", "doorBridge", "inkBridge", "crease",
        "shadow", "press", "lock", "ride", "rideBack", "lamp",
    ]

    /// 0.1 (14) redrew chapter 5's last four levels under new IDs (fold-proto difficulty-postmortem.md §4). A letter
    /// delivered in 0.1 (13) stays delivered: each old ID counts for the level now in its slot. (Vol. 1's 21 redrawn
    /// levels kept their IDs, so their saves need nothing.)
    public static let renamed: [String: String] = [
        "shadowFirst": "oldHome", "oneClose": "ferry", "rideFirst": "twiceClosed", "stuckPage": "twoLamps",
    ]

    /// The delivered level IDs from what is saved: the ID list if there is one (renamed IDs carried to their
    /// successors), else the old positions mapped through `legacyLayout` (positions outside it are dropped).
    public static func migrate(ids: [String]?, legacyIndices: [Int]?) -> Set<String> {
        if let ids { return Set(ids).union(ids.compactMap { renamed[$0] }) }
        return Set((legacyIndices ?? []).compactMap { legacyLayout.indices.contains($0) ? legacyLayout[$0] : nil })
    }

    /// Reads (and, the first time, migrates) the saved progress. After a migration the ID list is written and the
    /// positional list removed, so it runs once.
    public static func load(_ d: UserDefaults = .standard) -> Set<String> {
        let ids = d.stringArray(forKey: idsKey)
        let set = migrate(ids: ids, legacyIndices: d.array(forKey: legacyKey) as? [Int])
        if ids == nil || Set(ids!) != set { save(set, d) }
        return set
    }

    public static func save(_ set: Set<String>, _ d: UserDefaults = .standard) {
        d.set(set.sorted(), forKey: idsKey)
        d.removeObject(forKey: legacyKey)
    }

    /// The strict chapter rule (owner, 0.1 (10)): a chapter opens only once every level of the previous chapter is
    /// delivered. No exception for a chapter already played: a 0.1 (8) save that finished chapters 1–2 before
    /// chapter 2 grew two levels must play those two before chapter 3 opens again.
    public static func chapterOpen(previous: [String], done: Set<String>) -> Bool {
        !previous.isEmpty && previous.allSatisfy(done.contains)
    }

    /// The level rule inside an open chapter (owner, 0.1 (17)): a delivered level replays, and the first level not yet
    /// delivered is the one to play next; every later level stays shut until it is reached. hint-skip: a level the
    /// player skipped (after seeing the whole solution) counts as reached — it replays, and the one after it opens —
    /// but never as delivered, so it does not count towards `chapterOpen`.
    public static func levelOpen(_ id: String, in chapter: [String], done: Set<String>, skipped: Set<String> = []) -> Bool {
        guard chapter.contains(id) else { return false }
        let reached = done.union(skipped)
        return reached.contains(id) || chapter.first { !reached.contains($0) } == id
    }

    /// The skipped level IDs (empty for every older save). A delivered level is never also skipped.
    public static func loadSkipped(_ d: UserDefaults = .standard, done: Set<String>) -> Set<String> {
        Set(d.stringArray(forKey: skippedKey) ?? []).subtracting(done)
    }

    public static func saveSkipped(_ set: Set<String>, _ d: UserDefaults = .standard) {
        if set.isEmpty { d.removeObject(forKey: skippedKey) } else { d.set(set.sorted(), forKey: skippedKey) }
    }

    public static func reset(_ d: UserDefaults = .standard) {
        d.removeObject(forKey: idsKey); d.removeObject(forKey: legacyKey); d.removeObject(forKey: skippedKey)
    }
}
