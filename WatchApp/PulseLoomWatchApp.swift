import Combine
import SwiftUI
import WatchConnectivity

@MainActor final class WatchClient: NSObject, ObservableObject, WCSessionDelegate {
    @Published var reachable = false
    @Published var allowed = false
    @Published var playing = false
    @Published var busy = false
    @Published var title = "Pulse Loom"
    @Published var gain = 0.55
    @Published var error: String?
    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    func send(_ action: String, gain: Double? = nil) {
        guard WCSession.default.isReachable else {
            error = NSLocalizedString("watch.openPhone", comment: "")
            return
        }
        guard action == "stop" || allowed else {
            error = NSLocalizedString("watch.authorize", comment: "")
            return
        }
        var m: [String: Any] = ["action": action]
        if let gain { m["gain"] = gain }
        busy = true
        WCSession.default.sendMessage(
            m,
            replyHandler: { [weak self] response in
                Task { @MainActor in
                    guard let self else { return }
                    self.busy = false
                    if response["ok"] as? Bool != true {
                        self.error =
                            response["error"] as? String ?? NSLocalizedString("common.error", comment: "")
                    }
                    self.apply(response)
                }
            },
            errorHandler: { [weak self] error in
                Task { @MainActor in
                    self?.busy = false
                    self?.error = error.localizedDescription
                }
            })
    }
    private func apply(_ c: [String: Any]) {
        if let s = c["title"] as? String { title = s }
        if let g = c["gain"] as? Double, g.isFinite { gain = min(1, max(0, g)) }
        if let p = c["playing"] as? Bool { playing = p }
        if let a = c["allowed"] as? Bool { allowed = a }
    }
    nonisolated func session(
        _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.reachable = session.isReachable
            self.error = error?.localizedDescription
            self.apply(session.receivedApplicationContext)
        }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.reachable = session.isReachable
            if !self.reachable {
                self.allowed = false
                self.playing = false
            }
        }
    }
    nonisolated func session(
        _ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]
    ) { Task { @MainActor in self.apply(applicationContext) } }
}
@main struct PulseLoomWatchApp: App {
    @StateObject private var client = WatchClient()
    var body: some Scene {
        WindowGroup {
            ScrollView {
                VStack(spacing: 12) {
                    Text("Pulse Loom").font(.system(.headline, design: .serif).italic())
                    Text(client.title).font(.headline).lineLimit(2)
                    if !client.reachable {
                        Text("watch.openPhone").font(.footnote)
                    } else if !client.allowed {
                        Text("watch.authorize").font(.footnote)
                    }
                    HStack {
                        Button {
                            client.send(client.playing ? "pause" : "start")
                        } label: {
                            Image(systemName: client.playing ? "pause" : "power")
                        }.disabled(!client.allowed || client.busy)
                        Button {
                            client.send("stop")
                        } label: {
                            Image(systemName: "stop")
                        }
                    }
                    Text("\(Int(client.gain*100))%").monospacedDigit()
                    Slider(
                        value: $client.gain, in: 0...1,
                        onEditingChanged: { editing in if !editing { client.send("gain", gain: client.gain) }
                        }
                    ).disabled(!client.allowed)
                    if let error = client.error { Text(error).font(.footnote).foregroundStyle(.orange) }
                }.padding(.horizontal, 8)
            }.tint(Color(red: 0.74, green: 0.52, blue: 0.64))
        }
    }
}
