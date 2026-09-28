import PulseLoomCore
import SwiftUI
import UIKit

extension Color {
    init(hex: String) {
        let raw = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let n = UInt64(raw, radix: 16) ?? 0
        self.init(
            .sRGB, red: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255,
            blue: Double(n & 255) / 255, opacity: 1)
    }
}
struct LoomColors {
    let values: [String]
    init(theme: ThemeDefinition, dark: Bool) { values = dark ? theme.dark : theme.light }
    var background: Color { Color(hex: values[0]) }
    var surface: Color { Color(hex: values[1]) }
    var tint: Color { Color(hex: values[2]) }
    var tint2: Color { Color(hex: values[3]) }
    var accent: Color { Color(hex: values[4]) }
    var ink: Color { Color(hex: values[5]) }
    var muted: Color { Color(hex: values[6]) }
    var line: Color { Color(hex: values[7]) }
    var onAccent: Color { Color(hex: values[8]) }
    var hero1: Color { Color(hex: values[9]) }
    var hero2: Color { Color(hex: values[10]) }
    var hero3: Color { Color(hex: values[11]) }
}
private struct ReducedArtKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var reducedArt: Bool {
        get { self[ReducedArtKey.self] }
        set { self[ReducedArtKey.self] = newValue }
    }
}
private struct PaletteKey: EnvironmentKey {
    static let defaultValue = LoomColors(theme: Catalog.themes.first ?? .fallback, dark: false)
}
extension EnvironmentValues {
    var loom: LoomColors {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}
struct LoomBackground: ViewModifier {
    @Environment(\.loom) var c
    func body(content: Content) -> some View {
        content.background(c.background).foregroundStyle(c.ink).tint(c.accent)
    }
}
extension View { func loomBackground() -> some View { modifier(LoomBackground()) } }
struct LoomButton: View {
    @Environment(\.loom) var c
    let title: String
    var symbol: String?
    var secondary = false
    var destructive = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let symbol { Image(systemName: symbol) }
                Text(T(title)).font(.body)
            }.frame(maxWidth: .infinity).padding(.vertical, 15).padding(.horizontal, 15).foregroundStyle(
                destructive ? Color.red : secondary ? c.ink : c.onAccent
            ).background(secondary ? c.surface : c.accent, in: Capsule()).overlay(
                Capsule().stroke(secondary ? c.line : Color.clear, lineWidth: 1))
        }.buttonStyle(.plain).frame(minHeight: 48)
    }
}
struct LoomCard<Content: View>: View {
    @Environment(\.loom) var c
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding(17).frame(maxWidth: .infinity, alignment: .leading).background(
            c.surface, in: RoundedRectangle(cornerRadius: 23)
        ).overlay(RoundedRectangle(cornerRadius: 23).stroke(c.line.opacity(0.7), lineWidth: 0.7))
    }
}
struct LoomSlider: View {
    @Environment(\.loom) var c
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var unit = "%"
    var action: () -> Void = {}
    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text(T(title))
                Spacer()
                Text(unit == "%" ? "\(Int(value*100))%" : String(format: "%.1f %@", value, unit))
                    .foregroundStyle(c.muted).monospacedDigit()
            }.font(.subheadline)
            Slider(value: $value, in: range, onEditingChanged: { ending in if !ending { action() } }).tint(
                c.accent
            ).accessibilityLabel(T(title))
        }.padding(.vertical, 6)
    }
}
struct LoomSection: View {
    let title: String
    var body: some View {
        Text(T(title)).font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 15)
    }
}
struct Notice: View {
    @Environment(\.loom) var c
    let text: String
    var body: some View {
        Text(T(text)).font(.footnote).foregroundStyle(c.muted).frame(maxWidth: .infinity, alignment: .leading)
            .padding(13).background(c.tint, in: RoundedRectangle(cornerRadius: 15)).fixedSize(
                horizontal: false, vertical: true)
    }
}
struct EmptyState: View {
    @Environment(\.loom) var c
    let title: String
    let detail: String
    var symbol = "leaf"
    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: symbol).font(.system(size: 31, weight: .ultraLight)).foregroundStyle(c.accent)
            Text(T(title)).font(.title3)
            Text(T(detail)).font(.footnote).foregroundStyle(c.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 28)
    }
}
struct Petal: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.addCurve(
            to: CGPoint(x: r.midX, y: r.minY), control1: CGPoint(x: r.minX - r.width * 0.3, y: r.midY),
            control2: CGPoint(x: r.midX - r.width * 0.1, y: r.minY + r.height * 0.1))
        p.addCurve(
            to: CGPoint(x: r.midX, y: r.maxY), control1: CGPoint(x: r.maxX + r.width * 0.3, y: r.midY),
            control2: CGPoint(x: r.maxX, y: r.maxY - r.height * 0.2))
        return p
    }
}
struct TactileArt: View {
    @Environment(\.loom) var c
    @Environment(\.accessibilityReduceMotion) var systemReduce
    @Environment(\.reducedArt) var customReduce
    var reduce: Bool { systemReduce || customReduce }
    var style = "flower"
    var level = 0.0
    var body: some View {
        GeometryReader { g in
            ZStack {
                Ellipse().fill(
                    RadialGradient(
                        colors: [c.hero2.opacity(0.45), c.background.opacity(0)], center: .center,
                        startRadius: 8, endRadius: g.size.width * 0.5)
                ).frame(width: g.size.width, height: g.size.height)
                if style == "orb" || style == "moon" {
                    ForEach(0..<5) { i in
                        Ellipse().stroke(c.hero3.opacity(0.22 + Double(i) * 0.1), lineWidth: 0.8).frame(
                            width: g.size.width * (0.45 + Double(i) * 0.1),
                            height: g.size.height * (0.40 + Double(i) * 0.11)
                        ).rotationEffect(.degrees(Double(i) * 13 - 25)).scaleEffect(
                            reduce ? 1 : 1 + level * 0.08)
                    }
                } else {
                    ForEach(0..<9) { i in
                        Petal().fill(
                            LinearGradient(
                                colors: [
                                    c.hero1.opacity(0.65), c.hero2.opacity(0.66), c.hero3.opacity(0.24),
                                ], startPoint: .top, endPoint: .bottom)
                        ).overlay(Petal().stroke(c.surface.opacity(0.6), lineWidth: 0.5)).frame(
                            width: g.size.width * 0.24, height: g.size.height * 0.79
                        ).rotationEffect(.degrees(Double(i - 4) * 17), anchor: .bottom).offset(
                            y: -g.size.height * 0.02
                        ).scaleEffect(reduce ? 1 : 1 + level * 0.04)
                    }
                }
                Image(systemName: "iphone.radiowaves.left.and.right").font(
                    .system(size: 17, weight: .ultraLight)
                ).foregroundStyle(c.accent).padding(11).background(c.surface.opacity(0.85), in: Circle())
                    .offset(x: g.size.width * 0.35, y: g.size.height * 0.3)
            }.frame(width: g.size.width, height: g.size.height)
        }.accessibilityHidden(true)
    }
}
struct PatternWave: View {
    @Environment(\.loom) var c
    let pattern: HapticPattern
    var body: some View {
        GeometryReader { g in
            Path { p in
                for i in 0..<120 {
                    let x = Double(i) / 119
                    let y = PatternMath.level(pattern, at: x * pattern.durationMS / 1000)
                    let q = CGPoint(x: x * g.size.width, y: (1 - y) * g.size.height * 0.75 + 8)
                    if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
                }
            }.stroke(c.accent, lineWidth: 1.5)
        }.frame(height: 55).accessibilityLabel(T("pattern.wave"))
    }
}
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
struct PlainScene<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17, content: content).padding(.horizontal, 23).padding(
                .vertical, 15)
        }.loomBackground()
    }
}
