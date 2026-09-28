import Foundation

public struct RemoteCommand: Codable, Sendable {
    /// Version 2 distinguishes ordinary stop from a latched emergency stop.
    public static let currentProtocol = 2
    public var protocolVersion: Int? = Self.currentProtocol
    public var connectionID: String?
    public var sequence: UInt64
    public var action: String
    public var patternID: String?
    public var gain: Double?
    public init(
        sequence: UInt64, action: String, patternID: String? = nil, gain: Double? = nil,
        connectionID: String? = nil
    ) {
        self.connectionID = connectionID
        self.sequence = sequence
        self.action = action
        self.patternID = patternID
        self.gain = gain
    }
}
public struct RemoteConsent: Sendable {
    public private(set) var allowed = false
    public var limit = 0.4
    public private(set) var lastSequence: UInt64 = 0
    public init() {}
    public mutating func grant() { allowed = true }
    public mutating func revoke() { allowed = false }
    public mutating func resetConnection() {
        allowed = false
        lastSequence = 0
    }
    public mutating func accept(_ c: RemoteCommand, foreground: Bool, pro: Bool) throws -> Double? {
        guard c.sequence > lastSequence else { throw LoomError.invalid("Stale remote command.") }
        guard ["start", "stop", "emergencyStop", "gain", "ping"].contains(c.action) else {
            throw LoomError.invalid("Unknown remote command.")
        }
        lastSequence = c.sequence
        if c.action == "emergencyStop" {
            revoke()
            return nil
        }
        // Ordinary stop ends output, not the previously granted connection permission.
        if c.action == "stop" || c.action == "ping" { return nil }
        guard pro else { throw LoomError.entitlement }
        guard allowed, foreground else {
            throw LoomError.unavailable("The receiver must authorize control in the foreground.")
        }
        if let id = c.patternID {
            guard let p = Catalog.presets.first(where: { $0.id == id }), Entitlements.canPlay(p, pro: pro)
            else { throw LoomError.entitlement }
        }
        if let g = c.gain {
            guard Validation.finite(g, 0...1), Validation.finite(limit, 0...1) else {
                throw LoomError.invalid("Invalid remote intensity.")
            }
            return min(g, limit)
        }
        return nil
    }
}
