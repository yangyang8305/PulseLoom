import AVFoundation
import Combine
import PulseLoomCore
import SwiftUI
import WidgetKit

func T(_ key: String) -> String { NSLocalizedString(key, comment: "") }
func timeText(_ seconds: Double) -> String {
    let n = max(0, Int(seconds.rounded(.up)))
    return String(format: "%02d:%02d", n / 60, n % 60)
}
enum MainTab: Int, CaseIterable { case home, music, create, my }
enum SheetRoute: String, Identifiable {
    case presets, timer, adjust, themes, premium, musicSources, mixes, focus
    var id: String { rawValue }
}
struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

@MainActor final class AppModel: ObservableObject {
    let library = LibraryStore()
    let playback = PlaybackCoordinator()
    let music = MusicService()
    let sound = SoundscapeService()
    let purchase = PurchaseService()
    let cloud = CloudSyncService()
    let remote = RemoteService()
    let watch = WatchBridge()
    let systemMusic = SystemMusicService()
    let diagnostics = Diagnostics()
    @Published var tab: MainTab = .home
    @Published var sheet: SheetRoute?
    @Published var error: String?
    @Published var share: SharedFile?
    @Published var privacyHidden = false
    @Published var inviteInput = ""
    @Published var showInvite = false
    private var observers = Set<AnyCancellable>()
    private var notifications: [NSObjectProtocol] = []
    var prefs: Preferences { library.snapshot.preferences }
    var current: HapticPattern {
        library.pattern(prefs.lastPattern) ?? Catalog.presets.first ?? HapticPattern(name: "Unavailable")
    }
    var pro: Bool { purchase.pro }
    var theme: ThemeDefinition {
        let fallback = Catalog.themes.first ?? .fallback
        return Catalog.themes.first { $0.id == prefs.theme && ($0.free || pro) } ?? fallback
    }
    init() {
        for publisher in [
            library.objectWillChange, playback.objectWillChange, music.objectWillChange,
            sound.objectWillChange, purchase.objectWillChange, cloud.objectWillChange,
            remote.objectWillChange, watch.objectWillChange, systemMusic.objectWillChange,
        ] {
            publisher.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observers)
        }
        playback.willAcquire = { [weak self] kind in
            guard let self else { return }
            if kind != "music" { self.music.pause() }
            self.systemMusic.pause()
            if kind != "routine" && kind != "breath" { self.sound.stop() }
        }
        playback.didStopExternal = { [weak self] _ in
            guard let self else { return }
            self.music.pause()
            self.sound.stop()
        }
        playback.didFinish = { [weak self] name, kind, seconds, reason in
            self?.library.record(title: name, kind: kind, seconds: seconds, reason: reason)
        }
        music.acquire = { [weak self] in
            guard let self else { return }
            self.systemMusic.pause()
            self.sound.stop()
            self.playback.stop(reason: "music", notifyExternal: false)
        }
        music.output = { [weak self] value, sharp in
            try self?.playback.stream(value, sharpness: sharp, source: "music")
        }
        music.release = { [weak self] in
            guard let self, self.playback.kind == "music" else { return }
            self.playback.stopStream()
        }
        music.finished = { [weak self] title, seconds, reason in
            self?.library.record(title: title, kind: "music", seconds: seconds, reason: reason)
        }
        sound.willStart = { [weak self] in
            self?.music.pause()
            self?.systemMusic.pause()
        }
        systemMusic.willPlay = { [weak self] in self?.stopAll() }
        remote.onSafetyStop = { [weak self] in if self?.playback.kind == "remote" { self?.playback.stop() } }
        remote.onCommand = { [weak self] command, gain in
            guard let self else { return }
            self.perform {
                switch command.action {
                case "start":
                    guard let p = self.library.pattern(command.patternID ?? "") else {
                        throw LoomError.invalid("Unknown pattern.")
                    }
                    try self.playback.begin(
                        p, duration: min(600, self.prefs.timer), gain: gain ?? 0, kind: "remote")
                case "gain": try self.playback.adjust(gain: gain ?? 0, speed: 1, sharp: self.prefs.sharpness)
                default: break
                }
            }
        }
        watch.onCommand = { [weak self] message in
            guard let self else { return ["ok": false] }
            switch message["action"] as? String {
            case "stop": self.stopAll()
            case "start": try self.beginCurrent()
            case "pause": self.playback.pause()
            case "gain":
                guard let g = message["gain"] as? Double, g.isFinite, (0...1).contains(g) else {
                    throw LoomError.invalid("Invalid intensity.")
                }
                try self.library.preferences { $0.gain = g }
                try self.adjust()
            default: throw LoomError.invalid("Unknown watch action.")
            }
            return [
                "ok": true, "playing": self.playback.isPlaying, "gain": self.prefs.gain,
                "title": self.current.displayName(),
            ]
        }
        library.$snapshot.dropFirst().sink { [weak self] _ in Task { @MainActor in self?.updatePreferences() }
        }.store(in: &observers)
        purchase.$pro.sink { [weak self] value in
            Task { @MainActor in
                guard let self else { return }
                self.music.pro = value
                self.remote.pro = value
                if let p = self.playback.activePattern, !Entitlements.canPlay(p, pro: value) {
                    self.playback.stop()
                }
            }
        }.store(in: &observers)
        let center = NotificationCenter.default
        notifications.append(
            center.addObserver(forName: .loomShortcutRequested, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.consumeShortcut() }
            })
        notifications.append(
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) {
                [weak self] _ in Task { @MainActor in self?.interrupt(T("error.interruption")) }
            })
        notifications.append(
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) {
                [weak self] n in
                if let raw = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                    AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable
                {
                    Task { @MainActor in self?.interrupt(T("error.audioRoute")) }
                }
            })
        notifications.append(
            center.addObserver(
                forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    if ProcessInfo.processInfo.thermalState == .serious
                        || ProcessInfo.processInfo.thermalState == .critical
                    {
                        self?.interrupt(T("error.temperature"))
                    }
                }
            })
        updatePreferences()
        if Catalog.presets.count != 16 || Catalog.themes.count != 6 { error = T("error.catalog") }
    }
    deinit { notifications.forEach { NotificationCenter.default.removeObserver($0) } }
    func perform(_ operation: () throws -> Void) {
        do { try operation() } catch LoomError.entitlement { sheet = .premium } catch {
            self.error = error.localizedDescription
            diagnostics.record(code: "OPERATION_FAILED", category: "ui")
        }
    }
    func asyncPerform(_ operation: @escaping @MainActor () async throws -> Void) {
        Task {
            do { try await operation() } catch LoomError.entitlement { sheet = .premium } catch {
                self.error = error.localizedDescription
            }
        }
    }
    func pref<Value>(_ key: WritableKeyPath<Preferences, Value>) -> Binding<Value> {
        Binding(
            get: { self.prefs[keyPath: key] },
            set: { v in self.perform { try self.library.preferences { $0[keyPath: key] = v } } })
    }
    func updatePreferences() {
        playback.keepAwake = prefs.keepAwake
        diagnostics.enabled = prefs.diagnosticsEnabled
        publishWidget()
        watch.publish(title: current.displayName(), gain: prefs.gain, playing: playback.isPlaying)
    }
    func select(_ p: HapticPattern) {
        perform {
            guard Entitlements.canPlay(p, pro: pro) else { throw LoomError.entitlement }
            let running = playback.isPlaying && playback.kind == "pattern"
            try library.preferences { $0.lastPattern = p.id }
            if running {
                try playback.switchPattern(p, gain: prefs.gain, speed: prefs.speed, sharp: prefs.sharpness)
            }
            sheet = nil
        }
    }
    func beginCurrent() throws {
        guard Entitlements.canPlay(current, pro: pro) else { throw LoomError.entitlement }
        try playback.begin(
            current, duration: prefs.timer, gain: prefs.gain, speed: prefs.speed, sharp: prefs.sharpness)
        updatePreferences()
    }
    func toggle() {
        perform {
            if playback.isPlaying {
                playback.pause()
            } else if [.paused, .interrupted].contains(playback.state),
                playback.activePattern?.id == current.id
            {
                try playback.resume()
            } else {
                try beginCurrent()
            }
        }
    }
    func adjust() throws { try playback.adjust(gain: prefs.gain, speed: prefs.speed, sharp: prefs.sharpness) }
    func setTimer(_ value: Double) {
        perform {
            guard Validation.finite(value, 30...600) else { throw LoomError.invalid("Invalid timer.") }
            try library.preferences { $0.timer = value }
            if [.playing, .paused].contains(playback.state) { try playback.setRemaining(value) }
            sheet = nil
        }
    }
    func preview(_ p: HapticPattern) {
        perform {
            var x = p
            x.loop = false
            try playback.begin(
                x, duration: min(8, p.durationMS / 1000), gain: prefs.gain, sharp: prefs.sharpness,
                kind: "preview")
        }
    }
    func stopAll() {
        music.stop()
        systemMusic.pause()
        sound.stop()
        playback.stop()
        updatePreferences()
    }
    func interrupt(_ reason: String) {
        music.pause()
        systemMusic.pause()
        sound.stop()
        playback.interrupt(reason)
        remote.authorize(false)
        watch.allowed = false
        perform { try library.flushDraft() }
    }
    func phase(_ phase: ScenePhase) {
        let active = phase == .active
        playback.foreground = active
        remote.foreground = active
        watch.foreground = active
        if !active {
            privacyHidden = prefs.privacyCover
            interrupt(T("error.interruption"))
        } else {
            privacyHidden = false
            consumeShortcut()
            updatePreferences()
        }
    }
    func export<TValue: Encodable>(_ value: TValue, name: String) {
        perform {
            let u = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".json")
            try FileCodec.encode(value).write(to: u, options: .atomic)
            presentShare(u)
        }
    }
    func exportDiagnostics() {
        perform {
            let u = FileManager.default.temporaryDirectory.appendingPathComponent(
                "PulseLoom-diagnostics.json")
            try diagnostics.data().write(to: u, options: .atomic)
            presentShare(u)
        }
    }
    private func presentShare(_ url: URL) {
        if sheet != nil {
            sheet = nil
            Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                share = SharedFile(url: url)
            }
        } else {
            share = SharedFile(url: url)
        }
    }
    /// Cloud requests yield the main actor. Never replace edits made while awaiting the network.
    func syncLibrary(choice: String? = nil) async throws {
        guard pro else { throw LoomError.entitlement }
        let before = library.snapshot
        let incoming: LibrarySnapshot?
        if let choice {
            incoming = try await cloud.resolve(local: before, choice: choice)
        } else {
            incoming = try await cloud.synchronize(before)
        }
        guard var incoming else { return }
        let latest = library.snapshot
        if latest != before {
            incoming = try CloudMerge.preservingBoth(local: latest, remote: incoming)
            incoming.preferences = latest.preferences
            incoming.notes = latest.notes
            incoming.mixes = latest.mixes
            let ids = Set((Catalog.presets + incoming.custom).map(\.id))
            if !ids.contains(incoming.preferences.lastPattern) { incoming.preferences.lastPattern = "p02" }
        }
        try library.replace(incoming)
    }
    func read(_ url: URL, max: Int = 5 * 1024 * 1024) throws -> Data {
        let accessible = url.startAccessingSecurityScopedResource()
        defer { if accessible { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= max else { throw LoomError.invalid("File too large or empty.") }
        return try Data(contentsOf: url)
    }
    func handleURL(_ url: URL) {
        guard url.scheme == "pulseloom" else { return }
        if url.host == "invite" {
            inviteInput = url.absoluteString
            tab = .my
            showInvite = true
            return
        }
        guard url.host == "pattern" else { return }
        let id = url.pathComponents.last ?? ""
        if let p = library.pattern(id) {
            tab = .home
            select(p)
        }
        // External links never start haptics or a transaction.
    }
    private func consumeShortcut() {
        guard playback.foreground,
            let group = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String,
            let preferences = UserDefaults(suiteName: group),
            let id = preferences.string(forKey: "shortcutPattern")
        else { return }
        preferences.removeObject(forKey: "shortcutPattern")
        guard let pattern = library.pattern(id) else { return }
        tab = .home
        select(pattern)  // Navigation and selection only. No shortcut starts haptic output.
    }
    func publishWidget() {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String,
            let d = UserDefaults(suiteName: group)
        else { return }
        d.set(
            prefs.widgetPrivate
                ? T("widget.privateTitle")
                : (library.pattern(prefs.widgetPattern)?.displayName() ?? T("app.name")), forKey: "title")
        d.set(prefs.widgetPattern, forKey: "patternID")
        d.set(prefs.theme, forKey: "theme")
        WidgetCenter.shared.reloadAllTimelines()
    }
}
