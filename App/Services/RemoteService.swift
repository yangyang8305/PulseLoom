import Combine
import CryptoKit
import Foundation
import PulseLoomCore

/// The relay sees encrypted frames, room IDs and connection metadata; never the AES key or pattern commands.
@MainActor final class RemoteService: ObservableObject {
    enum Role: String, Codable { case sender, receiver }
    enum State { case disconnected, connecting, connected }
    struct Invitation: Codable {
        var room: String
        var token: String
        var key: String
        var server: String
    }
    private struct Created: Decodable {
        var room: String
        var sender_token: String
        var receiver_token: String
    }
    @Published private(set) var state: State = .disconnected
    @Published private(set) var role: Role = .sender
    @Published private(set) var shareURL: URL?
    @Published private(set) var peerPresent = false
    @Published private(set) var consent = RemoteConsent()
    @Published var error: String?
    @Published var limit = 0.4 {
        didSet {
            consent.limit = limit.isFinite ? min(1, max(0, limit)) : 0
            // A receiver lowering the ceiling immediately stops the old output.
            if role == .receiver && limit < oldValue { onSafetyStop?() }
        }
    }
    var onCommand: ((RemoteCommand, Double?) -> Void)?
    var onSafetyStop: (() -> Void)?
    var foreground = true
    var entitlementReader: (() -> Bool)?
    var hasPro: Bool { entitlementReader?() ?? pro }
    var controlID: String { connectionNonce }
    var pro = false {
        didSet { if !pro && oldValue { authorize(false) } }
    }
    private var socket: (any RemoteSocketIO)?
    private var receiveTask: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var key: SymmetricKey?
    private var room = ""
    private var sequence: UInt64 = 0
    private var peerAt = ProcessInfo.processInfo.systemUptime
    private var generation = UUID()
    private var connectionNonce = UUID().uuidString
    private var peerNonce: String?
    private var peerProtocol: Int?
    private var storedInvitation: Invitation?
    private let configuredServer: URL?
    private let makeSocket: (URL) -> any RemoteSocketIO
    init(server: URL? = nil, makeSocket: @escaping (URL) -> any RemoteSocketIO = { AppleRemoteSocket(url: $0) }) {
        configuredServer = server
        self.makeSocket = makeSocket
    }
    var server: URL? {
        if let configuredServer { return configuredServer }
        guard let s = Bundle.main.object(forInfoDictionaryKey: "RelayBaseURL") as? String,
            let url = URL(string: s), url.scheme == "https", url.host != nil
        else { return nil }
        return url
    }
    func create() async throws {
        guard hasPro, foreground else { throw LoomError.entitlement }
        guard let server else {
            throw LoomError.unavailable(NSLocalizedString("remote.notConfigured", comment: ""))
        }
        var req = URLRequest(url: server.appendingPathComponent("v1/rooms"))
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        let (data, res) = try await URLSession.shared.data(for: req)
        guard (res as? HTTPURLResponse)?.statusCode == 201 else {
            throw LoomError.unavailable("Relay could not create a room.")
        }
        guard hasPro, foreground else { throw LoomError.entitlement }
        let r = try JSONDecoder().decode(Created.self, from: data)
        let symmetric = SymmetricKey(size: .bits256)
        let encoded = symmetric.withUnsafeBytes { Data($0).base64EncodedString() }
        let receiver = Invitation(
            room: r.room, token: r.receiver_token, key: encoded, server: server.absoluteString)
        var parts = URLComponents()
        parts.scheme = "pulseloom"
        parts.host = "invite"
        parts.fragment = try JSONEncoder().encode(receiver).base64EncodedString()
        shareURL = parts.url
        let mine = Invitation(
            room: r.room, token: r.sender_token, key: encoded, server: server.absoluteString)
        try connect(mine, role: .sender)
    }
    func join(_ string: String) throws {
        guard let u = URLComponents(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
            u.scheme == "pulseloom", u.host == "invite",
            let fragment = u.fragment, fragment.count < 8192, let data = Data(base64Encoded: fragment)
        else { throw LoomError.invalid("Invalid invitation.") }
        let i = try JSONDecoder().decode(Invitation.self, from: data)
        guard i.server == server?.absoluteString else {
            throw LoomError.invalid("Invitation belongs to a different relay server.")
        }
        try connect(i, role: .receiver)
    }
    func connect(_ i: Invitation, role: Role) throws {
        guard hasPro, foreground else { throw LoomError.entitlement }
        guard let keyData = Data(base64Encoded: i.key), keyData.count == 32, i.room.count <= 64,
            i.token.count <= 128,
            let base = server
        else { throw LoomError.invalid("Invalid invitation credentials.") }
        disconnect()
        generation = UUID()
        let gen = generation
        connectionNonce = UUID().uuidString
        peerNonce = nil
        peerProtocol = nil
        self.key = SymmetricKey(data: keyData)
        self.role = role
        room = i.room
        storedInvitation = i
        state = .connecting
        var c = URLComponents(
            url: base.appendingPathComponent("v1/rooms/\(i.room)/ws"), resolvingAgainstBaseURL: false)!
        c.scheme = "wss"
        let task = makeSocket(c.url!)
        socket = task
        task.resume()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            do {
                let auth: [String: String] = ["type": "auth", "role": role.rawValue, "token": i.token]
                let s = String(data: try JSONEncoder().encode(auth), encoding: .utf8)!
                try await task.send(.string(s))
                while !Task.isCancelled, self.generation == gen {
                    let message = try await task.receive()
                    guard self.generation == gen else { return }
                    let data: Data
                    switch message {
                    case .data(let d): data = d
                    case .string(let s): data = Data(s.utf8)
                    @unknown default: continue
                    }
                    try self.handle(data)
                }
            } catch {
                guard self.generation == gen else { return }
                self.error = error.localizedDescription
                self.disconnect()
            }
        }
    }
    func handle(_ data: Data) throws {
        guard data.count <= 65536,
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = object["type"] as? String
        else { throw LoomError.invalid("Invalid relay frame.") }
        if type == "ready" {
            state = .connected
            startHeartbeat()
            return
        }
        if type == "peer_joined" {
            peerPresent = true
            peerAt = ProcessInfo.processInfo.systemUptime
            peerNonce = nil
            peerProtocol = nil
            connectionNonce = UUID().uuidString
            consent.resetConnection()
            onSafetyStop?()
            announceConnection()
            return
        }
        if type == "peer_left" {
            peerPresent = false
            consent.revoke()
            onSafetyStop?()
            return
        }
        guard type == "data", let s = object["payload"] as? String, let payload = Data(base64Encoded: s),
            let key
        else { return }
        let box = try AES.GCM.SealedBox(combined: payload)
        let plain = try AES.GCM.open(box, using: key, authenticating: Data(room.utf8))
        let command = try JSONDecoder().decode(RemoteCommand.self, from: plain)
        peerAt = ProcessInfo.processInfo.systemUptime
        peerPresent = true
        if command.action == "ping" {
            peerProtocol = command.protocolVersion
            if peerProtocol != RemoteCommand.currentProtocol {
                consent.revoke()
                peerNonce = nil
                onSafetyStop?()
                error = "Both devices must support the current remote safety protocol."
                return
            }
            if role == .sender { peerNonce = command.connectionID }
        }
        if role == .receiver {
            if ["start", "gain"].contains(command.action), command.connectionID != connectionNonce {
                throw LoomError.invalid("Command belongs to an old connection.")
            }
            do {
                if ["start", "gain"].contains(command.action) {
                    guard peerProtocol == RemoteCommand.currentProtocol,
                        command.protocolVersion == RemoteCommand.currentProtocol
                    else { throw LoomError.unavailable("Remote safety handshake is incomplete.") }
                }
                let actual = try consent.accept(command, foreground: foreground, pro: hasPro)
                if command.action == "emergencyStop" {
                    latchEmergency()
                } else if command.action == "stop" {
                    onSafetyStop?()
                } else if command.action != "ping" {
                    onCommand?(command, actual)
                }
            } catch {
                self.error = error.localizedDescription
                if !hasPro { authorize(false) } else { onSafetyStop?() }
            }
        } else if command.action == "emergencyStop" || command.action == "stop" {
            onSafetyStop?()
        }
    }
    func send(action: String, patternID: String? = nil, gain: Double? = nil) async throws {
        guard ["start", "gain", "stop", "emergencyStop", "ping"].contains(action) else { throw LoomError.invalid("Unknown command.") }
        if ["start", "gain"].contains(action) {
            guard hasPro, foreground, role == .sender else { throw LoomError.entitlement }
        }
        guard state == .connected, let socket, let key else {
            throw LoomError.unavailable("Remote connection is not ready.")
        }
        if role == .sender && ["start", "gain"].contains(action)
            && (peerNonce == nil || peerProtocol != RemoteCommand.currentProtocol) {
            throw LoomError.unavailable("Waiting for receiver handshake.")
        }
        sequence &+= 1
        let command = RemoteCommand(
            sequence: sequence, action: action, patternID: patternID, gain: gain,
            connectionID: role == .receiver ? connectionNonce : peerNonce)
        let box = try AES.GCM.seal(JSONEncoder().encode(command), using: key, authenticating: Data(room.utf8))
        guard let bytes = box.combined else { throw LoomError.unavailable("Unable to encrypt command.") }
        let json = try JSONSerialization.data(withJSONObject: [
            "type": "data", "payload": bytes.base64EncodedString(),
        ])
        try await socket.send(.data(json))
    }
    func authorize(_ value: Bool) {
        if value {
            guard hasPro, foreground, state == .connected else {
                error = "Pro and foreground access are required before authorizing remote control."
                return
            }
            guard peerPresent, peerProtocol == RemoteCommand.currentProtocol else {
                error = "Wait for a compatible receiver/sender handshake before allowing control."
                return
            }
            consent.grant()
        } else {
            consent.revoke()
            if role == .receiver {
                connectionNonce = UUID().uuidString
                announceConnection()
            }
            onSafetyStop?()
        }
    }
    private func latchEmergency() {
        consent.revoke()
        if role == .receiver {
            // Commands queued before the emergency cannot run after a new manual grant.
            connectionNonce = UUID().uuidString
            announceConnection()
        }
        onSafetyStop?()
    }
    private func announceConnection() {
        guard state == .connected else { return }
        let expected = generation
        Task {
            guard generation == expected, state == .connected else { return }
            do { try await send(action: "ping") } catch {
                guard generation == expected else { return }
                self.error = error.localizedDescription
            }
        }
    }
    func emergency() {
        latchEmergency()
        let expected = generation
        Task {
            // A delayed emergency from an old room must never target a new connection.
            guard generation == expected, state == .connected else { return }
            do { try await send(action: "emergencyStop") } catch {
                guard generation == expected else { return }
                self.error = error.localizedDescription
                disconnect()
            }
        }
    }
    func reconnect() throws {
        guard let i = storedInvitation else {
            throw LoomError.unavailable("Create or accept an invitation first.")
        }
        try connect(i, role: role)
    }
    private func startHeartbeat() {
        heartbeat?.cancel()
        peerAt = ProcessInfo.processInfo.systemUptime
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
                guard let self else { return }
                if self.peerPresent && ProcessInfo.processInfo.systemUptime - self.peerAt > 10 {
                    self.consent.revoke()
                    self.onSafetyStop?()
                    self.peerPresent = false
                    self.error = NSLocalizedString("remote.timeout", comment: "")
                }
                do { try await self.send(action: "ping") } catch {
                    self.error = error.localizedDescription
                    self.disconnect()
                    return
                }
            }
        }
    }
    func disconnect() {
        generation = UUID()
        receiveTask?.cancel()
        heartbeat?.cancel()
        socket?.cancel()
        socket = nil
        key = nil
        state = .disconnected
        peerPresent = false
        peerNonce = nil
        peerProtocol = nil
        consent.resetConnection()
        sequence = 0
        onSafetyStop?()
    }
}
