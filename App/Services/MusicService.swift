import AVFoundation
import Combine
import Foundation
import PulseLoomCore

@MainActor final class MusicService: ObservableObject {
    enum Status { case empty, loading, ready, failed }
    @Published private(set) var status: Status = .empty
    @Published private(set) var name = ""
    @Published private(set) var analysis: AudioAnalysis?
    @Published private(set) var isPlaying = false
    @Published private(set) var position = 0.0
    @Published private(set) var requestedLevel = 0.0
    @Published var config = MusicConfiguration()
    @Published var feel: MusicFeel = .balanced
    @Published var error: String?
    var acquire: (() throws -> Void)?
    var output: ((Double, Double) throws -> Void)?
    var release: (() -> Void)?
    var finished: ((String, Double, String) -> Void)?
    var pro = false
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var decoding: Task<(URL, AudioAnalysis), Error>?
    private var tempURL: URL?
    private var activePlayed = 0.0, lastTick = 0.0, sessionPlayed = 0.0
    var duration: Double { analysis?.duration ?? 0 }
    private let makePlayer: (URL) throws -> AVAudioPlayer
    private let preparePlayer: (AVAudioPlayer) -> Bool
    init(makePlayer: @escaping (URL) throws -> AVAudioPlayer = { try AVAudioPlayer(contentsOf: $0) },
         preparePlayer: @escaping (AVAudioPlayer) -> Bool = { $0.prepareToPlay() }) {
        self.makePlayer = makePlayer
        self.preparePlayer = preparePlayer
        timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    deinit {
        timer?.invalidate()
        task?.cancel()
        decoding?.cancel()
    }
    func load(url: URL) {
        stop(reason: "replaced")
        task?.cancel()
        decoding?.cancel()
        generation = UUID()
        let token = generation
        status = .loading
        error = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let work = Task.detached(priority: .userInitiated) { try Self.decode(url: url) }
                self.decoding = work
                let result = try await withTaskCancellationHandler(
                    operation: { try await work.value }, onCancel: { work.cancel() })
                guard !Task.isCancelled, self.generation == token else {
                    try? FileManager.default.removeItem(at: result.0)
                    return
                }
                let next = try self.makePlayer(result.0)
                _ = self.preparePlayer(next)
                if let old = self.tempURL { try? FileManager.default.removeItem(at: old) }
                self.tempURL = result.0
                self.player = next
                self.analysis = result.1
                self.name = url.deletingPathExtension().lastPathComponent
                self.config.from = 0
                self.config.to = result.1.duration
                self.position = 0
                self.activePlayed = 0
                self.status = .ready
            } catch {
                guard self.generation == token else { return }
                self.status = .failed
                self.error = error.localizedDescription
            }
        }
    }
    nonisolated private static func decode(url: URL) throws -> (URL, AudioAnalysis) {
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 30 * 1024 * 1024 else {
            throw LoomError.invalid("Audio must be at most 30 MB.")
        }
        let copied = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension)
        try FileManager.default.copyItem(at: url, to: copied)
        do {
            let file = try AVAudioFile(
                forReading: copied, commonFormat: .pcmFormatFloat32, interleaved: false)
            let format = file.processingFormat
            let seconds = Double(file.length) / format.sampleRate
            guard seconds > 0, seconds <= 600 else {
                throw LoomError.invalid("Audio must be no longer than 10 minutes.")
            }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else {
                throw LoomError.invalid("Audio buffer allocation failed.")
            }
            var analyzer = try AudioAnalyzer(sampleRate: format.sampleRate)
            while file.framePosition < file.length {
                try Task.checkCancellation()
                try file.read(into: buffer, frameCount: 4096)
                guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { break }
                let count = Int(buffer.frameLength)
                let nc = Int(format.channelCount)
                var mono = [Float](repeating: 0, count: count)
                for c in 0..<nc { for i in 0..<count { mono[i] += channels[c][i] / Float(nc) } }
                try analyzer.consume(mono)
            }
            return (copied, try analyzer.finish())
        } catch {
            try? FileManager.default.removeItem(at: copied)
            throw error
        }
    }
    func demo(mist: Bool = false) {
        pause()
        task?.cancel()
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(
            mist ? "Mist-Waltz.wav" : "Petal-Steps.wav")
        do {
            try DemoAudio.wav(mist: mist).write(to: u, options: .atomic)
            load(url: u)
        } catch { self.error = error.localizedDescription }
    }
    func cancelLoad() {
        generation = UUID()
        task?.cancel()
        decoding?.cancel()
        status = player == nil ? .empty : .ready
    }
    func play() throws {
        if isPlaying {
            pause()
            return
        }
        guard let player, let analysis else {
            throw LoomError.unavailable(NSLocalizedString("music.select", comment: ""))
        }
        guard pro || activePlayed < 60 else { throw LoomError.entitlement }
        try Validation.music(config, duration: analysis.duration)
        try acquire?()
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playback, mode: .default, options: [])
        try audio.setActive(true)
        if position < config.from || position >= endpoint { position = config.from }
        player.currentTime = position
        player.volume = Float(config.volume)
        guard player.play() else { throw LoomError.unavailable("Audio could not start.") }
        lastTick = ProcessInfo.processInfo.systemUptime
        isPlaying = true
    }
    private var endpoint: Double { config.to > config.from ? min(duration, config.to) : duration }
    private func tick() {
        guard isPlaying, let player, let analysis else { return }
        let now = ProcessInfo.processInfo.systemUptime
        activePlayed += max(0, now - lastTick)
        sessionPlayed += max(0, now - lastTick)
        lastTick = now
        position = player.currentTime
        if !player.isPlaying || position >= endpoint || (!pro && activePlayed >= 60) {
            let reason = (!pro && activePlayed >= 60) ? "preview_limit" : "completed"
            pause()
            finished?(name, sessionPlayed, reason)
            sessionPlayed = 0
            if reason == "preview_limit" { error = NSLocalizedString("music.previewEnded", comment: "") }
            return
        }
        let overlay = Catalog.presets.first { $0.id == config.overlay }
        requestedLevel = analysis.level(at: position, configuration: config, overlay: overlay)
        player.volume = Float(config.volume)
        do { try output?(requestedLevel, config.sharpness) } catch {
            pause()
            self.error = error.localizedDescription
        }
    }
    func pause() {
        if isPlaying { position = player?.currentTime ?? position }
        player?.pause()
        isPlaying = false
        requestedLevel = 0
        release?()
    }
    func stop(reason: String = "stopped") {
        pause()
        if sessionPlayed > 0 {
            finished?(name, sessionPlayed, reason)
            sessionPlayed = 0
        }
        position = config.from
        player?.currentTime = position
    }
    func seek(_ value: Double) {
        let v = min(endpoint, max(config.from, value))
        position = v
        player?.currentTime = v
    }
    func apply(_ feel: MusicFeel) {
        self.feel = feel
        config.apply(feel)
    }
    func clear() {
        pause()
        cancelLoad()
        player = nil
        analysis = nil
        name = ""
        status = .empty
        position = 0
        if let tempURL { try? FileManager.default.removeItem(at: tempURL) }
        tempURL = nil
    }
}
