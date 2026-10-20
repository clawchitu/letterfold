import SwiftUI

/// Strings live in Localizable.xcstrings / Levels.xcstrings, generated from fold-proto's i18n.js by tools/make-strings.js.
/// Templates keep the web's named placeholders ({name}); Korean particles are written {word:이} and chosen by the
/// final consonant, as in i18n.js. Named placeholders let every language keep its own word order.
/// The language follows the system unless Settings picks one (read through AppSettings, so views re-render).
enum L10n {
    static let supported = ["zh-Hans", "en", "ja", "ko"]
    private static var bundles: [String: Bundle] = [:]

    static var lang: String {
        let pick = AppSettings.shared.language
        return pick.isEmpty ? (Bundle.main.preferredLocalizations.first ?? "en") : pick
    }

    static var bundle: Bundle {
        let pick = AppSettings.shared.language
        if pick.isEmpty { return .main }
        if let b = bundles[pick] { return b }
        guard let path = Bundle.main.path(forResource: pick, ofType: "lproj"), let b = Bundle(path: path) else { return .main }
        bundles[pick] = b
        return b
    }

    static var locale: Locale { Locale(identifier: lang) }

    static func t(_ key: String, _ params: [String: any CustomStringConvertible] = [:]) -> String {
        fill(bundle.localizedString(forKey: key, value: key, table: "Localizable"), params)
    }

    static func level(_ id: String) -> (name: String, line: String, hint: String) {
        func get(_ part: String) -> String { bundle.localizedString(forKey: "\(id).\(part)", value: id, table: "Levels") }
        return (get("name"), get("line"), get("hint"))
    }

    /// A level's first hint (the 「?」 ladder's first rung), if it has one.
    static func levelHint1(_ id: String) -> String? {
        let v = bundle.localizedString(forKey: "\(id).hint1", value: "", table: "Levels")
        return v.isEmpty || v == "\(id).hint1" ? nil : v
    }

    private static let placeholder = try! NSRegularExpression(pattern: #"\{(\w+)(?::([^}]+))?\}"#)

    static func fill(_ template: String, _ params: [String: any CustomStringConvertible]) -> String {
        let ns = template as NSString
        var out = template
        for m in placeholder.matches(in: template, range: NSRange(location: 0, length: ns.length)).reversed() {
            let name = ns.substring(with: m.range(at: 1))
            let value = params[name].map { String(describing: $0) } ?? ""
            var rep = value
            if m.range(at: 2).location != NSNotFound {
                let part = ns.substring(with: m.range(at: 2))
                rep = lang.hasPrefix("ko") ? josa(value, part) : value
            }
            out = (out as NSString).replacingCharacters(in: m.range, with: rep)
        }
        return out
    }

    /// Korean particles: pick the form by the final consonant (batchim) of the last Hangul syllable.
    static func josa(_ word: String, _ p: String) -> String {
        let table: [String: (String, String)] = ["이": ("이", "가"), "을": ("을", "를"), "은": ("은", "는"), "과": ("과", "와"), "으로": ("으로", "로")]
        guard let pair = table[p] else { return word + p }
        guard let last = word.unicodeScalars.last else { return word + pair.1 }
        let code = Int(last.value) - 0xAC00
        if code < 0 || code > 11171 { return word + pair.1 }
        let fin = code % 28
        if p == "으로" { return word + (fin == 0 || fin == 8 ? "로" : "으로") }
        return word + (fin != 0 ? pair.0 : pair.1)
    }

    /// English sentences start with a capital; a no-op for the CJK scripts.
    static func cap(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }
}

extension L10n {
    /// Chinese display type: Songti and PingFang set 「，、；：。」 a full em wide (they have no `halt` feature), which
    /// leaves a visible hole mid-line (「河很宽，　纸很薄。」). Tighten the empty half after a mark that does not end a
    /// line. A no-op in other languages (Hiragino has proper Japanese spacing).
    static func tight(_ s: String, size: CGFloat) -> AttributedString {
        var a = AttributedString(s)
        guard lang.hasPrefix("zh") else { return a }
        let marks: Set<Character> = ["，", "、", "；", "：", "。"]
        var i = a.characters.startIndex
        while i < a.characters.endIndex {
            let next = a.characters.index(after: i)
            if marks.contains(a.characters[i]), next < a.characters.endIndex, a.characters[next] != "\n" {
                a[i..<next].kern = -size * 0.42
            }
            i = next
        }
        return a
    }
}
