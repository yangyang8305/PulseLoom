import Foundation

/// Debug-only trace written to Documents/diag.log so it can be pulled off a device with devicectl.
enum DiagLog {
    private static let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("diag.log")
    private static let formatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()
    static func write(_ message: String) {
        #if DEBUG
        let line = formatter.string(from: Date()) + " " + message + "\n"
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: url)
        }
        #endif
    }
}
