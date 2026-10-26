import PulseLoomCore
import SwiftUI

/// The main screen lays itself out to fit one screen: artwork, the current piece, two shelves of
/// choices, strength, and an always-visible start/stop dock. Nothing here scrolls vertically.
struct HomeView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.loom) var c
    @Environment(\.dynamicTypeSize) var typeSize
    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 640
            if typeSize.isAccessibilitySize {
                // Accessibility text sizes cannot fit one screen: scroll, keep the dock pinned below.
                VStack(spacing: 8) {
                    ScrollView {
                        content(spacing: 11, artHeight: min(220, geo.size.height * 0.3))
                    }
                    HapticDock().padding(.horizontal, 20).padding(.bottom, 8)
                }
            } else {
                VStack(alignment: .leading, spacing: compact ? 7 : 11) {
                    content(spacing: compact ? 7 : 11, artHeight: nil)
                    HapticDock()
                }
                .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 8)
            }
        }
        .loomBackground().toolbar(.hidden, for: .navigationBar)
    }
    /// Everything above the dock. `artHeight` nil lets the artwork take the remaining space.
    @ViewBuilder private func content(spacing: CGFloat, artHeight: CGFloat?) -> some View {
        let art = HeroArt(level: app.playback.level, playing: app.playback.isPlaying)
        let shelf = PatternShelf(title: favorites.isEmpty ? "home.loops" : "home.favorites", patterns: favorites.isEmpty ? Catalog.presets : favorites)
        let slider = LoomSlider(title: "home.intensity", value: app.pref(\.gain), live: { app.adjustLive(gain: $0) }) {
            app.perform { try app.adjust() }
        }.accessibilityIdentifier("homeIntensity")
        if let artHeight {
            VStack(alignment: .leading, spacing: spacing) {
                header
                art.frame(maxWidth: .infinity).frame(height: artHeight)
                nameplate
                shelf
                slider
                status
            }
            .padding(.horizontal, 20).padding(.top, 6)
        } else {
            header
            art.frame(maxWidth: .infinity, minHeight: 104, maxHeight: .infinity)
            nameplate
            shelf
            slider
            status
        }
    }
    /// Built-in rhythms the user marked with a heart, in catalog order.
    private var favorites: [HapticPattern] {
        let ids = Set(app.library.snapshot.favorites)
        return Catalog.presets.filter { ids.contains($0.id) }
    }
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Pulse Loom").font(.system(.title3, design: .serif).italic())
                Text(T("home.subtitle")).font(.caption2).foregroundStyle(c.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            LoomChip(
                title: String(format: T("time.minutes"), Int(app.prefs.timer / 60)), symbol: "clock"
            ) { app.sheet = .timer }
                .accessibilityIdentifier("timerButton")
            LoomIconButton(symbol: "square.grid.2x2", label: T("home.allPresets")) { app.sheet = .presets }
            LoomIconButton(symbol: "lock", label: T("lock.enter")) { app.lockPrompt = true }.accessibilityIdentifier("lockButton")
        }
    }
    private var nameplate: some View {
        VStack(spacing: 2) {
            Text(app.current.displayName()).font(.system(.title2, design: .serif))
                .lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityIdentifier("currentPattern")
            Text(app.current.builtin ? T("pattern.subtitle." + app.current.id) : T("pattern.custom"))
                .font(.caption).foregroundStyle(c.muted).lineLimit(1)
        }.frame(maxWidth: .infinity)
    }
    @ViewBuilder private var status: some View {
        if app.playback.state == .interrupted {
            Text(T("home.interrupted")).font(.caption).foregroundStyle(c.muted).lineLimit(1)
        } else if let warning = app.playback.outputs.lastFallbackReason {
            Text(String(format: T("output.fallbackFormat"), warning)).font(.caption).foregroundStyle(c.muted).lineLimit(1)
        } else if !app.playback.outputs.supported {
            Button {
                app.error = T("error.hapticsUnavailable")
            } label: {
                Label(T("error.hapticsUnavailable"), systemImage: "info.circle").font(.caption).foregroundStyle(c.muted).lineLimit(1)
            }
        } else {
            HStack {
                Text(String(
                    format: T("output.targetFormat"),
                    app.playback.isPlaying ? app.playback.outputs.activeName : app.playback.outputs.selectedName))
                Spacer()
                if app.playback.isPlaying || app.playback.state == .paused {
                    Text(T("home.remaining") + " " + timeText(app.playback.remaining)).monospacedDigit()
                }
            }.font(.caption).foregroundStyle(c.muted).lineLimit(1)
        }
    }
}

/// One horizontal shelf of selectable chips; the current selection is highlighted.
struct PatternShelf: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.loom) var c
    let title: String
    let patterns: [HapticPattern]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(T(title)).font(.caption.weight(.semibold)).foregroundStyle(c.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(patterns) { p in
                        LoomChip(
                            title: p.displayName(),
                            symbol: p.premium && !app.pro ? "lock" : nil,
                            detail: nil,
                            selected: app.current.id == p.id
                        ) { app.select(p) }
                        .accessibilityIdentifier("preset." + p.id)
                    }
                }.padding(.horizontal, 2).padding(.vertical, 4)
            }
        }
    }
}

struct HapticDock: View {
    @EnvironmentObject var app: AppModel
    var body: some View {
        HStack(spacing: 10) {
            LoomButton(
                title: app.playback.isPlaying
                    ? "home.pause" : app.playback.state == .paused ? "home.resume" : "home.start",
                symbol: app.playback.isPlaying ? "pause.fill" : "play.fill"
            ) { app.toggle() }.accessibilityIdentifier("hapticStart")
            LoomButton(title: "common.stop", symbol: "stop.fill", secondary: true, fill: false) { app.stopAll() }
                .accessibilityIdentifier("hapticStop")
            LoomIconButton(symbol: "slider.horizontal.3", label: T("home.adjust")) { app.sheet = .adjust }
        }
    }
}

struct PresetPickerView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.loom) var c
    @Environment(\.dismiss) var dismiss
    @State private var query = ""
    @State private var filter = "all"
    @State private var category = "all"
    private let categories = ["基础", "轻柔", "节奏", "渐变", "custom"]
    var filtered: [HapticPattern] {
        app.library.allPatterns.filter { p in
            (query.isEmpty
                || [p.name, p.englishName, p.japaneseName].joined().localizedCaseInsensitiveContains(query))
                && (filter == "all" || filter == "free" && !p.premium
                    || filter == "favorites" && app.library.snapshot.favorites.contains(p.id))
                && (category == "all" || category == p.category)
        }
    }
    var body: some View {
        NavigationStack {
            PlainScene(spacing: 12) {
                Picker(T("pattern.filter"), selection: $filter) {
                    Text(T("common.all")).tag("all")
                    Text(T("common.free")).tag("free")
                    Text(T("my.favorites")).tag("favorites")
                }.pickerStyle(.segmented)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        LoomChip(title: T("common.all"), selected: category == "all") { category = "all" }
                        ForEach(categories, id: \.self) { value in
                            LoomChip(title: T("category." + value), selected: category == value) { category = value }
                        }
                    }.padding(.vertical, 2)
                }
                ForEach(filtered) { p in
                    HStack(spacing: 10) {
                        Button {
                            app.select(p)
                        } label: {
                            HStack(spacing: 12) {
                                PatternWave(pattern: p).frame(width: 64, height: 40)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(p.displayName()).font(.body)
                                    Text(
                                        p.category == Catalog.pieceCategory
                                            ? String(format: T("pattern.durationShort"), Int(p.durationMS / 1000))
                                            : String(format: T("pattern.cycleFormat"), p.durationMS / 1000)
                                    ).font(.caption).foregroundStyle(c.muted)
                                }
                                Spacer()
                                if app.current.id == p.id { Image(systemName: "checkmark").foregroundStyle(c.accent) }
                                if p.premium { Text("Pro").font(.caption2.weight(.semibold)).foregroundStyle(c.muted) }
                            }
                        }.buttonStyle(.plain)
                        let loved = app.library.snapshot.favorites.contains(p.id)
                        Button { app.perform { try app.library.favorite(p.id) } } label: {
                            Image(systemName: loved ? "heart.fill" : "heart").foregroundStyle(loved ? c.accent : c.muted).frame(width: 40, height: 40)
                        }.accessibilityLabel(T("pattern.favorite")).accessibilityAddTraits(loved ? .isSelected : [])
                        .accessibilityIdentifier("favorite." + p.id)
                        NavigationLink {
                            PatternDetailView(pattern: p)
                        } label: {
                            Image(systemName: "info.circle").frame(width: 40, height: 40)
                        }
                    }.padding(.vertical, 3)
                }
                if filtered.isEmpty { EmptyState(title: "empty.search", detail: "empty.searchHelp") }
            }.searchable(text: $query, prompt: Text(T("pattern.search"))).navigationTitle(
                T("home.allPresets")
            ).navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(T("common.done")) { dismiss() } }
            }
        }
    }
}

struct PatternDetailView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var editor: EditorModel
    @Environment(\.loom) var c
    let pattern: HapticPattern
    var body: some View {
        PlainScene {
            LoomArt(style: app.theme.art).frame(height: 130)
            Text(pattern.displayName()).font(.system(.largeTitle, design: .serif)).frame(maxWidth: .infinity)
            if pattern.builtin {
                Text(T("pattern.subtitle." + pattern.id)).font(.footnote).foregroundStyle(c.muted).frame(maxWidth: .infinity)
            }
            LoomCard(padding: 12) { PatternWave(pattern: pattern) }
            Text(
                pattern.category == Catalog.pieceCategory
                    ? String(format: T("pattern.durationShort"), Int(pattern.durationMS / 1000))
                    : String(format: T("pattern.cycleFormat"), pattern.durationMS / 1000)
            ).font(.caption).foregroundStyle(c.muted)
            LoomButton(title: "pattern.use", symbol: "checkmark") {
                app.select(pattern)
                app.tab = .home
            }
            HStack(spacing: 10) {
                LoomButton(title: "pattern.preview", symbol: "hand.tap", secondary: true) { app.preview(pattern) }
                LoomButton(title: "common.stop", symbol: "stop.fill", secondary: true, fill: false) { app.stopAll() }
            }
            HStack {
                Button {
                    app.perform { try app.library.favorite(pattern.id) }
                } label: {
                    Label(
                        T("my.favorites"),
                        systemImage: app.library.snapshot.favorites.contains(pattern.id) ? "heart.fill" : "heart"
                    ).frame(minHeight: 44)
                }
                Spacer()
                Button {
                    app.export(pattern, name: "PulseLoom-pattern")
                } label: {
                    Label(T("common.export"), systemImage: "square.and.arrow.up").frame(minHeight: 44)
                }
            }
            LoomButton(title: "pattern.copyEdit", symbol: "pencil", secondary: true) {
                app.perform {
                    guard Entitlements.canPlay(pattern, pro: app.pro) else { throw LoomError.entitlement }
                    editor.edit(pattern, copy: true)
                    app.sheet = nil
                    app.tab = .create
                }
            }
        }.navigationTitle(T("pattern.details")).onDisappear {
            if app.playback.kind == "preview" { app.playback.stop() }
        }
    }
}

struct TimerView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.loom) var c
    @Environment(\.dismiss) var dismiss
    @State private var minutes = 3.0
    var body: some View {
        NavigationStack {
            PlainScene(spacing: 10) {
                ForEach([60, 180, 300, 600, 900, 1800, 3600], id: \.self) { n in
                    Button {
                        app.setTimer(Double(n))
                    } label: {
                        HStack {
                            Text(String(format: T("time.minutes"), n / 60))
                            Spacer()
                            if app.prefs.timer == Double(n) { Image(systemName: "checkmark").foregroundStyle(c.accent) }
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Divider()
                }
                DisclosureGroup(T("timer.custom")) {
                    Stepper(
                        String(format: T("time.minutes"), Int(minutes)), value: $minutes, in: 1...120, step: 1)
                    LoomButton(title: "common.apply", compact: true) { app.setTimer(minutes * 60) }
                }
            }.navigationTitle(T("timer.title")).navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(T("common.done")) { dismiss() } }
            }.onAppear { minutes = max(1, (app.prefs.timer / 60).rounded()) }
        }
    }
}

/// Secondary feel controls live here so the home screen only carries strength.
struct AdjustmentView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var showTest = false
    var body: some View {
        NavigationStack {
            PlainScene(spacing: 14) {
                LoomSlider(title: "home.intensity", value: app.pref(\.gain), live: { app.adjustLive(gain: $0) }) {
                    app.perform { try app.adjust() }
                }
                LoomSlider(
                    title: "home.speed", value: app.pref(\.speed), range: 0.5...2, unit: "×",
                    live: { app.adjustLive(speed: $0) }
                ) {
                    app.perform { try app.adjust() }
                }
                LoomSlider(title: "home.texture", value: app.pref(\.sharpness), live: { app.adjustLive(sharp: $0) }) {
                    app.perform { try app.adjust() }
                }
                Notice(text: "home.parametersHelp")
                HStack(spacing: 10) {
                    LoomButton(title: "home.testHaptics", symbol: "bolt", secondary: true, compact: true) { showTest = true }
                        .accessibilityIdentifier("homeTestStrength")
                    LoomButton(title: "common.reset", secondary: true, compact: true) {
                    app.perform {
                        let defaults = Preferences()
                        try app.library.preferences {
                            $0.gain = defaults.gain
                            $0.speed = defaults.speed
                            $0.sharpness = defaults.sharpness
                        }
                        try app.adjust()
                    }
                }
                }
            }.navigationDestination(isPresented: $showTest) { FirstTouchView(app: app) }
            .navigationTitle(T("home.adjust")).navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(T("common.done")) { dismiss() } }
            }
        }
    }
}
