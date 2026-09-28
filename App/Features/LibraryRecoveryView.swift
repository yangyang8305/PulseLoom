import PulseLoomCore
import SwiftUI
import UniformTypeIdentifiers

private func recoveryText(_ key: String) -> String {
    NSLocalizedString(key, tableName: "Recovery", bundle: .main, comment: "Library recovery")
}

/// Recovery is routed before onboarding and does not require a preference write to enter.
struct LibraryRecoveryView: View {
    @EnvironmentObject var app: AppModel
    @State private var importing = false
    @State private var candidate: LibrarySnapshot?
    @State private var erase = false
    var body: some View {
        NavigationStack {
            PlainScene {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 54, weight: .light)).frame(maxWidth: .infinity)
                Text(recoveryText("title")).font(.title2.bold())
                Text(recoveryText("detail")).font(.body)
                if let error = app.library.loadError { Text(error).font(.caption).foregroundStyle(.secondary) }
                Button(recoveryText("retry")) {
                    app.perform { try app.library.retryRecovery() }
                }.frame(minHeight: 44).accessibilityIdentifier("recoveryRetry")
                Button(recoveryText("previous")) {
                    app.perform { try app.restorePreviousLibrary() }
                }.frame(minHeight: 44).accessibilityIdentifier("recoveryRestorePrevious")
                Button(recoveryText("import")) { importing = true }.frame(minHeight: 44)
                Button(recoveryText("export")) {
                    let url = app.library.root.appendingPathComponent("library.json")
                    app.share = SharedFile(url: url)
                }.frame(minHeight: 44)
                    .disabled(!FileManager.default.fileExists(atPath: app.library.root.appendingPathComponent("library.json").path))
                Button(recoveryText("erase"), role: .destructive) { erase = true }.frame(minHeight: 44)
                Text(recoveryText("boundary")).font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle(recoveryText("title"))
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            app.perform {
                let data = try app.read(result.get(), max: FileCodec.libraryMaxBytes)
                let restored = try FileCodec.decode(LibrarySnapshot.self, data, maxBytes: FileCodec.libraryMaxBytes)
                try Validation.snapshot(restored)
                candidate = restored
            }
        }
        .confirmationDialog(T("privacy.restoreConfirm"),
            isPresented: Binding(get: { candidate != nil }, set: { if !$0 { candidate = nil } })) {
            Button(T("privacy.replace"), role: .destructive) {
                if let candidate { app.perform { try app.replaceLibrary(candidate) } }
                candidate = nil
            }
            Button(T("common.cancel"), role: .cancel) { candidate = nil }
        }
        .confirmationDialog(T("privacy.clearConfirm"), isPresented: $erase) {
            Button(T("common.delete"), role: .destructive) {
                app.perform { try app.clearLocalContent() }
            }
        }
    }
}
