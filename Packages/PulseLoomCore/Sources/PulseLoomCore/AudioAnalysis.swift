import Foundation

public struct AudioAnalysis: Codable, Equatable, Sendable {
    public var step: Double
    public var energy: [Double]
    public var onsets: [Double]
    public var bpm: Int?
    public var duration: Double
    public init(step: Double, energy: [Double], onsets: [Double], bpm: Int?, duration: Double) {
        self.step = step
        self.energy = energy
        self.onsets = onsets
        self.bpm = bpm
        self.duration = duration
    }
    public func level(at seconds: Double, configuration c: MusicConfiguration, overlay: HapticPattern? = nil)
        -> Double
    {
        let t = seconds + c.offset
        guard t >= 0, t < duration, !energy.isEmpty else { return 0 }
        let pos = t / step
        let index = min(energy.count - 1, Int(pos))
        let next = min(energy.count - 1, index + 1)
        let e = energy[index] + (energy[next] - energy[index]) * (pos - Double(index))
        var lo = 0
        var hi = onsets.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if onsets[mid] <= t { lo = mid + 1 } else { hi = mid }
        }
        let beat = lo > 0 ? max(0, 1 - (t - onsets[lo - 1]) / 0.11) : 0
        let sensitivity = 0.5 + c.sensitivity * 1.5
        var v = c.mapping == .beats ? beat : e
        if c.mapping == .blend, let p = overlay {
            v = v * (1 - c.overlayMix) + PatternMath.level(p, at: seconds) * c.overlayMix
        }
        return min(1, max(0, v * sensitivity)) * c.gain
    }
}
/// Streaming RMS envelopes avoid retaining a 10-minute uncompressed PCM file in RAM.
public struct AudioAnalyzer: Sendable {
    private let sampleRate: Double
    private let window: Int
    private var count = 0
    private var sum = 0.0
    private var rms: [Double] = []
    private var total = 0
    public init(sampleRate: Double) throws {
        guard Validation.finite(sampleRate, 8000...192000) else {
            throw LoomError.invalid("Unsupported sample rate.")
        }
        self.sampleRate = sampleRate
        window = max(1, Int(sampleRate * 0.02))
    }
    public mutating func consume(_ samples: [Float]) throws {
        guard Double(total + samples.count) / sampleRate <= 600.1 else {
            throw LoomError.invalid("Audio exceeds 10 minutes.")
        }
        for s in samples {
            guard s.isFinite else { throw LoomError.invalid("Audio contains invalid samples.") }
            let x = Double(s)
            sum += x * x
            count += 1
            total += 1
            if count == window {
                rms.append(sqrt(sum / Double(count)))
                sum = 0
                count = 0
            }
        }
    }
    public func finish() throws -> AudioAnalysis {
        guard total > 0 else { throw LoomError.invalid("Empty audio.") }
        var raw = rms
        if count > 0 { raw.append(sqrt(sum / Double(count))) }
        let sorted = raw.sorted()
        let ref = max(0.00001, sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))])
        let energy = raw.map { min(1, $0 / ref) }
        var onsets: [Double] = []
        var avg = 0.0
        var prev = 0.0
        let step = Double(window) / sampleRate
        for (i, e) in energy.enumerated() {
            let t = Double(i) * step
            if e > max(0.15, avg * 1.35), e - prev > 0.12, t - (onsets.last ?? -1) > 0.16 { onsets.append(t) }
            avg = avg * 0.92 + e * 0.08
            prev = e
        }
        let intervals = zip(onsets, onsets.dropFirst()).map { $1 - $0 }.filter { (0.25...1.5).contains($0) }
            .sorted()
        var bpm: Int?
        if intervals.count >= 4 {
            let median = intervals[intervals.count / 2]
            let good = intervals.filter { abs($0 - median) < median * 0.2 }.count
            if Double(good) / Double(intervals.count) >= 0.65 { bpm = Int((60 / median).rounded()) }
        }
        return AudioAnalysis(
            step: step, energy: energy, onsets: onsets, bpm: bpm, duration: Double(total) / sampleRate)
    }
}
public enum DemoAudio {
    /// Original synthesized tones; no third-party recordings or network requests.
    public static func wav(seconds: Double = 48, mist: Bool = false) -> Data {
        let rate = 22050
        let n = Int(max(0.1, min(60, seconds)) * Double(rate))
        var pcm = Data()
        pcm.reserveCapacity(n * 2)
        for i in 0..<n {
            let t = Double(i) / Double(rate)
            let period = mist ? 0.625 : 0.5
            let b = t.truncatingRemainder(dividingBy: period)
            let pitch = mist ? 220.0 : 261.63
            let x =
                (sin(2 * Double.pi * pitch * t) * 0.17 + sin(2 * Double.pi * pitch * 1.5 * t) * 0.09)
                * exp(-b * 8)
            let kick = sin(2 * Double.pi * (70 - 25 * min(1, b / 0.12)) * b) * exp(-b * 27) * 0.25
            let fade = min(1, t / 0.2) * min(1, (Double(n - i) / Double(rate)) / 0.3)
            var v = Int16(max(-1, min(1, (x + kick) * fade)) * Double(Int16.max)).littleEndian
            withUnsafeBytes(of: &v) { pcm.append(contentsOf: $0) }
        }
        var out = Data()
        func text(_ s: String) { out.append(contentsOf: s.utf8) }
        func u16(_ v: UInt16) {
            var x = v.littleEndian
            withUnsafeBytes(of: &x) { out.append(contentsOf: $0) }
        }
        func u32(_ v: UInt32) {
            var x = v.littleEndian
            withUnsafeBytes(of: &x) { out.append(contentsOf: $0) }
        }
        text("RIFF")
        u32(UInt32(36 + pcm.count))
        text("WAVEfmt ")
        u32(16)
        u16(1)
        u16(1)
        u32(UInt32(rate))
        u32(UInt32(rate * 2))
        u16(2)
        u16(16)
        text("data")
        u32(UInt32(pcm.count))
        out.append(pcm)
        return out
    }
}
