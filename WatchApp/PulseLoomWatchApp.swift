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
        #if DEBUG
        // Layout-only fixtures never activate connectivity or send commands.
        if let fixture = ProcessInfo.processInfo.environment["PULSELOOM_WATCH_LAYOUT_PREVIEW"] {
            reachable = fixture != "disconnected"
            allowed = fixture == "ready" || fixture == "playing"
            playing = fixture == "playing"
            title = "A long rhythm name for a small watch screen"
            return
        }
        #endif
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    func send(_ action: String, gain: Double? = nil) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["PULSELOOM_WATCH_LAYOUT_PREVIEW"] != nil { return }
        #endif
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
struct WatchControlView: View {
    @ObservedObject var client: WatchClient
    @State private var showIntensity = false
    init(client: WatchClient) {
        self.client = client
        #if DEBUG
        _showIntensity = State(initialValue: ProcessInfo.processInfo.environment["PULSELOOM_WATCH_LAYOUT_PAGE"] == "intensity")
        #endif
    }
    private let accent = Color(red: 0.74, green: 0.52, blue: 0.64)
    private var canControl: Bool { client.reachable && client.allowed && !client.busy }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if client.reachable && client.allowed {
                        Button {
                            client.send(client.playing ? "pause" : "start")
                        } label: {
                            Label(client.playing ? "watch.pause" : "watch.start",
                                  systemImage: client.playing ? "pause.fill" : "play.fill")
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .disabled(!canControl)
                        .accessibilityIdentifier("watchPlayback")
                    } else {
                        Label("watch.connect", systemImage: "iphone")
                            .font(.headline)
                        Text(client.reachable ? "watch.authorize" : "watch.openPhone")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Stop remains independent of permission and in-flight start/gain requests.
                    Button { client.send("stop") } label: {
                        Label("common.stop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(!client.reachable)
                    .accessibilityIdentifier("watchStop")

                    if client.reachable && client.allowed {
                        Text(client.title)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("watchPatternTitle")
                        NavigationLink {
                            intensityView
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("watch.intensity").font(.footnote)
                                Text(client.gain, format: .percent.precision(.fractionLength(0)))
                                    .monospacedDigit()
                            }
                        }
                        .accessibilityIdentifier("watchIntensity")
                    }
                    if let error = client.error {
                        Text(error).font(.footnote).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("watchError")
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            }
            .navigationTitle("app.name")
            .navigationDestination(isPresented: $showIntensity) { intensityView }
        }
        .tint(accent)
    }

    private var intensityView: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(client.gain, format: .percent.precision(.fractionLength(0)))
                    .font(.system(.largeTitle, design: .rounded).bold())
                    .monospacedDigit()
                    .accessibilityIdentifier("watchGainValue")
                Slider(value: $client.gain, in: 0...1, onEditingChanged: { editing in
                    if !editing { client.send("gain", gain: client.gain) }
                })
                .disabled(!canControl)
                .accessibilityLabel(Text("watch.intensity"))
                .accessibilityIdentifier("watchGainSlider")
                Button { client.send("stop") } label: {
                    Label("common.stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .tint(.red)
                .disabled(!client.reachable)
                if let error = client.error {
                    Text(error).font(.footnote).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("watch.intensity")
    }
}

@main struct PulseLoomWatchApp: App {
    @StateObject private var client = WatchClient()
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.environment["PULSELOOM_WATCH_LAYOUT_PREVIEW"] != nil {
                WatchControlView(client: client)
                    .environment(\.dynamicTypeSize,
                        ProcessInfo.processInfo.environment["PULSELOOM_WATCH_LAYOUT_LARGE_TEXT"] == "1"
                        ? .xxxLarge : .large)
            } else {
                WatchControlView(client: client)
            }
            #else
            WatchControlView(client: client)
            #endif
        }
    }
}
