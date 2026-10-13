import SwiftUI
import WebKit

/// The hero artwork. "classic" draws the Canvas mandala/orb; every other id is one of the
/// composed pieces in App/Resources/LoomArt.html (offline, no network, no interaction),
/// driven only by the output level, the theme palette and the reduce-motion flags.
struct HeroArt: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.loom) var c
    @Environment(\.colorScheme) var scheme
    @Environment(\.accessibilityReduceMotion) var systemReduce
    @Environment(\.reducedArt) var customReduce
    var level = 0.0
    var playing = false
    var body: some View {
        if app.artwork == "classic" || !ArtworkCatalog.ids.contains(app.artwork) {
            LoomArt(style: app.theme.art, level: level)
        } else {
            LoomArtWeb(
                option: app.artwork, level: level, playing: playing, palette: c, dark: scheme == .dark,
                reduce: systemReduce || customReduce)
                .accessibilityHidden(true)
        }
    }
}

enum ArtworkCatalog {
    /// Order shown in the picker; "classic" is the Canvas drawing that follows the theme's art name.
    static let ids = ["saturn", "moon", "mandala", "lotus", "guilloche", "water", "ink", "silk"]
    /// Picker order: planets, then flowers and patterns (the theme-following Canvas drawing among them), then water.
    static let all = ["saturn", "moon", "mandala", "lotus", "classic", "guilloche", "water", "ink", "silk"]
    static let defaultsKey = "pulseloom.artwork"
}

struct LoomArtWeb: UIViewRepresentable {
    var option: String
    var level: Double
    var playing: Bool
    var palette: LoomColors
    var dark: Bool
    var reduce: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.scrollView.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.navigationDelegate = context.coordinator
        if let url = Bundle.main.url(forResource: "LoomArt", withExtension: "html") {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        context.coordinator.pending = configuration
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        let coordinator = context.coordinator
        let config = configuration
        if config != coordinator.lastConfiguration {
            coordinator.lastConfiguration = config
            coordinator.run(view, "window.loom && window.loom.configure(\(config))")
        }
        let value = (level * 100).rounded() / 100
        if value != coordinator.lastLevel || playing != coordinator.lastPlaying {
            coordinator.lastLevel = value
            coordinator.lastPlaying = playing
            coordinator.run(view, "window.loom && window.loom.set(\(value), \(playing))")
        }
    }
    private var configuration: String {
        let v = palette.values
        let keys = ["bg": v[0], "surface": v[1], "line": v[7], "accent": v[4], "ink": v[5], "muted": v[6], "hero1": v[9], "hero2": v[10], "hero3": v[11]]
        let json = keys.sorted { $0.key < $1.key }.map { "\"\($0.key)\":\"\($0.value)\"" }.joined(separator: ",")
        return "{\"option\":\"\(option)\",\"dark\":\(dark),\"reduce\":\(reduce),\"palette\":{\(json)}}"
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var ready = false
        var pending: String?
        var lastConfiguration: String?
        var lastLevel = -1.0
        var lastPlaying = false
        func run(_ view: WKWebView, _ script: String) {
            guard ready else { return }
            view.evaluateJavaScript(script) { _, _ in }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            if let pending {
                lastConfiguration = pending
                webView.evaluateJavaScript("window.loom && window.loom.configure(\(pending))") { _, _ in }
            }
            webView.evaluateJavaScript("window.loom && window.loom.set(\(max(0, lastLevel)), \(lastPlaying))") { _, _ in }
        }
    }
}

/// Thumbnail grid to choose the hero artwork; lives in the Themes & appearance sheet.
/// Thumbnails are still frames rendered from the same drawings (App/Resources/Artwork-<id>-<light|dark>.png).
struct ArtworkPicker: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.loom) var c
    @Environment(\.colorScheme) var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(ArtworkCatalog.all, id: \.self) { id in
                    let selected = app.artwork == id
                    Button { app.artwork = id } label: {
                        VStack(spacing: 5) {
                            thumbnail(id).aspectRatio(220 / 235, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Text(T("artwork." + id)).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .padding(6)
                        .background(c.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(selected ? c.accent : c.line, lineWidth: selected ? 1.5 : 0.8))
                        .foregroundStyle(c.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(T("artwork." + id))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("artwork." + id)
                }
            }
        }
    }
    @ViewBuilder private func thumbnail(_ id: String) -> some View {
        if id == "classic" {
            LoomArt(style: app.theme.art).padding(6).background(c.surface)
        } else if let image = UIImage(named: "Artwork-\(id)-\(scheme == .dark ? "dark" : "light")") {
            Image(uiImage: image).resizable()
        } else {
            Rectangle().fill(c.tint)
        }
    }
}

/// A colour-scheme card: background, a surface card, the accent pill and the three hero tones.
struct ThemeSwatch: View {
    let colors: LoomColors
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(colors.background)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(colors.surface)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(colors.line, lineWidth: 0.8))
                    .frame(height: 30)
                HStack(spacing: 6) {
                    Capsule().fill(colors.accent).frame(width: 44, height: 12)
                    Circle().fill(colors.hero1).frame(width: 12, height: 12)
                    Circle().fill(colors.hero2).frame(width: 12, height: 12)
                    Circle().fill(colors.hero3).frame(width: 12, height: 12)
                }
            }.padding(10)
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(colors.line, lineWidth: 0.8))
        .accessibilityHidden(true)
    }
}

/// The artwork sheet: a live preview on top, the thumbnail grid below.
struct ArtworkView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.loom) var c
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            PlainScene(spacing: 14) {
                HeroArt().frame(height: 200)
                Text(T("artwork.help")).font(.caption).foregroundStyle(c.muted)
                ArtworkPicker()
            }
            .navigationTitle(T("artwork.title")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(T("common.done")) { dismiss() } } }
        }
    }
}
