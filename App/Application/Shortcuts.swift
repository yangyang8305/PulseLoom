import AppIntents
import Foundation
import PulseLoomCore

struct PresetEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "shortcut.pattern")
    static var defaultQuery = PresetQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}
struct PresetQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [PresetEntity] {
        Catalog.presets.filter { identifiers.contains($0.id) }.map {
            PresetEntity(id: $0.id, name: $0.displayName())
        }
    }
    func suggestedEntities() async throws -> [PresetEntity] {
        Catalog.presets.map { PresetEntity(id: $0.id, name: $0.displayName()) }
    }
}
struct OpenPulseLoomIntent: AppIntent {
    static var title: LocalizedStringResource = "shortcut.open"
    static var description = IntentDescription("shortcut.description")
    static var openAppWhenRun = true
    @Parameter(title: "shortcut.pattern") var pattern: PresetEntity?
    @MainActor func perform() async throws -> some IntentResult {
        if let pattern,
            let group = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String,
            let preferences = UserDefaults(suiteName: group)
        {
            preferences.set(pattern.id, forKey: "shortcutPattern")
            NotificationCenter.default.post(name: .loomShortcutRequested, object: nil)
        }
        return .result()
    }
}
struct PulseLoomShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenPulseLoomIntent(), phrases: ["Open \(.applicationName)", "打开\(.applicationName)"],
            shortTitle: "shortcut.open", systemImageName: "hand.tap")
    }
}
extension Notification.Name {
    static let loomShortcutRequested = Notification.Name("PulseLoom.shortcutRequested")
}
