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
        let group = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String
        let preferences = group.flatMap { $0.isEmpty ? nil : UserDefaults(suiteName: $0) }
        // A plain Open action supersedes stale pending selections; it never starts output.
        guard let pattern else {
            preferences?.removeObject(forKey: "shortcutPattern")
            return .result()
        }
        guard Catalog.presets.contains(where: { $0.id == pattern.id }) else {
            preferences?.removeObject(forKey: "shortcutPattern")
            throw LoomError.invalid(NSLocalizedString("shortcut.unknown", tableName: "Recovery", comment: ""))
        }
        guard let preferences else {
            throw LoomError.unavailable(NSLocalizedString("shortcut.storage", tableName: "Recovery", comment: ""))
        }
        preferences.set(pattern.id, forKey: "shortcutPattern")
        NotificationCenter.default.post(name: .loomShortcutRequested, object: nil)
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
