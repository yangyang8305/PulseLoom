import PulseLoomCore
import SwiftUI

@main struct PulseLoomApp: App {
    @StateObject private var app = AppModel()
    @StateObject private var editor = EditorModel()
    var body: some Scene { WindowGroup { RootView().environmentObject(app).environmentObject(editor) } }
}
struct RootView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var editor: EditorModel
    @Environment(\.colorScheme) var scheme
    @Environment(\.scenePhase) var scenePhase
    var dark: Bool { app.prefs.appearance == .dark || app.prefs.appearance == .auto && scheme == .dark }
    var body: some View {
        Group {
            if app.library.recoveryRequired {
                LibraryRecoveryView()
            } else if !app.prefs.onboarded {
                WelcomeView()
            } else {
                TabView(selection: $app.tab) {
                    NavigationStack { HomeView() }.tabItem { Label(T("tab.home"), systemImage: "house") }.tag(
                        MainTab.home)
                    NavigationStack { MusicView() }.tabItem {
                        Label(T("tab.music"), systemImage: "music.note")
                    }.tag(MainTab.music)
                    NavigationStack { CreateView() }.tabItem {
                        Label(T("tab.create"), systemImage: "pencil.tip")
                    }.tag(MainTab.create)
                    NavigationStack { MyView() }.tabItem { Label(T("tab.my"), systemImage: "person") }.tag(
                        MainTab.my)
                }.tint(Color(hex: dark ? app.theme.dark[4] : app.theme.light[4]))
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if app.tab != .home && !(app.tab == .music && app.music.isPlaying)
                            && (app.playback.isPlaying || app.music.isPlaying || app.sound.active
                                || app.systemMusic.playing)
                        {
                            MiniControl()
                        }
                    }
            }
        }
        .environment(\.loom, LoomColors(theme: app.theme, dark: dark))
        .environment(\.reducedArt, app.prefs.reduceMotion)
        .preferredColorScheme(app.prefs.appearance == .auto ? nil : dark ? .dark : .light)
        .overlay {
            if app.privacyHidden {
                ZStack {
                    Color(hex: dark ? app.theme.dark[0] : app.theme.light[0])
                    Text("Pulse Loom").font(.system(size: 39, design: .serif).italic()).foregroundStyle(
                        Color(hex: dark ? app.theme.dark[5] : app.theme.light[5]))
                }.ignoresSafeArea().accessibilityHidden(true)
            }
        }
        .sheet(item: $app.sheet) { route in
            sheet(route).environmentObject(app).environmentObject(editor).environment(
                \.loom, LoomColors(theme: app.theme, dark: dark))
        }
        .sheet(item: $app.share) { item in ShareSheet(url: item.url) }
        .sheet(isPresented: $app.showInvite) {
            NavigationStack { RemoteView() }.environmentObject(app).environment(
                \.loom, LoomColors(theme: app.theme, dark: dark))
        }
        .alert(
            T("common.error"),
            isPresented: Binding(get: { app.error != nil }, set: { if !$0 { app.error = nil } })
        ) {
            Button(T("common.done")) { app.error = nil }
        } message: {
            Text(app.error ?? "")
        }
        .onChange(of: scenePhase) { _, phase in
            editor.endTouch()
            if phase != .active { editor.end() }
            app.phase(phase)
        }
        .onChange(of: app.tab) { _, tab in
            if tab != .create {
                editor.endTouch()
                editor.end()
            }
        }
        .onChange(of: app.library.contentGeneration) { _, _ in
            editor.refreshLibraryBoundary()
        }
        .onOpenURL { app.handleURL($0) }
        .task {
            editor.attach(app)
            app.phase(scenePhase)
        }
    }
    @ViewBuilder private func sheet(_ route: SheetRoute) -> some View {
        switch route {
        case .presets: PresetPickerView()
        case .timer: TimerView().presentationDetents([.medium, .large])
        case .adjust: AdjustmentView().presentationDetents([.medium, .large])
        case .themes: ThemeView()
        case .premium: PremiumView()
        case .musicSources: NavigationStack { SystemMusicView() }
        case .mixes: MusicMixesView()
        case .focus: NavigationStack { FocusView() }
        }
    }
}
struct MiniControl: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.loom) var c
    var body: some View {
        HStack {
            Button {
                app.tab = app.music.isPlaying || app.systemMusic.playing ? .music : .home
            } label: {
                Text(
                    app.music.isPlaying
                        ? app.music.name
                        : app.systemMusic.playing
                            ? (app.systemMusic.selected?.title ?? T("music.appleMusic"))
                            : app.sound.active && !app.playback.isPlaying
                                ? T("sound.title") : app.playback.title
                ).font(.caption).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                if app.music.isPlaying {
                    app.music.pause()
                } else if app.systemMusic.playing {
                    app.systemMusic.pause()
                } else if app.sound.active && !app.playback.isPlaying {
                    app.sound.stop()
                } else {
                    app.playback.pause()
                }
            } label: {
                Image(systemName: "pause").frame(width: 44, height: 44)
            }
            Button {
                app.stopAll()
            } label: {
                Image(systemName: "stop").frame(width: 44, height: 44)
            }
        }.padding(.horizontal, 18).background(c.tint).foregroundStyle(c.ink)
    }
}
struct WelcomeView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.loom) var c
    @State private var showGuide = false
    @State private var page = 0
    @State private var showTest = false
    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 20)
            TactileArt(style: app.theme.art).frame(height: 230)
            Text("Pulse\nLoom").font(.system(size: 61, weight: .regular, design: .serif).italic())
                .multilineTextAlignment(.center)
            Text(T("welcome.subtitle")).font(.headline)
            Text(T("welcome.detail")).font(.footnote).multilineTextAlignment(.center).foregroundStyle(c.muted)
            Spacer(minLength: 25)
            LoomButton(title: "welcome.enter", symbol: "arrow.right") {
                app.perform { try app.library.preferences { $0.onboarded = true } }
            }.accessibilityIdentifier("welcomeEnter")
            Button(T("welcome.guide")) { showGuide = true }.frame(minHeight: 44)
        }.padding(25).frame(maxWidth: .infinity, maxHeight: .infinity).loomBackground()
            .sheet(isPresented: $showGuide) {
                NavigationStack {
                    PlainScene {
                        Text(T(page == 0 ? "welcome.guide1Title" : "welcome.guide2Title")).font(.largeTitle)
                        TactileArt(style: page == 0 ? "flower" : "orb").frame(height: 200)
                        Text(T(page == 0 ? "welcome.guide1" : "welcome.guide2"))
                        LoomButton(title: page == 0 ? "common.continue" : "welcome.test") {
                            if page == 0 { page = 1 } else { showTest = true }
                        }
                        LoomButton(title: "welcome.enter", secondary: true) {
                            app.perform { try app.library.preferences { $0.onboarded = true } }
                            showGuide = false
                        }
                    }.navigationTitle(T("welcome.guide")).navigationDestination(isPresented: $showTest) {
                        TroubleshootingView()
                    }.toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(T("common.close")) { showGuide = false }
                        }
                    }
                }
            }
    }
}
struct FocusView: View {
    @EnvironmentObject var app: AppModel
    var body: some View {
        PlainScene {
            Text(app.current.displayName()).font(.system(.largeTitle, design: .serif))
            TactileArt(style: app.theme.art, level: app.playback.level).frame(height: 235)
            Text(timeText(app.playback.remaining)).font(.title.monospacedDigit()).frame(maxWidth: .infinity)
            // Bind the mutable property on the existing coordinator; do not replace the service.
            Toggle(
                T("home.guard"),
                isOn: Binding(
                    get: { app.playback.guardEnabled },
                    set: { app.playback.guardEnabled = $0 }))
            LoomSlider(title: "home.intensity", value: app.pref(\.gain)) { app.perform { try app.adjust() } }
                .disabled(app.playback.guardEnabled)
            HapticDock()
        }.navigationTitle(T("home.focus"))
    }
}
