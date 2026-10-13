import Foundation
import PulseLoomCore

/// In-app language override. "system" follows iOS; otherwise strings, catalog names and the
/// SwiftUI locale come from the chosen .lproj immediately, and AppleLanguages is written so the
/// next launch (and system-provided UI such as share sheets) agree.
enum AppLanguage {
    static let defaultsKey = "pulseloom.language"
    static let choices = ["system", "zh-Hans", "en", "ja"]
    static func nativeName(_ code: String) -> String {
        switch code {
        case "zh-Hans": return "中文"
        case "en": return "English"
        case "ja": return "日本語"
        default: return T("language.system")
        }
    }
    private(set) static var code = UserDefaults.standard.string(forKey: defaultsKey) ?? "system"
    private(set) static var bundle: Bundle = .main
    static var locale: Locale { code == "system" ? .autoupdatingCurrent : Locale(identifier: code == "zh-Hans" ? "zh_CN" : code == "ja" ? "ja_JP" : "en_US") }

    static func apply(_ choice: String, persist: Bool = true) {
        code = choices.contains(choice) ? choice : "system"
        if persist { UserDefaults.standard.set(code, forKey: defaultsKey) }
        if code == "system" {
            bundle = .main
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            LoomLanguage.current = Locale.current.language.languageCode?.identifier ?? "en"
        } else {
            bundle = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
            LoomLanguage.current = code == "zh-Hans" ? "zh" : code
        }
    }
    /// Called once at launch so the stored choice applies before the first view renders.
    /// An explicit -AppleLanguages launch argument (UI tests, Xcode scheme) wins over the stored choice.
    static func restore() {
        let forced = ProcessInfo.processInfo.arguments.contains("-AppleLanguages")
        if forced { code = "system"; bundle = .main; LoomLanguage.current = Locale.current.language.languageCode?.identifier ?? "en" }
        else { apply(code, persist: false) }
    }
}
