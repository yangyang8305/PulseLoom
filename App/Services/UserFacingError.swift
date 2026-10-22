import Foundation
import PulseLoomCore

/// Translate at presentation boundaries. Raw SDK descriptions must not appear in user alerts.
///
/// Mapping is by type, not by matching English copy:
/// - `LoomError.failure(reason)` → the reason's localization key.
/// - `LoomError.unavailable(text)` → already user-facing text, shown verbatim (re-localized if it
///   was produced under a different app language).
/// - `LoomError.diagnostic` / `.invalid` / `.storage` → generic copy; the detail is for logs only.
/// - Foundation domains (URL, Cocoa) → network / file copy.
enum UserFacingError {
    static func message(_ error: Error, fallback: String = "error.operation") -> String {
        if let loom = error as? LoomError {
            switch loom {
            case .failure(let reason): return T(reason.localizationKey)
            case .unavailable(let text): return relocalized(text) ?? text
            case .entitlement: return T("error.proRequired")
            case .storage: return T("error.storage")
            case .invalid(let detail): return relocalized(detail) ?? T("error.invalidInput")
            case .diagnostic: return T(fallback)
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { return T("error.network") }
        if ns.domain == NSCocoaErrorDomain {
            if ns.code == NSUserCancelledError { return T("error.cancelled") }
            if ns.code == NSFileWriteOutOfSpaceError { return T("error.diskFull") }
            return T("error.file")
        }
        return T(fallback)
    }

    static func isOutputMessage(_ message: String) -> Bool {
        ["error.outputUnavailable", "error.controllerDisconnected", "error.controllerUnsupported",
         "error.outputStart", "error.outputStopping", "error.unsupported", "error.hapticsUnavailable"]
            .contains { T($0) == message }
    }

    // MARK: - Cross-language re-localization

    /// Text that was localized by `T()` under one app language and is now shown under another is
    /// mapped back to its key through a table built once from the bundled `.strings` files.
    private static func relocalized(_ text: String) -> String? {
        guard let entry = localizedTextIndex[text] else { return nil }
        return AppLanguage.bundle.localizedString(forKey: entry.key, value: nil, table: entry.table)
    }

    private struct Entry { let key: String; let table: String }

    private static let localizedTextIndex: [String: Entry] = {
        var index: [String: Entry] = [:]
        for table in ["Localizable", "Recovery"] {
            for language in ["en", "zh-Hans", "ja"] {
                guard let path = Bundle.main.path(forResource: table, ofType: "strings",
                                                  inDirectory: nil, forLocalization: language),
                      let strings = NSDictionary(contentsOfFile: path) as? [String: String] else { continue }
                for (key, value) in strings where index[value] == nil {
                    index[value] = Entry(key: key, table: table)
                }
            }
        }
        return index
    }()
}
