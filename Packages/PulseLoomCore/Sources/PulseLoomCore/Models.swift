import Foundation

public enum PatternMode: String, Codable, CaseIterable, Sendable { case basic, curve, recorded }
public enum EventKind: String, Codable, Sendable { case continuous, transient }
public struct Segment: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var duration: Double
    public var gap: Double
    public var gain: Double
    public var sharp: Double
    public var type: EventKind
    public init(
        id: UUID = UUID(), duration: Double = 250, gap: Double = 250,
        gain: Double = 0.5, sharp: Double = 0.25, type: EventKind = .continuous
    ) {
        self.id = id
        self.duration = duration
        self.gap = gap
        self.gain = gain
        self.sharp = sharp
        self.type = type
    }
}
public struct CurveNode: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var time: Double
    public var value: Double
    public init(id: UUID = UUID(), time: Double, value: Double) {
        self.id = id
        self.time = time
        self.value = value
    }
}
public struct HapticPattern: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var englishName: String
    public var japaneseName: String
    public var category: String
    public var description: String
    public var mode: PatternMode
    public var segments: [Segment]
    public var nodes: [CurveNode]
    /// Milliseconds, unlike Core Haptics which consumes seconds.
    public var cycle: Double
    public var sharpness: Double
    public var loop: Bool
    public var fadeIn: Double
    public var fadeOut: Double
    public var premium: Bool
    public var builtin: Bool
    public var sourcePremium: Bool
    public var updatedAt: Date
    public init(
        id: String = UUID().uuidString, name: String = "", englishName: String = "",
        japaneseName: String = "", category: String = "custom", description: String = "",
        mode: PatternMode = .basic, segments: [Segment] = [Segment(), Segment(), Segment(), Segment()],
        nodes: [CurveNode] = [], cycle: Double = 2000, sharpness: Double = 0.25,
        loop: Bool = true, fadeIn: Double = 0, fadeOut: Double = 0,
        premium: Bool = false, builtin: Bool = false, sourcePremium: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.englishName = englishName
        self.japaneseName = japaneseName
        self.category = category
        self.description = description
        self.mode = mode
        self.segments = segments
        self.nodes = nodes
        self.cycle = cycle
        self.sharpness = sharpness
        self.loop = loop
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.premium = premium
        self.builtin = builtin
        self.sourcePremium = sourcePremium
        self.updatedAt = updatedAt
    }
    public var durationMS: Double {
        mode == .curve ? cycle : segments.reduce(0) { $0 + $1.duration + $1.gap }
    }
    public func displayName(language: String = Locale.current.language.languageCode?.identifier ?? "en")
        -> String
    {
        guard builtin else { return name }
        if language == "zh" { return name }
        if language == "ja", !japaneseName.isEmpty { return japaneseName }
        return englishName.isEmpty ? name : englishName
    }
    public func copyForEditing() -> HapticPattern {
        var p = self
        p.id = UUID().uuidString
        p.builtin = false
        p.sourcePremium = sourcePremium || premium
        p.premium = false
        p.updatedAt = Date()
        return p
    }
}
public enum Appearance: String, Codable, CaseIterable, Sendable { case auto, light, dark }
public struct Preferences: Codable, Equatable, Sendable {
    public var name = ""
    public var theme = "blush"
    public var appearance: Appearance = .auto
    public var gain = 0.55
    public var speed = 1.0
    public var sharpness = 0.25
    public var timer = 180.0
    public var lastPattern = "p02"
    public var keepAwake = true
    public var reduceMotion = false
    public var historyEnabled = false
    public var privacyCover = true
    public var diagnosticsEnabled = false
    public var onboarded = false
    public var icon = "default"
    public var widgetPattern = "p02"
    public var widgetPrivate = true
    public init() {}
}
public struct RoutineItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var patternID: String
    public var seconds: Double
    public var gain: Double
    public init(id: UUID = UUID(), patternID: String, seconds: Double = 60, gain: Double = 0.5) {
        self.id = id
        self.patternID = patternID
        self.seconds = seconds
        self.gain = gain
    }
}
public struct Routine: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var items: [RoutineItem]
    public var crossfade: Double
    public var sound: Bool
    public var updatedAt: Date
    public init(
        id: String = UUID().uuidString, name: String = "", items: [RoutineItem] = [],
        crossfade: Double = 0, sound: Bool = false, updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.items = items
        self.crossfade = crossfade
        self.sound = sound
        self.updatedAt = updatedAt
    }
    public var duration: Double { items.reduce(0) { $0 + $1.seconds } }
}
public struct HistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var kind: String
    public var date: Date
    public var seconds: Double
    public var reason: String
    public init(title: String, kind: String, seconds: Double, reason: String, date: Date = Date()) {
        id = UUID()
        self.title = title
        self.kind = kind
        self.seconds = seconds
        self.reason = reason
        self.date = date
    }
}
public enum MusicMapping: String, Codable, CaseIterable, Sendable { case energy, beats, blend }
public enum MusicFeel: String, Codable, CaseIterable, Sendable { case soft, balanced, vivid }
public struct MusicConfiguration: Codable, Equatable, Sendable {
    public var gain = 0.55
    public var sensitivity = 0.55
    public var sharpness = 0.25
    public var volume = 0.3
    public var mapping: MusicMapping = .energy
    public var offset = 0.0
    public var overlay = "p02"
    public var overlayMix = 0.25
    public var from = 0.0
    public var to = 0.0
    public init() {}
    public mutating func apply(_ feel: MusicFeel) {
        switch feel {
        case .soft:
            mapping = .energy
            sensitivity = 0.35
            sharpness = 0.15
        case .balanced:
            mapping = .energy
            sensitivity = 0.55
            sharpness = 0.35
        case .vivid:
            mapping = .beats
            sensitivity = 0.8
            sharpness = 0.65
        }
    }
}
public struct MusicMix: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var trackName: String
    public var configuration: MusicConfiguration
    public init(
        id: String = UUID().uuidString, name: String, trackName: String, configuration: MusicConfiguration
    ) {
        self.id = id
        self.name = name
        self.trackName = trackName
        self.configuration = configuration
    }
}
public struct FeedbackNote: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var text: String
    public var screen: String
    public var date: Date
    public init(text: String, screen: String) {
        id = UUID()
        self.text = text
        self.screen = screen
        date = Date()
    }
}
public struct LibrarySnapshot: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var custom: [HapticPattern] = []
    public var favorites: [String] = []
    public var routines: [Routine] = []
    public var mixes: [MusicMix] = []
    public var preferences = Preferences()
    public var notes: [FeedbackNote] = []
    public var tombstones: [String: Date] = [:]
    public var updatedAt = Date()
    public init() {}
    /// Do not synchronize history, music filenames, feedback or unrelated device preferences.
    public func cloudPayload() -> LibrarySnapshot {
        var s = self
        s.mixes = []
        s.notes = []
        var p = Preferences()
        p.theme = preferences.theme
        p.appearance = preferences.appearance
        s.preferences = p
        s.updatedAt = Date(timeIntervalSince1970: 0)
        return s
    }
}
public enum LoomError: Error, LocalizedError, Equatable {
    case invalid(String)
    case storage(String)
    case unavailable(String)
    case entitlement
    public var errorDescription: String? {
        switch self {
        case .invalid(let s), .storage(let s), .unavailable(let s): return s
        case .entitlement: return "Pro is required for this content or additional saved patterns."
        }
    }
}
public enum Entitlements {
    public static func canPlay(_ p: HapticPattern, pro: Bool) -> Bool {
        pro || (!p.premium && !p.sourcePremium)
    }
    public static func canSave(isNew: Bool, count: Int, pro: Bool) -> Bool {
        !isNew || count < (pro ? 200 : 3)
    }
}
