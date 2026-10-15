import MusicKit
import PulseLoomCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// One screen: artwork, the chosen song, feel, strength, position and the play/stop dock.
/// Everything that is rarely touched lives in the "More adjustments" sheet.
struct MusicView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.loom) var c
    @State private var importing = false
    @State private var advanced = false
    @State private var library = false
    @State private var outputSettings = false
    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 640
            VStack(alignment: .leading, spacing: compact ? 8 : 12) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(T("music.title")).font(.system(.title3, design: .serif).italic())
                        Text(T("music.subtitle")).font(.caption2).foregroundStyle(c.muted).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    LoomIconButton(symbol: "lock", label: T("lock.enter")) { app.lockPrompt = true }
                    if app.music.analysis != nil {
                        LoomIconButton(symbol: "slider.horizontal.3", label: T("music.more")) { advanced = true }
                    }
                }
                HeroArt(level: app.music.requestedLevel, playing: app.music.isPlaying)
                    .frame(maxWidth: .infinity, minHeight: 104, maxHeight: .infinity)
                if app.music.status == .loading {
                    ProgressView(T("music.analyzing")).frame(maxWidth: .infinity)
                    LoomButton(title: "common.cancel", secondary: true, compact: true) { app.music.cancelLoad() }
                } else if app.music.analysis != nil {
                    loaded
                } else {
                    Text(T("music.bringSong")).font(.system(.title3, design: .serif)).frame(maxWidth: .infinity)
                    TrackShelf()
                    LoomButton(title: "music.select", symbol: "plus", secondary: true) { importing = true }
                        .accessibilityIdentifier("selectMusic")
                    Text(T("music.localHelp")).font(.caption2).foregroundStyle(c.muted).lineLimit(2)
                }
                if app.music.status != .loading { sources }
                if let error = app.music.error {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(error).font(.caption).foregroundStyle(c.muted)
                            if UserFacingError.isOutputMessage(error) {
                                Button(T("touch.checkDevice")) { outputSettings = true }
                                    .font(.caption).accessibilityIdentifier("musicCheckOutput")
                            }
                        }
                        Spacer()
                        Button(T("common.dismiss")) { app.music.error = nil }.font(.caption)
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 8)
        }
        .loomBackground().toolbar(.hidden, for: .navigationBar)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            app.perform {
                guard let u = try result.get().first else { return }
                app.music.load(url: u)
            }
        }
        .sheet(isPresented: $advanced) { MusicAdvancedView().environmentObject(app).environment(\.loom, c) }
        .sheet(isPresented: $library) { MusicLibraryView().environmentObject(app).environment(\.loom, c) }
        .sheet(isPresented: $outputSettings) {
            NavigationStack { HapticOutputsView().toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(T("common.done")) { outputSettings = false } }
            } }.environmentObject(app).environment(\.loom, c)
        }
    }
    private var loaded: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "music.note").foregroundStyle(c.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.music.name).font(.subheadline.weight(.medium)).lineLimit(1)
                    Text(timeText(app.music.position) + " / " + timeText(app.music.duration))
                        .font(.caption.monospacedDigit()).foregroundStyle(c.muted)
                }
                Spacer()
                Button(T("music.change")) { importing = true }.font(.subheadline).frame(minHeight: 44)
            }
            Picker(T("music.feel"), selection: Binding(get: { app.music.feel }, set: { app.music.apply($0) })) {
                ForEach(MusicFeel.allCases, id: \.self) { f in Text(T("music.feel." + f.rawValue)).tag(f) }
            }.pickerStyle(.segmented)
            LoomSlider(
                title: "home.intensity",
                value: Binding(get: { app.music.config.gain }, set: { app.music.config.gain = $0 }))
            Slider(
                value: Binding(get: { app.music.position }, set: { app.music.seek($0) }),
                in: 0...max(0.1, app.music.duration)
            ).tint(c.accent).accessibilityLabel(T("music.progress"))
            HStack(spacing: 10) {
                LoomButton(
                    title: app.music.isPlaying ? "music.pause" : "music.start",
                    symbol: app.music.isPlaying ? "pause.fill" : "play.fill"
                ) { app.perform { try app.music.play() } }
                LoomButton(title: "common.stop", symbol: "stop.fill", secondary: true, fill: false) { app.stopAll() }
            }
        }
    }
    private var sources: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                LoomChip(title: T("music.library"), symbol: "music.note.list") { library = true }
                    .accessibilityIdentifier("musicLibrary")
                NavigationLink { SystemMusicView() } label: { ChipLabel(title: T("music.appleMusic"), symbol: "music.note.list") }
                    .buttonStyle(.plain)
            }.padding(.vertical, 4).padding(.horizontal, 2)
        }
    }
}
/// One row of the bundled pieces; the loaded one is highlighted.
struct TrackShelf: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.loom) var c
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(T("music.library")).font(.caption.weight(.semibold)).foregroundStyle(c.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BundledMusic.tracks) { t in
                        LoomChip(
                            title: t.displayName(), detail: T("music.style." + t.style),
                            selected: app.music.bundledID == t.id
                        ) { app.music.loadBundled(t) }
                        .accessibilityIdentifier("track." + t.id)
                    }
                }.padding(.horizontal, 2).padding(.vertical, 4)
            }
        }
    }
}

/// The full list of bundled pieces with style, tempo and length.
struct MusicLibraryView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.loom) var c
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            PlainScene(spacing: 10) {
                Text(T("music.libraryHelp")).font(.caption).foregroundStyle(c.muted)
                ForEach(BundledMusic.tracks) { t in
                    Button {
                        app.music.loadBundled(t)
                        dismiss()
                    } label: {
                        LoomRow(
                            title: t.displayName(),
                            symbol: app.music.bundledID == t.id ? "waveform" : "music.note",
                            subtitle: T("music.style." + t.style) + " · " + String(format: T("music.bpmFormat"), t.bpm)
                                + " · " + timeText(t.seconds))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("library." + t.id)
                }
            }
            .navigationTitle(T("music.libraryTitle")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(T("common.done")) { dismiss() } } }
        }
    }
}

/// Chip styling for navigation links (which cannot reuse the button chip).
struct ChipLabel: View {
    @Environment(\.loom) var c
    let title: String
    var symbol: String?
    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).font(.caption.weight(.semibold)) }
            Text(title).font(.subheadline).lineLimit(1)
        }
        .padding(.vertical, 9).padding(.horizontal, 13).foregroundStyle(c.ink)
        .background(c.surface.opacity(0.9), in: Capsule())
        .overlay(Capsule().strokeBorder(c.line, lineWidth: 0.8))
        .frame(minHeight: 44)
    }
}

struct MusicAdvancedView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.loom) var c
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            PlainScene(spacing: 14) {
                LoomSlider(
                    title: "music.volume",
                    value: Binding(get: { app.music.config.volume }, set: { app.music.config.volume = $0 }))
                LoomSlider(
                    title: "music.sensitivity",
                    value: Binding(get: { app.music.config.sensitivity }, set: { app.music.config.sensitivity = $0 }))
                Picker(
                    T("music.mapping"),
                    selection: Binding(
                        get: { app.music.config.mapping == .blend ? .energy : app.music.config.mapping },
                        set: { app.music.config.mapping = $0 })
                ) {
                    ForEach([MusicMapping.energy, .beats], id: \.self) { m in Text(T("music.mapping." + m.rawValue)).tag(m) }
                }.pickerStyle(.segmented)
                Text(T("music.analysisHelp")).font(.caption).foregroundStyle(c.muted)
            }
            .navigationTitle(T("music.more")).navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(T("common.done")) { dismiss() } }
            }
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
                LoomButton(title: "common.search", secondary: true, compact: true) {
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
