import PulseLoomCore
import SwiftUI

struct ManualView: View {
    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject var app: AppModel
    @State private var continuous = false
    @State private var pressed = false
    @State private var timeout: Task<Void, Never>?
    var body: some View {
        PlainScene {
            Notice(text: "manual.help")
            ZStack {
                TactileArt(style: "orb", level: pressed ? app.prefs.gain : 0)
                Text(T(pressed ? "manual.release" : "manual.hold")).font(.title3)
                TouchSurface(began: { _ in start() }, moved: { _ in }, ended: { if !continuous { end() } })
            }.frame(height: 240)
            Toggle(T("manual.continuous"), isOn: $continuous).onChange(of: continuous) { _, _ in end() }
            LoomSlider(title: "home.intensity", value: app.pref(\.gain)) {
                if pressed {
                    app.perform {
                        try app.playback.stream(
                            app.prefs.gain, sharpness: app.prefs.sharpness, source: "manual")
                    }
                }
            }
            LoomButton(title: "common.stop", symbol: "stop", secondary: true) { end() }
            Button(T("manual.shortTest")) {
                start()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { end() }
            }.frame(minHeight: 44)
        }.navigationTitle(T("manual.title")).onDisappear { end() }.onChange(of: scenePhase) { _, phase in
            if phase != .active { end() }
        }.onChange(of: app.privacyHidden) { _, hidden in if hidden { end() } }
    }
    func start() {
        if continuous && pressed {
            end()
            return
        }
        app.perform {
            try app.playback.stream(app.prefs.gain, sharpness: app.prefs.sharpness, source: "manual")
            pressed = true
            timeout?.cancel()
            timeout = Task {
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(continuous ? min(600, app.prefs.timer) : 10) * 1_000_000_000)
                } catch { return }
                end()
            }
        }
    }
    func end() {
        timeout?.cancel()
        pressed = false
        if app.playback.kind == "manual" { app.playback.stopStream() }
    }
}
struct SoundscapeView: View {
    @EnvironmentObject var app: AppModel
    var body: some View {
        PlainScene {
            TactileArt(style: "orb").frame(height: 170)
            Notice(text: "sound.help")
            ForEach(0..<3) { i in
                LoomSlider(
                    title: ["sound.rain", "sound.air", "sound.hum"][i],
                    value: Binding(
                        get: { app.sound.levels[i] },
                        set: {
                            app.sound.levels[i] = $0
                            app.sound.update()
                        }))
            }
            HStack {
                ForEach(0..<3) { i in
                    Button(T(["sound.rain", "sound.air", "sound.hum"][i])) { app.sound.preset(i) }.frame(
                        maxWidth: .infinity, minHeight: 44)
                }
            }
            LoomButton(title: app.sound.active ? "sound.pause" : "sound.start", symbol: "speaker.wave.2") {
                app.perform { if app.sound.active { app.sound.stop() } else { try app.sound.play() } }
            }
            LoomButton(title: "sound.withHaptics", secondary: true) {
                app.perform {
                    guard Entitlements.canPlay(app.current, pro: app.pro) else { throw LoomError.entitlement }
                    try app.sound.play()
                    try app.playback.begin(
                        app.current, duration: app.prefs.timer, gain: app.prefs.gain, kind: "routine")
                }
            }
            LoomButton(title: "common.stop", secondary: true) { app.stopAll() }
        }.navigationTitle(T("sound.title"))
    }
}
struct BreathView: View {
    @EnvironmentObject var app: AppModel
    @State private var timing = BreathTiming()
    var active: Bool { app.playback.kind == "breath" && [.playing, .paused].contains(app.playback.state) }
    var body: some View {
        PlainScene {
            if active {
                let phase = timing.phase(at: app.playback.elapsed)
                ZStack {
                    TactileArt(style: "orb", level: app.playback.level).frame(height: 230)
                    VStack(spacing: 12) {
                        Text(T(phase.0)).font(.largeTitle)
                        Text(timeText(phase.1)).font(.title2.monospacedDigit())
                    }
                }
                Text(timeText(app.playback.remaining)).frame(maxWidth: .infinity).monospacedDigit()
                LoomButton(title: app.playback.isPlaying ? "home.pause" : "home.resume") {
                    app.perform {
                        if app.playback.isPlaying { app.playback.pause() } else { try app.playback.resume() }
                    }
                }
                LoomButton(title: "common.stop", secondary: true) { app.stopAll() }
            } else {
                Picker(
                    T("breath.style"),
                    selection: Binding(
                        get: { timing.inhale == 4 && timing.exhale == 6 ? 0 : 1 },
                        set: { v in
                            timing.inhale = 4
                            timing.exhale = v == 0 ? 6 : 4
                        })
                ) {
                    Text(T("breath.slow")).tag(0)
                    Text(T("breath.even")).tag(1)
                }.pickerStyle(.segmented)
                Stepper(
                    String(format: T("time.minutes"), Int(timing.minutes)), value: $timing.minutes, in: 1...10
                )
                DisclosureGroup(T("breath.custom")) {
                    NumberInput(title: "breath.inhale", value: $timing.inhale, unit: "unit.seconds")
                    NumberInput(title: "breath.hold", value: $timing.hold, unit: "unit.seconds")
                    NumberInput(title: "breath.exhale", value: $timing.exhale, unit: "unit.seconds")
                }
                LoomButton(title: "breath.start", symbol: "wind") {
                    app.perform {
                        let p = try timing.pattern()
                        try app.playback.begin(
                            p, duration: timing.minutes * 60, gain: app.prefs.gain, kind: "breath")
                    }
                }
            }
            Notice(text: "breath.help")
        }.navigationTitle(T("breath.title"))
    }
}
struct RoutinesView: View {
    @EnvironmentObject var app: AppModel
    @State private var route: Routine?
    var body: some View {
        PlainScene {
            LoomButton(title: "routine.new", symbol: "plus") {
                route = Routine(name: T("routine.untitled"), items: [RoutineItem(patternID: "p02")])
            }
            LoomButton(title: "routine.template", secondary: true) {
                route = Routine(
                    name: T("routine.template"),
                    items: [
                        RoutineItem(patternID: "p02"), RoutineItem(patternID: "p04"),
                        RoutineItem(patternID: "p06"),
                    ])
            }
            ForEach(app.library.snapshot.routines) { r in
                HStack {
                    Button {
                        route = r
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(r.name)
                            Text(timeText(r.duration) + " · \(r.items.count)").font(.caption).foregroundStyle(
                                .secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button {
                        app.perform {
                            if r.sound { try app.sound.play() }
                            try app.playback.playRoutine(
                                r, resolver: { app.library.pattern($0) }, pro: app.pro)
                        }
                    } label: {
                        Image(systemName: "power").frame(width: 44, height: 44)
                    }
                }.padding(.vertical, 8)
            }
            if app.playback.kind == "routine", app.playback.isPlaying {
                Text(app.playback.title + " · " + timeText(app.playback.remaining))
                HStack {
                    LoomButton(title: "routine.next", secondary: true) {
                        app.playback.advanceRoutine(to: app.playback.routineIndex + 1)
                    }
                    LoomButton(title: "common.stop", secondary: true) { app.stopAll() }
                }
            }
        }.navigationTitle(T("routine.title")).sheet(item: $route) { r in RoutineEditorView(routine: r) }
    }
}
struct RoutineEditorView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) var dismiss
    @State var routine: Routine
    @State private var delete = false
    var body: some View {
        NavigationStack {
            PlainScene {
                TextField(T("common.name"), text: $routine.name).textFieldStyle(.roundedBorder)
                ForEach(Array(routine.items.enumerated()), id: \.element.id) { i, item in
                    LoomCard {
                        VStack(spacing: 12) {
                            Picker(T("home.presets"), selection: $routine.items[i].patternID) {
                                ForEach(app.library.allPatterns) { p in Text(p.displayName()).tag(p.id) }
                            }
                            Stepper(
                                String(format: T("time.seconds"), Int(routine.items[i].seconds)),
                                value: $routine.items[i].seconds, in: 15...300, step: 15)
                            LoomSlider(title: "home.intensity", value: $routine.items[i].gain)
                            HStack {
                                Button {
                                    if i > 0 { routine.items.swapAt(i, i - 1) }
                                } label: {
                                    Image(systemName: "arrow.up").frame(width: 44, height: 44)
                                }
                                Spacer()
                                Button {
                                    routine.items.removeAll { $0.id == item.id }
                                } label: {
                                    Image(systemName: "trash").frame(width: 44, height: 44)
                                }
                            }
                        }
                    }
                }
                if routine.items.count < 12 {
                    LoomButton(title: "routine.add", symbol: "plus", secondary: true) {
                        routine.items.append(RoutineItem(patternID: "p02"))
                    }
                }
                Text(T("routine.total") + " " + timeText(routine.duration)).font(.caption)
                DisclosureGroup(T("routine.options")) {
                    Stepper(
                        String(format: T("routine.fade"), routine.crossfade), value: $routine.crossfade,
                        in: 0...3, step: 0.5)
                    Toggle(T("routine.sound"), isOn: $routine.sound)
                }
                LoomButton(title: "common.save", symbol: "checkmark") {
                    app.perform {
                        routine.updatedAt = Date()
                        try Validation.routine(routine, patterns: app.library.allPatterns)
                        guard app.pro else { throw LoomError.entitlement }
                        try app.library.commit { s in
                            if let i = s.routines.firstIndex(where: { $0.id == routine.id }) {
                                s.routines[i] = routine
                            } else {
                                s.routines.append(routine)
                            }
                        }
                        dismiss()
                    }
                }
                LoomButton(title: "pattern.preview", secondary: true) {
                    app.perform {
                        if routine.sound { try app.sound.play() }
                        try app.playback.playRoutine(
                            routine, resolver: { app.library.pattern($0) }, pro: app.pro)
                    }
                }
                if app.library.snapshot.routines.contains(where: { $0.id == routine.id }) {
                    LoomButton(title: "common.delete", secondary: true, destructive: true) { delete = true }
                }
            }.navigationTitle(T("routine.edit")).toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(T("common.close")) { dismiss() } }
            }
        }
        .confirmationDialog(T("common.delete"), isPresented: $delete) {
            Button(T("common.delete"), role: .destructive) {
                app.perform {
                    try app.library.commit {
                        $0.routines.removeAll { $0.id == routine.id }
                        $0.tombstones[routine.id] = Date()
                    }
                    dismiss()
                }
            }
        }
    }
}
struct CloudView: View {
    @EnvironmentObject var app: AppModel
    var body: some View {
        PlainScene {
            Notice(text: "sync.help")
            LabeledContent(T("sync.status"), value: T("sync.state." + stateName))
            if let date = app.cloud.lastSync { Text(date, style: .date).font(.caption) }
            if app.cloud.state == .off {
                LoomButton(title: "sync.enable", symbol: "icloud") {
                    app.asyncPerform {
                        guard app.pro else { throw LoomError.entitlement }
                        try await app.cloud.enable()
                    }
                }
            } else {
                LoomButton(title: "sync.now", symbol: "arrow.triangle.2.circlepath") {
                    app.asyncPerform {
                        guard app.pro else { throw LoomError.entitlement }
                        try await app.syncLibrary()
                    }
                }.disabled(app.cloud.state == .syncing)
                if app.cloud.state == .conflict {
                    Notice(text: "sync.conflictHelp")
                    ForEach(["both", "local", "remote"], id: \.self) { choice in
                        LoomButton(title: "sync.choice." + choice, secondary: true) {
                            app.asyncPerform {
                                try await app.syncLibrary(choice: choice)
                            }
                        }.disabled(app.cloud.state == .syncing)
                    }
                }
                LoomButton(title: "sync.disable", secondary: true) { app.cloud.disable() }
                    .disabled(app.cloud.state == .syncing)
                DeleteCloudButton().disabled(app.cloud.state == .syncing)
            }
            if let e = app.cloud.error { Notice(text: e) }
        }.navigationTitle(T("sync.title"))
    }
    var stateName: String {
        switch app.cloud.state {
        case .off: return "off"
        case .ready: return "ready"
        case .syncing: return "syncing"
        case .conflict: return "conflict"
        case .failed: return "failed"
        }
    }
}
private struct DeleteCloudButton: View {
    @EnvironmentObject var app: AppModel
    @State private var confirm = false
    var body: some View {
        LoomButton(title: "sync.delete", secondary: true, destructive: true) { confirm = true }
            .confirmationDialog(T("sync.delete"), isPresented: $confirm) {
                Button(T("common.delete"), role: .destructive) {
                    app.asyncPerform { try await app.cloud.deleteCloud() }
                }
            }
    }
}
struct RemoteView: View {
    @EnvironmentObject var app: AppModel
    @State private var invite = ""
    @State private var selected = "p02"
    @State private var level = 0.4
    var body: some View {
        PlainScene {
            Notice(text: "remote.help")
            if app.remote.server == nil { Notice(text: "remote.notConfigured") }
            if app.remote.state != .connected {
                LoomButton(title: "remote.invite", symbol: "link") {
                    app.asyncPerform {
                        guard app.pro else { throw LoomError.entitlement }
                        try await app.remote.create()
                    }
                }
                TextField(T("remote.pasteInvite"), text: $invite, axis: .vertical).textFieldStyle(
                    .roundedBorder
                ).textInputAutocapitalization(.never).autocorrectionDisabled()
                LoomButton(title: "remote.join", secondary: true) {
                    app.perform {
                        guard app.pro else { throw LoomError.entitlement }
                        try app.remote.join(invite)
                    }
                }
                if app.remote.state == .connecting { ProgressView(T("remote.connecting")) }
            } else {
                if let link = app.remote.shareURL, app.remote.role == .sender {
                    ShareLink(item: link) {
                        Label(T("remote.share"), systemImage: "square.and.arrow.up").frame(minHeight: 44)
                    }
                }
                LabeledContent(
                    T("remote.peer"), value: T(app.remote.peerPresent ? "remote.online" : "remote.waiting"))
                if app.remote.role == .receiver {
                    Toggle(
                        T("remote.allow"),
                        isOn: Binding(get: { app.remote.consent.allowed }, set: { app.remote.authorize($0) }))
                    LoomSlider(title: "remote.limit", value: $app.remote.limit)
                } else {
                    Picker(T("home.presets"), selection: $selected) {
                        ForEach(Catalog.presets) { p in Text(p.displayName()).tag(p.id) }
                    }
                    LoomSlider(title: "home.intensity", value: $level) {
                        app.asyncPerform { try await app.remote.send(action: "gain", gain: level) }
                    }
                    LoomButton(title: "remote.start", symbol: "power") {
                        app.asyncPerform {
                            try await app.remote.send(action: "start", patternID: selected, gain: level)
                        }
                    }.disabled(!app.remote.peerPresent)
                }
                LoomButton(title: "remote.emergency", symbol: "stop", secondary: true, destructive: true) {
                    app.remote.emergency()
                    app.stopAll()
                }
                LoomButton(title: "remote.disconnect", secondary: true) { app.remote.disconnect() }
            }
            if let e = app.remote.error {
                Notice(text: e)
                Button(T("remote.reconnect")) { app.perform { try app.remote.reconnect() } }.frame(
                    minHeight: 44)
            }
            Notice(text: "remote.safety")
        }.navigationTitle(T("remote.title")).onAppear { invite = app.inviteInput }
    }
}
struct WatchSettingsView: View {
    @EnvironmentObject var app: AppModel
    var body: some View {
        PlainScene {
            Image(systemName: "applewatch").font(.system(size: 75, weight: .ultraLight)).frame(
                maxWidth: .infinity
            ).padding()
            LabeledContent(T("watch.install"), value: T(app.watch.installed ? "common.yes" : "common.no"))
            LabeledContent(T("watch.reachable"), value: T(app.watch.reachable ? "common.yes" : "common.no"))
            Toggle(T("watch.allow"), isOn: $app.watch.allowed).onChange(of: app.watch.allowed) { _, _ in
                app.updatePreferences()
            }
            Notice(text: "watch.help")
            if let e = app.watch.error { Notice(text: e) }
        }.navigationTitle(T("watch.title")).onAppear { app.updatePreferences() }
    }
}
struct WidgetSettingsView: View {
    @EnvironmentObject var app: AppModel
    var body: some View {
        PlainScene {
            LoomCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pulse Loom").font(.system(.title3, design: .serif))
                    Text(
                        app.prefs.widgetPrivate
                            ? T("widget.privateTitle")
                            : app.library.pattern(app.prefs.widgetPattern)?.displayName() ?? "")
                    Label(T("widget.opensApp"), systemImage: "hand.tap").font(.caption)
                }
            }
            Picker(T("widget.pattern"), selection: app.pref(\.widgetPattern)) {
                ForEach(Catalog.presets) { p in Text(p.displayName()).tag(p.id) }
            }
            Toggle(T("widget.private"), isOn: app.pref(\.widgetPrivate))
            Notice(text: "widget.addHelp")
        }.navigationTitle(T("widget.title"))
    }
}
