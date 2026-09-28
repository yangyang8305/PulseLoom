import PulseLoomCore
import SwiftUI

struct HomeView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.loom) var c
    @Environment(\.dynamicTypeSize) var textSize
    private let quick = ["p01", "p02", "p04", "p03", "p05", "p06"]
    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(T("home.title")).font(.title.bold())
                            Text(T("home.subtitle")).font(.footnote).foregroundStyle(c.muted)
                        }
                        Spacer()
                        Text("Pulse Loom").font(.system(.title3, design: .serif).italic()).foregroundStyle(
                            c.muted
                        ).padding(.top, 12)
                    }
                    VStack(spacing: 3) {
                        TactileArt(style: app.theme.art, level: app.playback.level).frame(
                            height: geo.size.height < 570 ? 90 : 145)
                        Text(app.current.displayName()).font(.system(.title2, design: .serif))
                            .accessibilityIdentifier("currentPattern")
                        Text(
                            app.current.builtin
                                ? T("pattern.subtitle." + app.current.id) : T("pattern.custom")
                        ).font(.caption).foregroundStyle(c.muted)
                    }.frame(maxWidth: .infinity)
                    HStack {
                        Text(T("home.presets")).font(.subheadline)
                        Spacer()
                        Button {
                            app.sheet = .presets
                        } label: {
                            Label(T("home.allPresets"), systemImage: "arrow.right").font(.caption)
                        }.frame(minHeight: 44)
                    }
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: 8),
                            count: textSize.isAccessibilitySize ? 2 : 3), spacing: 8
                    ) {
                        ForEach(quick, id: \.self) { id in
                            if let p = app.library.pattern(id) {
                                Button {
                                    app.select(p)
                                } label: {
                                    VStack(spacing: 5) {
                                        Text(p.displayName()).font(.subheadline)
                                        Text(T("pattern.subtitle." + p.id)).font(.caption2).foregroundStyle(
                                            c.muted
                                        ).lineLimit(1)
                                    }.frame(maxWidth: .infinity).padding(.vertical, 12).background(
                                        app.current.id == id ? c.tint : c.surface,
                                        in: RoundedRectangle(cornerRadius: 18)
                                    ).overlay(
                                        RoundedRectangle(cornerRadius: 18).stroke(
                                            app.current.id == id ? c.accent : c.line, lineWidth: 0.8))
                                }.buttonStyle(.plain).accessibilityIdentifier("preset." + id)
                                    .accessibilityAddTraits(app.current.id == id ? .isSelected : [])
                            }
                        }
                    }
                    LoomSlider(title: "home.intensity", value: app.pref(\.gain)) {
                        app.perform { try app.adjust() }
                    }.accessibilityIdentifier("homeIntensity")
                    HStack {
                        Button {
                            app.sheet = .timer
                        } label: {
                            Label(
                                String(format: T("home.timerFormat"), Int(app.prefs.timer / 60)),
                                systemImage: "clock"
                            ).font(.caption).padding(11).overlay(Capsule().stroke(c.line, lineWidth: 1))
                        }.accessibilityIdentifier("timerButton")
                        Spacer()
                        Button {
                            app.sheet = .adjust
                        } label: {
                            Label(T("home.adjust"), systemImage: "slider.horizontal.3").font(.caption)
                        }.frame(minHeight: 44)
                    }
                    if app.playback.state == .interrupted { Notice(text: "home.interrupted") }
                    if !app.playback.driver.supported {
                        Button {
                            app.error = T("error.hapticsUnavailable")
                        } label: {
                            Label(T("error.hapticsUnavailable"), systemImage: "info.circle").font(.caption)
                                .foregroundStyle(c.muted)
                        }.frame(minHeight: 44)
                    }
                }.padding(.horizontal, 23).padding(.top, 14).padding(.bottom, 14)
            }.safeAreaInset(edge: .bottom) {
                HapticDock().padding(.horizontal, 23).padding(.vertical, 10).background(c.background)
            }
        }.loomBackground().toolbar(.hidden, for: .navigationBar)
    }
}
struct HapticDock: View {
    @EnvironmentObject var app: AppModel
    var body: some View {
        VStack(spacing: 8) {
            if app.playback.isPlaying || app.playback.state == .paused {
                Text(T("home.remaining") + " " + timeText(app.playback.remaining)).font(.caption)
                    .monospacedDigit()
            }
            HStack(spacing: 12) {
                LoomButton(
                    title: app.playback.isPlaying
                        ? "home.pause" : app.playback.state == .paused ? "home.resume" : "home.start",
                    symbol: "power"
                ) { app.toggle() }.accessibilityIdentifier("hapticStart")
                LoomButton(title: "common.stop", symbol: "stop", secondary: true) { app.stopAll() }.frame(
                    width: 85
                ).accessibilityIdentifier("hapticStop")
            }
        }
    }
}
struct PresetPickerView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var query = ""
    @State private var filter = "all"
    @State private var category = "all"
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
            PlainScene {
                Picker(T("pattern.filter"), selection: $filter) {
                    Text(T("common.all")).tag("all")
                    Text(T("common.free")).tag("free")
                    Text(T("my.favorites")).tag("favorites")
                }.pickerStyle(.segmented)
                Picker(T("pattern.category"), selection: $category) {
                    Text(T("common.all")).tag("all")
                    ForEach(["基础", "轻柔", "节奏", "渐变", "custom"], id: \.self) { value in
                        Text(T("category." + value)).tag(value)
                    }
                }.pickerStyle(.menu)
                ForEach(filtered) { p in
                    HStack {
                        Button {
                            app.select(p)
                        } label: {
                            HStack(spacing: 14) {
                                PatternWave(pattern: p).frame(width: 58, height: 43)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(p.displayName())
                                    Text(String(format: T("pattern.cycleFormat"), p.durationMS / 1000)).font(
                                        .caption
                                    ).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if p.premium { Text("Pro").font(.caption2) }
                            }
                        }.buttonStyle(.plain)
                        NavigationLink {
                            PatternDetailView(pattern: p)
                        } label: {
                            Image(systemName: "info.circle").frame(width: 44, height: 44)
                        }
                    }.padding(.vertical, 6)
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
    let pattern: HapticPattern
    var body: some View {
        PlainScene {
            TactileArt(style: app.theme.art).frame(height: 145)
            Text(pattern.displayName()).font(.system(.largeTitle, design: .serif))
            PatternWave(pattern: pattern)
            Text(String(format: T("pattern.cycleFormat"), pattern.durationMS / 1000)).font(.caption)
            LoomButton(title: "pattern.preview", symbol: "hand.tap", secondary: true) { app.preview(pattern) }
            LoomButton(title: "pattern.use", symbol: "checkmark") {
                app.select(pattern)
                app.tab = .home
            }
            HStack {
                Button {
                    app.perform { try app.library.favorite(pattern.id) }
                } label: {
                    Label(
                        T("my.favorites"),
                        systemImage: app.library.snapshot.favorites.contains(pattern.id)
                            ? "heart.fill" : "heart"
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
    @Environment(\.dismiss) var dismiss
    @State private var seconds = 180.0
    var body: some View {
        NavigationStack {
            PlainScene {
                ForEach([60, 180, 300, 600], id: \.self) { n in
                    Button {
                        app.setTimer(Double(n))
                    } label: {
                        HStack {
                            Text(String(format: T("time.minutes"), n / 60))
                            Spacer()
                            if app.prefs.timer == Double(n) { Image(systemName: "checkmark") }
                        }.frame(minHeight: 45)
                    }
                }
                DisclosureGroup(T("timer.custom")) {
                    Stepper(
                        String(format: T("time.seconds"), Int(seconds)), value: $seconds, in: 30...600,
                        step: 30)
                    LoomButton(title: "common.apply") { app.setTimer(seconds) }
                }
                Notice(text: "timer.limit")
            }.navigationTitle(T("timer.title")).navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(T("common.done")) { dismiss() } }
            }.onAppear { seconds = app.prefs.timer }
        }
    }
}
struct AdjustmentView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            PlainScene {
                LoomSlider(title: "home.intensity", value: app.pref(\.gain)) {
                    app.perform { try app.adjust() }
                }
                LoomSlider(title: "home.speed", value: app.pref(\.speed), range: 0.5...2, unit: "×") {
                    app.perform { try app.adjust() }
                }
                LoomSlider(title: "home.texture", value: app.pref(\.sharpness)) {
                    app.perform { try app.adjust() }
                }
                Notice(text: "home.parametersHelp")
                LoomButton(title: "home.focus", secondary: true) { app.sheet = .focus }
                LoomButton(title: "common.reset", secondary: true) {
                    app.perform {
                        try app.library.preferences {
                            $0.gain = 0.55
                            $0.speed = 1
                            $0.sharpness = 0.25
                        }
                        try app.adjust()
                    }
                }
            }.navigationTitle(T("home.adjust")).navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(T("common.done")) { dismiss() } }
            }
        }
    }
}
