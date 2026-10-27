// Checks the 行 → háng IPA hint (L10n.speech) with the real zh-CN voice: renders each row phrase with the hint and
// compares the samples to the same phrase with 航 (háng) and 形 (xíng). Run: swiftc -O tools/speech-ipa.swift -o /tmp/sipa && /tmp/sipa
import AVFoundation
import Foundation
let ipa = "hɑŋ˧˥"   // = L10n.hangIPA
let synth = AVSpeechSynthesizer()
func render(_ a: NSAttributedString) -> [Float] {
    let u = AVSpeechUtterance(attributedString: a); u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
    var out: [Float] = []; var done = false
    synth.write(u) { b in
        guard let p = b as? AVAudioPCMBuffer else { return }
        if p.frameLength == 0 { done = true; return }
        if let f = p.floatChannelData { out += UnsafeBufferPointer(start: f[0], count: Int(p.frameLength)) }
        else if let i = p.int16ChannelData { out += UnsafeBufferPointer(start: i[0], count: Int(p.frameLength)).map { Float($0) / 32768 } }
    }
    while !done { RunLoop.current.run(until: Date() + 0.01) }
    return out
}
func hinted(_ s: String) -> NSAttributedString {
    let a = NSMutableAttributedString(string: s); let ns = s as NSString
    var r = ns.range(of: "行")
    while r.location != NSNotFound {
        a.addAttribute(NSAttributedString.Key(AVSpeechSynthesisIPANotationAttribute), value: ipa, range: r)
        r = ns.range(of: "行", range: NSRange(location: r.location + 1, length: ns.length - r.location - 1))
    }
    return a
}
var bad = 0
for s in CommandLine.arguments.dropFirst() {
    let h = render(hinted(s)), hang = render(NSAttributedString(string: s.replacingOccurrences(of: "行", with: "航"))),
        xing = render(NSAttributedString(string: s.replacingOccurrences(of: "行", with: "形"))), plain = render(NSAttributedString(string: s))
    let ok = h == hang && h != xing
    if !ok { bad += 1 }
    print(ok ? "OK  " : "FAIL", s, "| plain reads", plain == xing ? "xíng" : plain == hang ? "háng" : "?")
}
exit(bad == 0 ? 0 : 1)
