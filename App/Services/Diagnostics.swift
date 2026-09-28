import Foundation
import OSLog

@MainActor final class Diagnostics {
    struct Entry: Codable {
        var date: Date
        var code: String
        var category: String
    }
    private(set) var entries: [Entry] = []
    var enabled = false
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PulseLoom", category: "diagnostics")
    func record(code: String, category: String) {
        // Never include free-form user names, audio filenames, invites, credentials or purchase receipts.
        guard code.range(of: "^[A-Z0-9_]{1,40}$", options: .regularExpression) != nil else { return }
        log.notice("Event \(code,privacy:.public)")
        guard enabled else { return }
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        entries = Array(
            (entries.filter { $0.date > cutoff } + [
                Entry(date: Date(), code: code, category: String(category.prefix(32)))
            ]).suffix(500))
    }
    func clear() { entries = [] }
    func data() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = .prettyPrinted
        e.dateEncodingStrategy = .iso8601
        return try e.encode(entries)
    }
}
