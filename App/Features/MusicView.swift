import MusicKit
import PulseLoomCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct MusicView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.loom) var c
    @State private var importing = false
    @State private var showSources = false
    @State private var saveMix = false
    @State private var mixName = ""
    var body: some View {
        PlainScene {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text(T("music.title")).font(.title.bold())
                    Text(T("music.subtitle")).font(.footnote).foregroundStyle(c.muted)
                }
                Spacer()
                Button {
                    app.sheet = .mixes
                } label: {
                    Image(systemName: "heart").frame(width: 44, height: 44)
                }
            }
            if app.music.status == .loading {
                TactileArt(style: "orb").frame(height: 170)
                ProgressView(T("music.analyzing")).frame(maxWidth: .infinity)
                LoomButton(title: "common.cancel", secondary: true) { app.music.cancelLoad() }
            } else if app.music.analysis != nil {
                TactileArt(style: "orb", level: app.music.requestedLevel).frame(height: 130)
                HStack {
                    Image(systemName: "music.note")
                    Text(app.music.name).lineLimit(2)
                    Spacer()
                    Button(T("music.change")) { importing = true }.frame(minHeight: 44)
                }
                LoomSlider(
                    title: "home.intensity",
                    value: Binding(get: { app.music.config.gain }, set: { app.music.config.gain = $0 }))
                Picker(
                    T("music.feel"), selection: Binding(get: { app.music.feel }, set: { app.music.apply($0) })
                ) {
                    ForEach(MusicFeel.allCases, id: \.self) { f in Text(T("music.feel." + f.rawValue)).tag(f)
                    }
                }.pickerStyle(.segmented)
                HStack {
                    LoomButton(title: app.music.isPlaying ? "music.pause" : "music.start", symbol: "power") {
                        app.perform { try app.music.play() }
                    }
                    LoomButton(title: "common.stop", symbol: "stop", secondary: true) { app.stopAll() }.frame(
                        width: 85)
                }
                Text(timeText(app.music.position) + " / " + timeText(app.music.duration)).font(.caption)
                    .monospacedDigit().foregroundStyle(c.muted).frame(maxWidth: .infinity)
                Slider(
                    value: Binding(get: { app.music.position }, set: { app.music.seek($0) }),
                    in: 0...max(0.1, app.music.duration)
                ).accessibilityLabel(T("music.progress"))
                DisclosureGroup(T("music.more")) {
                    VStack(spacing: 16) {
                        LoomSlider(
                            title: "music.volume",
                            value: Binding(
                                get: { app.music.config.volume }, set: { app.music.config.volume = $0 }))
                        LoomSlider(
                            title: "music.sensitivity",
                            value: Binding(
                                get: { app.music.config.sensitivity },
                                set: { app.music.config.sensitivity = $0 }))
                        LoomSlider(
                            title: "home.texture",
                            value: Binding(
                                get: { app.music.config.sharpness }, set: { app.music.config.sharpness = $0 })
                        )
                        Picker(
                            T("music.mapping"),
                            selection: Binding(
                                get: { app.music.config.mapping }, set: { app.music.config.mapping = $0 })
                        ) {
                            ForEach(MusicMapping.allCases, id: \.self) { m in
                                Text(T("music.mapping." + m.rawValue)).tag(m)
                            }
                        }.pickerStyle(.menu)
                        if app.music.config.mapping == .blend {
                            Picker(
                                T("music.overlay"),
                                selection: Binding(
                                    get: { app.music.config.overlay }, set: { app.music.config.overlay = $0 })
                            ) { ForEach(Catalog.presets) { p in Text(p.displayName()).tag(p.id) } }
                            LoomSlider(
                                title: "music.mix",
                                value: Binding(
                                    get: { app.music.config.overlayMix },
                                    set: { app.music.config.overlayMix = $0 }))
                        }
                        LoomSlider(
                            title: "music.offset",
                            value: Binding(
                                get: { app.music.config.offset }, set: { app.music.config.offset = $0 }),
                            range: -0.5...0.5, unit: T("unit.seconds"))
                        HStack {
                            Text(T("music.from"))
                            TextField(
                                "",
                                value: Binding(
                                    get: { app.music.config.from }, set: { app.music.config.from = $0 }),
                                format: .number
                            ).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                        }
                        HStack {
                            Text(T("music.to"))
                            TextField(
                                "",
                                value: Binding(
                                    get: { app.music.config.to }, set: { app.music.config.to = $0 }),
                                format: .number
                            ).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                        }
                        LoomButton(title: "music.applyRange", secondary: true) {
                            app.perform {
                                try Validation.music(app.music.config, duration: app.music.duration)
                                app.music.seek(app.music.config.from)
                            }
                        }
                        LoomButton(title: "music.saveMix", symbol: "heart", secondary: true) {
                            mixName = app.music.name
                            saveMix = true
                        }
                        Text(T("music.analysisHelp")).font(.caption).foregroundStyle(c.muted)
                    }.padding(.top, 13)
                }
            } else {
                TactileArt(style: "orb").frame(height: 200)
                Text(T("music.bringSong")).font(.system(.title2, design: .serif)).frame(maxWidth: .infinity)
                LoomButton(title: "music.select", symbol: "plus") { importing = true }
                    .accessibilityIdentifier("selectMusic")
                LoomButton(title: "music.demo", symbol: "music.note", secondary: true) { app.music.demo() }
                    .accessibilityIdentifier("demoMusic")
                Text(T("music.localHelp")).font(.footnote).foregroundStyle(c.muted)
            }
            if let error = app.music.error {
                Notice(text: error)
                Button(T("common.dismiss")) { app.music.error = nil }.frame(minHeight: 44)
            }
            NavigationLink {
                SystemMusicView()
            } label: {
                Label(T("music.appleMusic"), systemImage: "music.note.list").frame(minHeight: 44)
            }
            NavigationLink {
                SoundscapeView()
            } label: {
                Label(T("sound.title"), systemImage: "wind").frame(minHeight: 44)
            }
        }.toolbar(.hidden, for: .navigationBar).fileImporter(
            isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: false
        ) { result in
            app.perform {
                guard let u = try result.get().first else { return }
                app.music.load(url: u)
            }
        }
        .alert(T("music.saveMix"), isPresented: $saveMix) {
            TextField(T("common.name"), text: $mixName)
            Button(T("common.save")) {
                app.perform {
                    guard !mixName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        mixName.count <= 50
                    else { throw LoomError.invalid(T("error.name")) }
                    guard app.library.snapshot.mixes.count < 200 else {
                        throw LoomError.invalid(T("error.capacity"))
                    }
                    let mix = MusicMix(
                        name: mixName, trackName: app.music.name, configuration: app.music.config)
                    try app.library.commit { $0.mixes.append(mix) }
                }
            }
            Button(T("common.cancel"), role: .cancel) {}
        }
    }
}
struct MusicMixesView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            PlainScene {
                Notice(text: "music.mixHelp")
                if app.library.snapshot.mixes.isEmpty {
                    EmptyState(title: "empty.mixes", detail: "music.mixHelp", symbol: "music.note")
                }
                ForEach(app.library.snapshot.mixes) { mix in
                    HStack {
                        Button {
                            app.perform {
                                if app.music.analysis != nil {
                                    try Validation.music(mix.configuration, duration: app.music.duration)
                                }
                                app.music.config = mix.configuration
                                app.tab = .music
                                dismiss()
                            }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(mix.name)
                                Text(mix.trackName).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Button {
                            app.perform { try app.library.commit { $0.mixes.removeAll { $0.id == mix.id } } }
                        } label: {
                            Image(systemName: "trash").frame(width: 44, height: 44)
                        }
                    }
                }
            }.navigationTitle(T("music.mixes")).toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(T("common.done")) { dismiss() } }
            }
        }
    }
}
struct SystemMusicView: View {
    @EnvironmentObject var app: AppModel
    @State private var query = ""
    var body: some View {
        PlainScene {
            Notice(text: "music.systemHelp")
            if !app.systemMusic.authorized {
                LoomButton(title: "music.authorize") { Task { await app.systemMusic.authorize() } }
            } else {
                TextField(T("music.search"), text: $query).textFieldStyle(.roundedBorder).onSubmit {
                    Task { await app.systemMusic.search(query) }
                }
                LoomButton(title: "common.search", secondary: true) {
                    Task { await app.systemMusic.search(query) }
                }
                if app.systemMusic.searching { ProgressView() }
                ForEach(app.systemMusic.songs) { song in
                    Button {
                        Task { await app.systemMusic.choose(song) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(song.title)
                                Text(song.artistName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if app.systemMusic.selected?.id == song.id { Image(systemName: "checkmark") }
                        }.frame(minHeight: 50)
                    }
                }
            }
            if let song = app.systemMusic.selected {
                Text(song.title).font(.title2)
                Notice(text: app.systemMusic.systemEnabled ? "music.systemOn" : "music.systemOff")
                Notice(text: app.systemMusic.trackAvailable ? "music.trackAvailable" : "music.trackMissing")
                LoomButton(title: app.systemMusic.playing ? "music.pause" : "music.systemStart") {
                    if app.systemMusic.playing {
                        app.systemMusic.pause()
                    } else {
                        app.asyncPerform { try await app.systemMusic.play() }
                    }
                }.disabled(!app.systemMusic.systemEnabled || !app.systemMusic.trackAvailable)
            }
            if let e = app.systemMusic.error { Notice(text: e) }
            Button(T("common.openSettings")) {
                if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
            }.frame(minHeight: 44)
        }.navigationTitle(T("music.appleMusic"))
    }
}
