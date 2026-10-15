import PulseLoomCore
import SwiftUI
import UniformTypeIdentifiers

/// One screen: who you are, your library, three rows (theme, Pro, settings) and a grid of extras.
struct MyView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.loom) var c
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    var body: some View {
        PlainScene(spacing: 14) {
            HStack(spacing: 14) {
                LoomArt(style: app.theme.art).frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.prefs.name.isEmpty ? T("my.space") : app.prefs.name).font(.system(.title2, design: .serif))
                    Text(T("my.subtitle")).font(.footnote).foregroundStyle(c.muted)
                }
            }
            LoomCard(padding: 12) {
                HStack {
                    NavigationLink { SavedPatternsView() } label: { counter(app.library.snapshot.custom.count, "my.patterns") }
                    Divider().frame(height: 36)
                    NavigationLink { FavoritesView() } label: { counter(app.library.snapshot.favorites.count, "my.favorites") }
                    Divider().frame(height: 36)
                    NavigationLink { HistoryView() } label: { counter(app.library.history.count, "my.history") }
                }
            }
            VStack(spacing: 0) {
                Button { app.sheet = .artwork } label: { LoomRow(title: "artwork.title", symbol: "sparkles", subtitle: T("artwork." + app.artwork)) }
                Button { app.sheet = .themes } label: { LoomRow(title: "theme.title", symbol: "paintpalette", subtitle: app.theme.displayName()) }
                Divider()
                Button { app.sheet = .premium } label: {
                    LoomRow(title: "purchase.title", symbol: "sparkle", subtitle: app.pro ? T("purchase.active") : T("purchase.free"))
                }
                Divider()
                NavigationLink { SettingsView() } label: { LoomRow(title: "settings.title", symbol: "gearshape") }
            }.buttonStyle(.plain)
            LoomSection(title: "my.more")
            LazyVGrid(columns: columns, spacing: 10) {
                tile("routine.title", "list.bullet") { RoutinesView() }
                tile("breath.title", "wind") { BreathView() }
                tile("manual.title", "hand.tap") { ManualView() }
                tile("sync.title", "icloud") { CloudView() }
                tile("remote.title", "link") { RemoteView() }
                tile("watch.title", "applewatch") { WatchSettingsView() }
                tile("widget.title", "square.grid.2x2") { WidgetSettingsView() }
            }
        }.toolbar(.hidden, for: .navigationBar)
    }
    private func counter(_ n: Int, _ title: String) -> some View {
        VStack(spacing: 4) {
            Text("\(n)").font(.system(.title2, design: .serif))
            Text(T(title)).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity, minHeight: 50).foregroundStyle(c.ink)
    }
    private func tile<Destination: View>(_ title: String, _ symbol: String, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.body.weight(.medium)).foregroundStyle(c.accent)
                    .frame(width: 38, height: 38).background(c.tint, in: Circle())
                Text(T(title)).font(.caption2).foregroundStyle(c.ink).lineLimit(2).multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }.frame(maxWidth: .infinity, minHeight: 72)
        }.buttonStyle(.plain)
    }
}
typealias MyRow = LoomRow

struct SavedPatternsView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var editor: EditorModel
    @State private var importing = false
    @State private var rename: HapticPattern?
    @State private var delete: HapticPattern?
    @State private var name = ""
    var body: some View {
        PlainScene {
            Text(String(format: T("my.saveQuota"), app.library.snapshot.custom.count, app.pro ? 200 : 3))
                .font(.footnote)
            if app.library.snapshot.custom.isEmpty {
                EmptyState(title: "empty.patterns", detail: "empty.patternsHelp")
            }
            ForEach(app.library.snapshot.custom) { p in
                HStack {
                    NavigationLink {
                        PatternDetailView(pattern: p)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(p.name)
                            Text(String(format: T("pattern.cycleFormat"), p.durationMS / 1000)).font(.caption)
                                .foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Menu {
                        Button(T("common.edit")) {
                            editor.edit(p)
                            app.tab = .create
                        }
                        Button(T("common.duplicate")) {
                            app.perform {
                                var copy = p.copyForEditing()
                                copy.name = String((p.name + " " + T("common.copy")).prefix(30))
                                try app.library.save(copy, pro: app.pro)
                            }
                        }
                        Button(T("common.rename")) {
                            name = p.name
                            rename = p
                        }
                        Button(T("common.export")) { app.export(p, name: "PulseLoom-pattern") }
                        Button(T("common.delete"), role: .destructive) { delete = p }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44)
                    }
                }.padding(.vertical, 7)
            }
            Text(ContentPolicy.importNotice).font(.footnote).foregroundStyle(.secondary)
            LoomButton(title: "common.import", symbol: "square.and.arrow.down", secondary: true) {
                importing = true
            }
            LoomButton(title: "my.exportPatterns", symbol: "square.and.arrow.up", secondary: true) {
                app.export(app.library.snapshot.custom, name: "PulseLoom-patterns")
            }
        }.navigationTitle(T("my.patterns"))
            .fileImporter(
                isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false
            ) { r in
                app.perform {
                    guard let u = try r.get().first else { return }
                    let d = try app.read(u)
                    let items = try PatternImport.decodeMany(d)
                    guard app.library.snapshot.custom.count + items.count <= (app.pro ? 200 : 3) else {
                        throw LoomError.entitlement
                    }
                    try app.library.commit { $0.custom.append(contentsOf: items) }
                }
            }
            .alert(
                T("common.rename"),
                isPresented: Binding(get: { rename != nil }, set: { if !$0 { rename = nil } })
            ) {
                TextField(T("common.name"), text: $name)
                Button(T("common.save")) {
                    if var p = rename {
                        p.name = String(name.prefix(30))
                        p.updatedAt = Date()
                        app.perform { try app.library.save(p, pro: app.pro) }
                    }
                    rename = nil
                }
                Button(T("common.cancel"), role: .cancel) { rename = nil }
            }
            .confirmationDialog(
                T("my.deleteConfirm"),
                isPresented: Binding(get: { delete != nil }, set: { if !$0 { delete = nil } })
            ) {
                Button(T("common.delete"), role: .destructive) {
                    if let p = delete {
                        if app.playback.activePattern?.id == p.id { app.stopAll() }
                        app.perform { try app.library.delete(p.id) }
                    }
                    delete = nil
                }
            }
    }
}
struct FavoritesView: View {
    @EnvironmentObject var app: AppModel
    var body: some View {
        List {
            ForEach(app.library.snapshot.favorites, id: \.self) { id in
                if let p = app.library.pattern(id) {
                    NavigationLink {
                        PatternDetailView(pattern: p)
                    } label: {
                        Text(p.displayName())
                    }
                }
            }.onDelete { indices in
                let ids = indices.map { app.library.snapshot.favorites[$0] }
                app.perform { try app.library.commit { $0.favorites.removeAll { ids.contains($0) } } }
            }.onMove { from, to in
                app.perform { try app.library.commit { $0.favorites.move(fromOffsets: from, toOffset: to) } }
            }
        }.scrollContentBackground(.hidden).loomBackground().navigationTitle(T("my.favorites")).toolbar {
            EditButton()
        }
    }
}
struct HistoryView: View {
    @EnvironmentObject var app: AppModel
    @State private var clear = false
    var body: some View {
        PlainScene {
            Toggle(T("history.enabled"), isOn: app.pref(\.historyEnabled))
            Notice(text: "history.help")
            ForEach(app.library.history) { h in
                VStack(alignment: .leading, spacing: 5) {
                    Text(h.title)
                    Text(h.date, style: .date).font(.caption)
                    Text(timeText(h.seconds) + " · " + h.reason).font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }
            LoomButton(title: "history.clear", secondary: true, destructive: true) { clear = true }
        }.navigationTitle(T("my.history")).confirmationDialog(T("history.clear"), isPresented: $clear) {
            Button(T("common.delete"), role: .destructive) { app.perform { try app.library.clearHistory() } }
        }
    }
}
struct ThemeView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.colorScheme) var system
    @Environment(\.dismiss) var dismiss
    @State private var preview: ThemeDefinition?
    var body: some View {
        NavigationStack {
            PlainScene(spacing: 14) {
                Picker(T("theme.appearance"), selection: app.pref(\.appearance)) {
                    ForEach(Appearance.allCases, id: \.self) { a in Text(T("theme." + a.rawValue)).tag(a) }
                }.pickerStyle(.segmented)
                Text(T("theme.palette")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(Catalog.themes) { t in
                        let dark = app.prefs.appearance == .dark || app.prefs.appearance == .auto && system == .dark
                        let colors = LoomColors(theme: t, dark: dark)
                        Button {
                            preview = t
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ThemeSwatch(colors: colors).frame(height: 96)
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t.displayName()).font(.system(.headline, design: .serif))
                                        Text(t.free ? T("common.free") : "Pro").font(.caption)
                                    }
                                    Spacer()
                                    if app.prefs.theme == t.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(colors.accent) }
                                }
                            }.padding(12)
                            .background(colors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(
                                app.prefs.theme == t.id ? colors.accent : colors.line, lineWidth: app.prefs.theme == t.id ? 1.5 : 0.8))
                            .foregroundStyle(colors.ink)
                        }.buttonStyle(.plain)
                    }
                }
            }.navigationTitle(T("theme.title")).toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(T("common.done")) { dismiss() } }
            }
        }
        .sheet(item: $preview) { t in
            let colors = LoomColors(
                theme: t,
                dark: app.prefs.appearance == .dark || app.prefs.appearance == .auto && system == .dark)
            NavigationStack {
                PlainScene {
                    Text(t.displayName()).font(.system(.title, design: .serif))
                    ThemeSwatch(colors: colors).frame(height: 120)
                    HeroArt().frame(height: 220).environment(\.loom, colors)
                    Text(T("theme.previewHelp")).font(.footnote)
                    LoomButton(title: "theme.apply", symbol: "checkmark") {
                        if t.free || app.pro {
                            app.perform { try app.library.preferences { $0.theme = t.id } }
                            preview = nil
                        } else {
                            preview = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { app.sheet = .premium }
                        }
                    }
                    LoomButton(title: "common.cancel", secondary: true) { preview = nil }
                }.navigationTitle(T("theme.preview"))
            }.environment(\.loom, colors).tint(colors.accent)
        }
    }
}
/// Quick settings first; data, help and purchases below. Each row is one plain decision.
struct SettingsView: View {
    @EnvironmentObject var app: AppModel
    var body: some View {
        Form {
            Section(T("settings.quick")) {
                NavigationLink {
                    HapticOutputsView()
                } label: {
                    Label(T("output.title"), systemImage: "gamecontroller")
                }
                Toggle(T("settings.awake"), isOn: app.pref(\.keepAwake))
                Toggle(T("settings.privacyCover"), isOn: app.pref(\.privacyCover))
                Toggle(T("settings.motion"), isOn: app.pref(\.reduceMotion))
                Toggle(T("history.enabled"), isOn: app.pref(\.historyEnabled))
            }
            Section(T("settings.personal")) {
                Picker(T("settings.language"), selection: $app.language) {
                    ForEach(AppLanguage.choices, id: \.self) { Text(AppLanguage.nativeName($0)).tag($0) }
                }.accessibilityIdentifier("settingsLanguage")
                TextField(T("settings.name"), text: app.pref(\.name))
                NavigationLink { ThemeView() } label: { Text(T("theme.title")) }
            }
            Section(T("settings.data")) {
                NavigationLink { PrivacyView() } label: { Text(T("privacy.title")) }
                NavigationLink { CloudView() } label: { Text(T("sync.title")) }
                Toggle(T("diagnostics.enabled"), isOn: app.pref(\.diagnosticsEnabled))
                Button(T("diagnostics.export")) { app.exportDiagnostics() }
            }
            Section(T("settings.help")) {
                NavigationLink { FirstTouchView(app: app) } label: { Text(T("touch.title")) }
                NavigationLink { TroubleshootingView() } label: { Text(T("help.troubleshoot")) }
                NavigationLink { HelpView() } label: { Text(T("help.title")) }
                NavigationLink { IconsView() } label: { Text(T("icons.title")) }
                NavigationLink { FeedbackView() } label: { Text(T("feedback.title")) }
                Button(T("onboard.again")) {
                    app.perform { try app.library.preferences { $0.onboarded = false } }
                }
            }
            Section(T("purchase.title")) {
                Button(T("purchase.view")) { app.sheet = .premium }
                Button(T("purchase.restore")) { Task { await app.purchase.restore() } }
                Button(T("purchase.refund")) { Task { await app.purchase.refund() } }
            }
            Section {
                Text(
                    "PulseLoom \(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? ""))"
                ).font(.caption)
            }
        }.scrollContentBackground(.hidden).loomBackground().navigationTitle(T("settings.title"))
    }
}
struct PrivacyView: View {
    @EnvironmentObject var app: AppModel
    @State private var importing = false
    @State private var proposed: LibrarySnapshot?
    @State private var clear = false
    var body: some View {
        PlainScene {
            Text(T("privacy.title")).font(.title)
            ForEach(
                [
                    "privacy.local", "privacy.audio", "privacy.cloud", "privacy.remote", "privacy.apple",
                    "privacy.retention",
                ], id: \.self
            ) { key in Notice(text: key) }
            LoomButton(title: "privacy.export", symbol: "square.and.arrow.up", secondary: true) {
                app.export(app.library.snapshot, name: "PulseLoom-backup")
            }
            Text(ContentPolicy.backupNotice).font(.footnote).foregroundStyle(.secondary)
            LoomButton(title: "privacy.restore", symbol: "square.and.arrow.down", secondary: true) {
                importing = true
            }
            LoomButton(title: "privacy.clear", secondary: true, destructive: true) { clear = true }
            if let e = app.library.loadError {
                Notice(text: e)
                LoomButton(title: "privacy.previous", secondary: true) {
                    app.perform { try app.restorePreviousLibrary() }
                }
            }
        }.navigationTitle(T("privacy.title")).fileImporter(
            isPresented: $importing, allowedContentTypes: [.json]
        ) { r in
            app.perform {
                let u = try r.get()
                let data = try app.read(u, max: FileCodec.libraryMaxBytes)
                let candidate = try FileCodec.decode(LibrarySnapshot.self, data, maxBytes: FileCodec.libraryMaxBytes)
                try Validation.snapshot(candidate)
                proposed = candidate
            }
        }
        .confirmationDialog(
            T("privacy.restoreConfirm"),
            isPresented: Binding(get: { proposed != nil }, set: { if !$0 { proposed = nil } })
        ) {
            Button(T("privacy.replace"), role: .destructive) {
                if let s = proposed {
                    app.perform { try app.replaceLibrary(s) }
                }
                proposed = nil
            }
            Button(T("common.cancel"), role: .cancel) { proposed = nil }
        } message: {
            Text(String(format: T("privacy.importCount"), proposed?.custom.count ?? 0))
        }
        .confirmationDialog(T("privacy.clearConfirm"), isPresented: $clear) {
            Button(T("common.delete"), role: .destructive) {
                app.perform { try app.clearLocalContent() }
            }
        }
    }
}

/// Selection is scoped to the current controller connection; never persist a transient UUID.
struct HapticOutputsView: View {
    @EnvironmentObject var app: AppModel
    private var manager: ControllerHapticsManager { app.playback.outputs.controllers }
    var body: some View {
        Form {
            Section {
                Picker(T("output.route"), selection: Binding(
                    get: { manager.choice },
                    set: { manager.select($0) }
                )) {
                    Text(T("output.auto")).tag(HapticOutputChoice.automatic)
                    Text(T("output.phone")).tag(HapticOutputChoice.phone)
                    ForEach(manager.devices) { device in
                        Text(device.name).tag(HapticOutputChoice.controller(device.id))
                    }
                    if case .controller(let id) = manager.choice,
                       !manager.devices.contains(where: { $0.id == id }) {
                        Text(T("output.disconnected")).tag(manager.choice)
                    }
                }.pickerStyle(.inline)
            } footer: {
                Text(T("output.autoHelp"))
            }
            Section(T("output.connected")) {
                if manager.devices.isEmpty {
                    Text(T("output.none")).foregroundStyle(.secondary)
                }
                ForEach(manager.devices) { device in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(device.name).font(.headline)
                        Text(device.family).font(.caption).foregroundStyle(.secondary)
                        Text(T(device.supportsHaptics ? "output.capable" : "output.notCapable"))
                            .font(.footnote)
                        if !device.localities.isEmpty {
                            Text(device.localities.joined(separator: ", "))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }.accessibilityIdentifier("outputDevice." + device.id.uuidString)
                }
                Button(T("output.scan")) { manager.discover() }
                    .accessibilityIdentifier("outputScan")
            }
            Section {
                Button(T("output.test")) {
                    app.perform {
                        // Brief low-gain, non-looping hardware test; no fabricated success indicator.
                        let sample = HapticPattern(
                            name: "Controller test",
                            segments: [Segment(duration: 250, gap: 0, gain: 0.35, sharp: 0.25)],
                            loop: false)
                        try app.playback.begin(sample, duration: 0.25, gain: 0.35, kind: "output_test")
                    }
                }.accessibilityIdentifier("outputTest")
                Button(T("common.stop"), role: .destructive) { app.stopAll() }
            } footer: {
                Text(T("output.testHelp"))
            }
        }.scrollContentBackground(.hidden).loomBackground().navigationTitle(T("output.title"))
            .onAppear { manager.refresh() }
            .onDisappear { manager.suspendDiscovery() }
    }
}
