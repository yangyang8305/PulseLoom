import Foundation

public enum Catalog {
    public static let presets: [HapticPattern] = load("presets")
    private static func load(_ file: String) -> [HapticPattern] {
        guard let url = Bundle.module.url(forResource: file, withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let items = try? JSONDecoder().decode([HapticPattern].self, from: data)
        else { return [] }
        return items
    }
}
public struct ThemeDefinition: Codable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var chineseName: String
    public var art: String
    public var free: Bool
    public var light: [String]
    public var dark: [String]
}
public enum ThemeCatalog {
    public static let all: [ThemeDefinition] = {
        guard let u = Bundle.module.url(forResource: "themes", withExtension: "json"),
            let d = try? Data(contentsOf: u),
            let a = try? JSONDecoder().decode([ThemeDefinition].self, from: d)
        else { return [] }
        return a
    }()
}

extension Catalog { public static var themes: [ThemeDefinition] { ThemeCatalog.all } }

extension ThemeDefinition {
    public static let fallback = ThemeDefinition(
        id: "blush", name: "Blush", chineseName: "柔绯", art: "flower", free: true,
        light: [
            "#fcf7f3", "#fffcf9", "#f2e4e3", "#e8d4db", "#966879", "#423238", "#806d75", "#dfced3", "#fffaf8",
            "#f7e8e7", "#e7c6d1", "#c7a2b9",
        ],
        dark: [
            "#15151a", "#212129", "#292734", "#45404f", "#d6a9bd", "#f1eef7", "#b9b2c8", "#45404f", "#211822",
            "#27232b", "#43313d", "#765566",
        ])
}
