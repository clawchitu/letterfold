import Foundation

/// Strings live in Localizable.xcstrings / Levels.xcstrings, generated from fold-proto's i18n.js by tools/make-strings.js.
/// Templates keep the web's named placeholders ({name}); Korean particles are written {word:이} and chosen by the
/// final consonant, as in i18n.js. Named placeholders let every language keep its own word order.
enum L10n {
    static var lang: String { Bundle.main.preferredLocalizations.first ?? "en" }

    static func t(_ key: String, _ params: [String: any CustomStringConvertible] = [:]) -> String {
        fill(Bundle.main.localizedString(forKey: key, value: key, table: "Localizable"), params)
    }

    static func level(_ id: String) -> (name: String, line: String, hint: String) {
        func get(_ part: String) -> String { Bundle.main.localizedString(forKey: "\(id).\(part)", value: id, table: "Levels") }
        return (get("name"), get("line"), get("hint"))
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
