import AVFoundation
import Combine
import Foundation

@MainActor final class SoundscapeService: ObservableObject {
    @Published var levels: [Double] = [0.25, 0, 0]
    @Published private(set) var active = false
    @Published var error: String?
    private var players: [AVAudioPlayer] = []
    var willStart: (() -> Void)?
    func play() throws {
        willStart?()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: .mixWithOthers)
        try session.setActive(true)
        if players.isEmpty {
            players = try (0..<3).map { i in
                let p = try AVAudioPlayer(data: Self.wav(kind: i))
                p.numberOfLoops = -1
                p.prepareToPlay()
                return p
            }
        }
        for (i, p) in players.enumerated() {
            p.volume = Float(levels[i])
            guard p.play() else {
                stop()
                throw NSError(
                    domain: "Soundscape", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Soundscape could not start."])
            }
        }
        active = true
    }
    func update() { for (i, p) in players.enumerated() { p.setVolume(Float(levels[i]), fadeDuration: 0.15) } }
    func stop() {
        players.forEach { $0.stop() }
        active = false
    }
    func preset(_ i: Int) {
        levels = i == 0 ? [0.35, 0.08, 0] : i == 1 ? [0, 0.3, 0.06] : [0.03, 0.03, 0.18]
        update()
    }
    private static func wav(kind: Int) -> Data {
        let rate = 22050
        let n = rate * 4
        var seed: UInt64 = 12345 + UInt64(kind)
        var brown = 0.0
        var pcm = Data()
        for i in 0..<n {
            seed = 2_862_933_555_777_941_757 &* seed &+ 3_037_000_493
            let noise = Double(seed >> 32) / Double(UInt32.max) * 2 - 1
            brown = brown * 0.985 + noise * 0.015
            let t = Double(i) / Double(rate)
            let fade = min(1, Double(i) / 400) * min(1, Double(n - i) / 400)
            let x =
                (kind == 0 ? noise * 0.15 : kind == 1 ? brown * 0.8 : sin(t * 2 * Double.pi * 110) * 0.15)
                * fade
            var v = Int16(max(-1, min(1, x)) * 32767).littleEndian
            withUnsafeBytes(of: &v) { pcm.append(contentsOf: $0) }
        }
        var d = Data()
        func txt(_ x: String) { d.append(contentsOf: x.utf8) }
        func u32(_ x: UInt32) {
            var x = x.littleEndian
            withUnsafeBytes(of: &x) { d.append(contentsOf: $0) }
        }
        func u16(_ x: UInt16) {
            var x = x.littleEndian
            withUnsafeBytes(of: &x) { d.append(contentsOf: $0) }
        }
        txt("RIFF")
        u32(UInt32(pcm.count + 36))
        txt("WAVEfmt ")
        u32(16)
        u16(1)
        u16(1)
        u32(UInt32(rate))
        u32(UInt32(rate * 2))
        u16(2)
        u16(16)
        txt("data")
        u32(UInt32(pcm.count))
        d.append(pcm)
        return d
    }
}
