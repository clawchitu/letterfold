import XCTest
import AVFoundation
@testable import FoldCore

/// The background music's offline render goes through the same DSP and the same AVAudioEngine graph as the game
/// (manual rendering mode): no NaN, no clipping, the peak near gen.py's -18 dBFS, the sparse pacing.
final class MusicTests: XCTestCase {
    private func dbfs(_ x: Float) -> Double { 20 * log10(max(1e-9, Double(x))) }
    private func peak(_ r: MusicEngine.Render) -> Float {
        max(r.left.map(abs).max() ?? 0, r.right.map(abs).max() ?? 0)
    }

    func testChapterOneRenderIsCleanAndAtLevel() throws {
        let r = try MusicEngine.renderOffline(seconds: 30, chapter: 1, accents: [11, 21.5], wins: [26])
        XCTAssertEqual(r.left.count, Int(30 * r.sampleRate))
        XCTAssertFalse(r.left.contains { !$0.isFinite } || r.right.contains { !$0.isFinite }, "NaN / inf in the render")
        let p = dbfs(peak(r))
        XCTAssertLessThan(p, -12, "clipping headroom: peak \(p) dBFS")
        XCTAssertEqual(p, -18, accuracy: 2.5, "peak \(p) dBFS, want about -18")
        XCTAssertGreaterThan(r.notes, 3)
        let rms = sqrt(r.left.reduce(0) { $0 + Double($1 * $1) } / Double(r.left.count))
        XCTAssertGreaterThan(dbfs(Float(rms)), -60, "near silent")
    }

    func testEveryVolumeRendersClean() throws {
        for ch in [5, 7, 8, 9] {
            let r = try MusicEngine.renderOffline(seconds: 12, chapter: ch, seed: UInt64(ch), accents: [4])
            XCTAssertFalse(r.left.contains { !$0.isFinite } || r.right.contains { !$0.isFinite }, "ch\(ch): NaN")
            XCTAssertLessThan(dbfs(peak(r)), -14, "ch\(ch) peak")
        }
    }

    /// gen.py variant b's pacing: about 22 notes in 90 s.
    func testSparsePacing() throws {
        let r = try MusicEngine.renderOffline(seconds: 90, chapter: 1, seed: 2718, plucks: true, bed: false)
        XCTAssert((14...32).contains(r.notes), "\(r.notes) notes in 90 s")
    }

    /// MUSIC_OUT=<dir> (TEST_RUNNER_MUSIC_OUT under xcodebuild): write WAVs to listen to and measure.
    func testWriteRecordings() throws {
        guard let dir = ProcessInfo.processInfo.environment["MUSIC_OUT"] else { throw XCTSkip("MUSIC_OUT not set") }
        func write(_ r: MusicEngine.Render, _ name: String) throws {
            let f = AVAudioFormat(standardFormatWithSampleRate: r.sampleRate, channels: 2)!
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
            let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: r.sampleRate,
                                                                   AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16,
                                                                   AVLinearPCMIsFloatKey: false],
                                       commonFormat: .pcmFormatFloat32, interleaved: false)
            let b = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: AVAudioFrameCount(r.left.count))!
            b.frameLength = AVAudioFrameCount(r.left.count)
            r.left.withUnsafeBufferPointer { b.floatChannelData![0].update(from: $0.baseAddress!, count: r.left.count) }
            r.right.withUnsafeBufferPointer { b.floatChannelData![1].update(from: $0.baseAddress!, count: r.right.count) }
            try file.write(from: b)
        }
        let acc = [34.0, 51.5, 66.0]   // gen.py fold_accents
        try write(try MusicEngine.renderOffline(seconds: 92, chapter: 1, seed: 2718, accents: acc), "native-ch1.wav")
        try write(try MusicEngine.renderOffline(seconds: 92, chapter: 1, seed: 2718, bed: false), "native-ch1-plucks.wav")
        try write(try MusicEngine.renderOffline(seconds: 92, chapter: 1, seed: 2718, plucks: false), "native-ch1-bed.wav")
        for (v, ch) in [(1, 1), (2, 5), (3, 9)] {
            try write(try MusicEngine.renderOffline(seconds: 20, chapter: ch, seed: 2718, accents: [9]), "native-vol\(v).wav")
        }
        for ch in [7, 8] {
            try write(try MusicEngine.renderOffline(seconds: 20, chapter: ch, seed: 2718, accents: [9]), "native-ch\(ch).wav")
        }
    }
}
