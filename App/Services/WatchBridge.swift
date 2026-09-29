import Combine
import Foundation
import WatchConnectivity

@MainActor final class WatchBridge: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var reachable = false
    @Published private(set) var installed = false
    @Published var allowed = false {
        didSet { publish(title: lastTitle, gain: lastGain, playing: lastPlaying) }
    }
    private var lastTitle = "Pulse Loom", lastGain = 0.55, lastPlaying = false
    @Published var error: String?
    var foreground = true { didSet { publish(title: lastTitle, gain: lastGain, playing: lastPlaying) } }
    var onCommand: (([String: Any]) throws -> [String: Any])?
    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    func publish(title: String, gain: Double, playing: Bool) {
        lastTitle = title
        lastGain = gain
        lastPlaying = playing
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        reachable = WCSession.default.isReachable
        installed = WCSession.default.isWatchAppInstalled
        do {
            try WCSession.default.updateApplicationContext([
                "title": title, "gain": gain, "playing": playing, "allowed": allowed && foreground,
            ])
        } catch { self.error = error.localizedDescription }
    }
    nonisolated func session(
        _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.reachable = session.isReachable
            self.installed = session.isWatchAppInstalled
            self.error = error?.localizedDescription
            self.publish(title: self.lastTitle, gain: self.lastGain, playing: self.lastPlaying)
        }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in
            self.allowed = false
            self.reachable = false
        }
    }
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.reachable = session.isReachable
            if !self.reachable { self.allowed = false }
            self.publish(title: self.lastTitle, gain: self.lastGain, playing: self.lastPlaying)
        }
    }
    nonisolated func session(
        _ session: WCSession, didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            do {
                let action = message["action"] as? String ?? ""
                if action != "stop" && (!self.allowed || !self.foreground) {
                    throw NSError(
                        domain: "Watch", code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey: NSLocalizedString("watch.permission", comment: "")
                        ])
                }
                replyHandler(try self.onCommand?(message) ?? ["ok": false])
            } catch { replyHandler(["ok": false, "error": error.localizedDescription]) }
        }
    }
}
