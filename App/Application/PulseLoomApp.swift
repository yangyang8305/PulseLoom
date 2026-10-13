import PulseLoomCore
import SwiftUI

@main struct PulseLoomApp: App {
    @StateObject private var app = AppModel()
    @StateObject private var editor = EditorModel()
    init() { AppLanguage.restore() }
    var body: some Scene {
        WindowGroup { RootView().environmentObject(app).environmentObject(editor).id(app.language).environment(\.locale, AppLanguage.locale) }
    }
}
struct RootView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var editor: EditorModel
    @Environment(\.colorScheme) var scheme
    @Environment(\.scenePhase) var scenePhase
    var dark: Bool { app.prefs.appearance == .dark || app.prefs.appearance == .auto && scheme == .dark }
    var body: some View {
        ZStack {
            content
            if app.locked { LockScreenView().transition(.opacity).zIndex(10) }
        }
        .animation(.easeInOut(duration: 0.25), value: app.locked)
        .alert(T("lock.confirmTitle"), isPresented: $app.lockPrompt) {
            Button(T("lock.confirm")) { app.lock() }.accessibilityIdentifier("lockConfirm")
            Button(T("common.cancel"), role: .cancel) {}
        } message: {
            Text(T("lock.confirmMessage"))
        }
    }
    private var content: some View {
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
                .preferredColorScheme(app.prefs.appearance == .auto ? nil : dark ? .dark : .light)
        }
        .sheet(item: $app.share) { item in ShareSheet(url: item.url) }
        .sheet(isPresented: $app.showInvite) {
            NavigationStack { RemoteView() }.environmentObject(app).environment(
                \.loom, LoomColors(theme: app.theme, dark: dark))
                .preferredColorScheme(app.prefs.appearance == .auto ? nil : dark ? .dark : .light)
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
        case .artwork: ArtworkView()
        case .premium: PremiumView()
        case .musicSources: NavigationStack { SystemMusicView() }
        case .mixes: MusicMixesView()
        }
    }
}
struct WelcomeView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.loom) var c
    @State private var showGuide = false
    @State private var page = 0
    @State private var showTest = false
    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 12)
            HeroArt().frame(maxHeight: 260)
            Text("Pulse Loom").font(.system(size: 44, weight: .regular, design: .serif).italic())
                .multilineTextAlignment(.center)
            Text(T("welcome.subtitle")).font(.headline)
            Text(T("welcome.detail")).font(.footnote).multilineTextAlignment(.center).foregroundStyle(c.muted)
            Spacer(minLength: 12)
            LoomButton(title: "welcome.enter", symbol: "arrow.right") {
                app.perform { try app.library.preferences { $0.onboarded = true } }
            }.accessibilityIdentifier("welcomeEnter")
            Button(T("welcome.guide")) { showGuide = true }.frame(minHeight: 44)
        }.padding(25).frame(maxWidth: .infinity, maxHeight: .infinity).loomBackground()
            .sheet(isPresented: $showGuide) {
                NavigationStack {
                    PlainScene {
                        Text(T(page == 0 ? "welcome.guide1Title" : "welcome.guide2Title")).font(.largeTitle)
                        LoomArt(style: page == 0 ? "flower" : "orb").frame(height: 200)
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
