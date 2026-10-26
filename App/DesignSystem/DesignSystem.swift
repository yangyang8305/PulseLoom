import PulseLoomCore
import SwiftUI
import UIKit

// MARK: - Palette

extension Color {
    init(hex: String) {
        let raw = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let n = UInt64(raw, radix: 16) ?? 0
        self.init(
            .sRGB, red: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255,
            blue: Double(n & 255) / 255, opacity: 1)
    }
    /// Small HSB shifts give highlights and gradients without a second palette.
    func shifted(brightness: Double = 0, saturation: Double = 0) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return Color(
            hue: Double(h), saturation: min(1, max(0, Double(s) + saturation)),
            brightness: min(1, max(0, Double(b) + brightness)), opacity: Double(a))
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

// MARK: - Background texture

/// A jali-inspired lattice drawn tone-on-tone, so screens carry a quiet pattern instead of flat paint.
struct LoomLattice: View {
    @Environment(\.loom) var c
    var opacity = 0.042
    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            let step: CGFloat = 54
            var stars = Path()
            var dots = Path()
            var y: CGFloat = -step
            var row = 0
            while y < size.height + step {
                var x: CGFloat = (row % 2 == 0 ? 0 : step / 2) - step
                while x < size.width + step {
                    let r = step * 0.3
                    for i in 0..<8 {
                        let a = Double(i) / 8 * 2 * .pi, a2 = a + .pi / 8
                        let outer = CGPoint(x: x + CGFloat(cos(a)) * r, y: y + CGFloat(sin(a)) * r)
                        let inner = CGPoint(x: x + CGFloat(cos(a2)) * r * 0.52, y: y + CGFloat(sin(a2)) * r * 0.52)
                        if i == 0 { stars.move(to: outer) } else { stars.addLine(to: outer) }
                        stars.addLine(to: inner)
                    }
                    stars.closeSubpath()
                    dots.addEllipse(in: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3))
                    x += step
                }
                y += step * 0.86
                row += 1
            }
            context.stroke(stars, with: .color(c.ink.opacity(opacity)), lineWidth: 0.55)
            context.fill(dots, with: .color(c.accent.opacity(opacity * 1.6)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
struct LoomBackground: ViewModifier {
    @Environment(\.loom) var c
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    c.background
                    LinearGradient(
                        colors: [c.hero1.opacity(0.32), c.background.opacity(0)], startPoint: .top,
                        endPoint: .center)
                    LoomLattice()
                }.ignoresSafeArea()
            }
            .foregroundStyle(c.ink).tint(c.accent)
    }
}
extension View { func loomBackground() -> some View { modifier(LoomBackground()) } }

// MARK: - Buttons

enum LoomButtonRole { case primary, secondary, quiet, destructive }
struct LoomButtonStyle: ButtonStyle {
    @Environment(\.loom) var c
    let role: LoomButtonRole
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .subheadline.weight(.medium) : .body.weight(.medium))
            .padding(.vertical, compact ? 9 : 14).padding(.horizontal, compact ? 14 : 18)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .overlay(Capsule().strokeBorder(border, lineWidth: 0.8))
            .overlay(
                Capsule().strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(role == .primary ? 0.32 : 0.55), .clear],
                        startPoint: .top, endPoint: .center), lineWidth: 1
                ).padding(0.8))
            .shadow(color: shadow, radius: role == .primary ? 9 : 3, y: role == .primary ? 4 : 1.5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
    private var foreground: Color {
        switch role {
        case .primary: return c.onAccent
        case .destructive: return Color(red: 0.72, green: 0.22, blue: 0.24)
        default: return c.ink
        }
    }
    private var background: AnyShapeStyle {
        switch role {
        case .primary:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [c.accent.shifted(brightness: 0.08), c.accent, c.accent.shifted(brightness: -0.07)],
                    startPoint: .top, endPoint: .bottom))
        case .quiet: return AnyShapeStyle(c.tint.opacity(0.75))
        default:
            return AnyShapeStyle(
                LinearGradient(colors: [c.surface, c.surface.shifted(brightness: -0.025)], startPoint: .top, endPoint: .bottom))
        }
    }
    private var border: Color { role == .primary ? .clear : c.line }
    private var shadow: Color { role == .primary ? c.accent.opacity(0.28) : Color.black.opacity(0.06) }
}
/// `fill` keeps the capsule at its natural width (no fixed widths, so labels never wrap mid-word).
struct LoomButton: View {
    let title: String
    var symbol: String?
    var secondary = false
    var destructive = false
    var compact = false
    var fill = true
    var multiline = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol).font(.body.weight(.medium)) }
                Text(T(title)).lineLimit(multiline ? nil : 1).minimumScaleFactor(multiline ? 1 : 0.8)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: multiline)
            }.frame(maxWidth: fill ? .infinity : nil)
        }
        .buttonStyle(
            LoomButtonStyle(
                role: destructive ? .destructive : secondary ? .secondary : .primary, compact: compact))
        .frame(minHeight: compact ? 36 : 48)
    }
}
/// A small selectable capsule for lists of choices that must stay on one screen.
struct LoomChip: View {
    @Environment(\.loom) var c
    let title: String
    var symbol: String?
    var detail: String?
    var selected = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.caption.weight(.semibold)) }
                Text(title).font(.subheadline.weight(selected ? .semibold : .regular)).lineLimit(1)
                if let detail { Text(detail).font(.caption2).foregroundStyle(selected ? c.onAccent.opacity(0.85) : c.ink.opacity(0.72)) }
            }
            .padding(.vertical, 9).padding(.horizontal, 13)
            .foregroundStyle(selected ? c.onAccent : c.ink)
            .background(
                selected
                    ? AnyShapeStyle(LinearGradient(colors: [c.accent.shifted(brightness: 0.06), c.accent], startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(c.surface.opacity(0.9)),
                in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.clear : c.line, lineWidth: 0.8))
            .shadow(color: selected ? c.accent.opacity(0.25) : .clear, radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel(detail.map { title + " " + $0 } ?? title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
struct LoomIconButton: View {
    @Environment(\.loom) var c
    let symbol: String
    let label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.body.weight(.medium)).frame(width: 44, height: 44)
                .foregroundStyle(c.accent)
                .background(c.surface.opacity(0.9), in: Circle())
                .overlay(Circle().strokeBorder(c.line, lineWidth: 0.8))
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}

// MARK: - Containers

struct LoomCard<Content: View>: View {
    @Environment(\.loom) var c
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [c.surface, c.surface.shifted(brightness: -0.015)], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(c.line.opacity(0.8), lineWidth: 0.7))
            .shadow(color: Color.black.opacity(0.05), radius: 8, y: 3)
    }
}
struct LoomRow: View {
    @Environment(\.loom) var c
    let title: String
    let symbol: String
    var subtitle = ""
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol).font(.body.weight(.medium)).frame(width: 30, height: 30)
                .foregroundStyle(c.accent).background(c.tint, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(T(title)).font(.subheadline)
                if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(c.muted) }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(c.muted)
        }.frame(minHeight: 48).contentShape(Rectangle()).foregroundStyle(c.ink)
    }
}
struct LoomSection: View {
    @Environment(\.loom) var c
    let title: String
    var body: some View {
        Text(T(title)).font(.caption.weight(.semibold)).foregroundStyle(c.muted).textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
    }
}
struct Notice: View {
    @Environment(\.loom) var c
    let text: String
    var body: some View {
        Text(T(text)).font(.footnote).foregroundStyle(c.muted).frame(maxWidth: .infinity, alignment: .leading)
            .padding(12).background(c.tint.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .fixedSize(horizontal: false, vertical: true)
    }
}
struct EmptyState: View {
    @Environment(\.loom) var c
    let title: String
    let detail: String
    var symbol = "leaf"
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 30, weight: .ultraLight)).foregroundStyle(c.accent)
            Text(T(title)).font(.title3)
            Text(T(detail)).font(.footnote).foregroundStyle(c.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 24)
    }
}
/// Sub-pages scroll; primary tabs lay themselves out to fit one screen instead.
struct PlainScene<Content: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing, content: content).padding(.horizontal, 20).padding(.vertical, 14)
        }.loomBackground()
    }
}

// MARK: - Slider

/// A textured slider. With `live`, dragging previews through that callback (throttled) and the
/// binding is written once on release; without it the binding is written continuously.
struct LoomSlider: View {
    @Environment(\.loom) var c
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var unit = "%"
    var live: ((Double) -> Void)? = nil
    var action: () -> Void = {}
    @State private var local = 0.0
    @State private var editing = false
    @State private var lastLive = Date.distantPast
    private var shown: Double { editing ? local : value }
    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        return span > 0 ? min(1, max(0, (shown - range.lowerBound) / span)) : 0
    }
    private var label: String { unit == "%" ? "\(Int((shown * 100).rounded()))%" : String(format: "%.1f %@", shown, unit) }
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(T(title)).font(.subheadline)
                Spacer()
                Text(label).font(.subheadline.monospacedDigit()).foregroundStyle(c.muted)
            }
            GeometryReader { g in
                let thumb: CGFloat = 26
                let usable = max(1, g.size.width - thumb)
                let x = usable * fraction
                ZStack(alignment: .leading) {
                    Capsule().fill(c.line).frame(height: 5)
                    Capsule().fill(
                        LinearGradient(colors: [c.accent.opacity(0.7), c.accent], startPoint: .leading, endPoint: .trailing)
                    ).frame(width: x + thumb / 2, height: 5)
                    Circle().fill(c.surface)
                        .overlay(Circle().strokeBorder(c.accent, lineWidth: 1.2))
                        .overlay(Circle().fill(c.accent).frame(width: 8, height: 8))
                        .frame(width: thumb, height: thumb)
                        .shadow(color: Color.black.opacity(0.14), radius: 4, y: 2)
                        .offset(x: x)
                }
                .frame(height: 36)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            if !editing { editing = true }
                            let f = min(1, max(0, (drag.location.x - thumb / 2) / usable))
                            set(range.lowerBound + f * (range.upperBound - range.lowerBound))
                        }
                        .onEnded { _ in finish() })
            }.frame(height: 36)
        }
        .onAppear { local = value }
        .onChange(of: value) { _, v in if !editing { local = v } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(T(title))
        .accessibilityValue(label)
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 20
            let next = min(range.upperBound, max(range.lowerBound, value + (direction == .increment ? step : -step)))
            value = next
            local = next
            action()
        }
    }
    private func set(_ v: Double) {
        local = v
        guard let live else {
            value = v
            return
        }
        let now = Date()
        if now.timeIntervalSince(lastLive) >= 0.12 {
            lastLive = now
            live(v)
        }
    }
    private func finish() {
        editing = false
        if value != local { value = local }
        action()
    }
}

// MARK: - Art

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

/// Theme artwork drawn as vector paths: a mandala, an orb, paisley or a moon over ripples.
/// `level` breathes the drawing with the haptic output; reduced motion keeps it still.
struct LoomArt: View {
    @Environment(\.loom) var c
    @Environment(\.accessibilityReduceMotion) var systemReduce
    @Environment(\.reducedArt) var customReduce
    var style = "flower"
    var level = 0.0
    private var breath: Double { systemReduce || customReduce ? 0 : min(1, max(0, level)) }
    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 * (1 + breath * 0.05)
            drawGlow(&context, center: center, radius: radius)
            switch style {
            case "orb", "moon": drawOrb(&context, center: center, radius: radius)
            case "leaves": drawPaisley(&context, center: center, radius: radius)
            case "lake": drawMoon(&context, center: center, radius: radius)
            default: drawMandala(&context, center: center, radius: radius)
            }
        }
        .accessibilityHidden(true)
    }
    private func drawGlow(_ g: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let rect = CGRect(x: center.x - radius * 1.25, y: center.y - radius * 1.25, width: radius * 2.5, height: radius * 2.5)
        g.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                Gradient(colors: [c.hero2.opacity(0.45 + breath * 0.2), c.hero2.opacity(0)]), center: center,
                startRadius: radius * 0.1, endRadius: radius * 1.25))
    }
    private func petal(center: CGPoint, angle: Double, inner: CGFloat, outer: CGFloat, width: CGFloat) -> Path {
        var p = Path()
        let dir = CGPoint(x: cos(angle), y: sin(angle))
        let side = CGPoint(x: -dir.y, y: dir.x)
        let base = CGPoint(x: center.x + dir.x * inner, y: center.y + dir.y * inner)
        let tip = CGPoint(x: center.x + dir.x * outer, y: center.y + dir.y * outer)
        let mid = (inner + outer) / 2
        let c1 = CGPoint(x: center.x + dir.x * mid + side.x * width, y: center.y + dir.y * mid + side.y * width)
        let c2 = CGPoint(x: center.x + dir.x * mid - side.x * width, y: center.y + dir.y * mid - side.y * width)
        p.move(to: base)
        p.addQuadCurve(to: tip, control: c1)
        p.addQuadCurve(to: base, control: c2)
        return p
    }
    private func drawMandala(_ g: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let rings: [(count: Int, inner: CGFloat, outer: CGFloat, width: CGFloat, color: Color, opacity: Double)] = [
            (16, 0.62, 0.98, 0.09, c.hero3, 0.35),
            (12, 0.40, 0.78, 0.12, c.hero2, 0.6),
            (8, 0.18, 0.52, 0.14, c.hero1, 0.85),
        ]
        for (i, ring) in rings.enumerated() {
            let offset = Double(i) * .pi / Double(ring.count)
            for k in 0..<ring.count {
                let a = Double(k) / Double(ring.count) * 2 * .pi + offset
                let path = petal(center: center, angle: a, inner: radius * ring.inner, outer: radius * ring.outer, width: radius * ring.width)
                g.fill(path, with: .linearGradient(
                    Gradient(colors: [ring.color.opacity(ring.opacity), c.hero3.opacity(ring.opacity * 0.4)]),
                    startPoint: center, endPoint: CGPoint(x: center.x + CGFloat(cos(a)) * radius, y: center.y + CGFloat(sin(a)) * radius)))
                g.stroke(path, with: .color(c.accent.opacity(0.35)), lineWidth: 0.6)
            }
        }
        let core = radius * 0.17
        g.fill(Path(ellipseIn: CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2)), with: .color(c.surface.opacity(0.92)))
        g.stroke(Path(ellipseIn: CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2)), with: .color(c.accent.opacity(0.6)), lineWidth: 0.8)
        var dots = Path()
        for k in 0..<8 {
            let a = Double(k) / 8 * 2 * .pi
            let p = CGPoint(x: center.x + CGFloat(cos(a)) * core * 0.55, y: center.y + CGFloat(sin(a)) * core * 0.55)
            dots.addEllipse(in: CGRect(x: p.x - 1.4, y: p.y - 1.4, width: 2.8, height: 2.8))
        }
        g.fill(dots, with: .color(c.accent.opacity(0.7)))
    }
    private func drawOrb(_ g: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        for i in 0..<6 {
            let f = 0.38 + Double(i) * 0.12
            let w = radius * f * 2, h = radius * f * 1.5
            var ellipse = Path(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
            ellipse = ellipse.applying(CGAffineTransform(rotationAngle: Double(i) * 0.26 - 0.6).concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
            g.stroke(ellipse, with: .color(c.hero3.opacity(0.22 + Double(i) * 0.1)), lineWidth: 0.8)
        }
        let r = radius * 0.3
        g.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .radialGradient(
            Gradient(colors: [c.hero1.opacity(0.95), c.hero2.opacity(0.4)]), center: CGPoint(x: center.x - r * 0.3, y: center.y - r * 0.35), startRadius: 0, endRadius: r * 1.2))
        g.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(c.accent.opacity(0.5)), lineWidth: 0.7)
    }
    private func boteh(center: CGPoint, angle: Double, length: CGFloat) -> Path {
        var p = Path()
        let dir = CGPoint(x: cos(angle), y: sin(angle))
        let side = CGPoint(x: -dir.y, y: dir.x)
        func pt(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
            CGPoint(x: center.x + dir.x * along + side.x * across, y: center.y + dir.y * along + side.y * across)
        }
        p.move(to: pt(0, 0))
        p.addCurve(to: pt(length, length * 0.12), control1: pt(length * 0.15, length * 0.45), control2: pt(length * 0.9, length * 0.5))
        p.addCurve(to: pt(length * 0.82, -length * 0.08), control1: pt(length * 1.08, -length * 0.05), control2: pt(length * 0.95, -length * 0.12))
        p.addCurve(to: pt(0, 0), control1: pt(length * 0.6, -length * 0.38), control2: pt(length * 0.15, -length * 0.4))
        return p
    }
    private func drawPaisley(_ g: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        for k in 0..<6 {
            let a = Double(k) / 6 * 2 * .pi - .pi / 2
            let path = boteh(center: center, angle: a, length: radius * 0.92)
            g.fill(path, with: .linearGradient(Gradient(colors: [c.hero1.opacity(0.85), c.hero2.opacity(0.35)]), startPoint: center, endPoint: CGPoint(x: center.x + CGFloat(cos(a)) * radius, y: center.y + CGFloat(sin(a)) * radius)))
            g.stroke(path, with: .color(c.accent.opacity(0.45)), lineWidth: 0.7)
            let innerPath = boteh(center: center, angle: a, length: radius * 0.55)
            g.stroke(innerPath, with: .color(c.accent.opacity(0.3)), lineWidth: 0.5)
        }
        let core = radius * 0.12
        g.fill(Path(ellipseIn: CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2)), with: .color(c.surface.opacity(0.9)))
        g.stroke(Path(ellipseIn: CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2)), with: .color(c.accent.opacity(0.6)), lineWidth: 0.8)
    }
    private func drawMoon(_ g: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        for i in 1...5 {
            let r = radius * (0.45 + CGFloat(i) * 0.11)
            var arc = Path()
            arc.addArc(center: CGPoint(x: center.x, y: center.y + radius * 0.25), radius: r, startAngle: .degrees(196), endAngle: .degrees(344), clockwise: false)
            g.stroke(arc, with: .color(c.hero3.opacity(0.55 - Double(i) * 0.08)), lineWidth: 0.8)
        }
        let r = radius * 0.34
        let moonCenter = CGPoint(x: center.x, y: center.y - radius * 0.18)
        var moon = Path(ellipseIn: CGRect(x: moonCenter.x - r, y: moonCenter.y - r, width: r * 2, height: r * 2))
        let bite = Path(ellipseIn: CGRect(x: moonCenter.x - r * 0.45, y: moonCenter.y - r * 1.05, width: r * 2, height: r * 2))
        moon = moon.subtracting(bite)
        g.fill(moon, with: .linearGradient(Gradient(colors: [c.hero1, c.hero2.opacity(0.6)]), startPoint: CGPoint(x: moonCenter.x - r, y: moonCenter.y - r), endPoint: CGPoint(x: moonCenter.x + r, y: moonCenter.y + r)))
        g.stroke(moon, with: .color(c.accent.opacity(0.5)), lineWidth: 0.7)
    }
}
typealias TactileArt = LoomArt

struct PatternWave: View {
    @Environment(\.loom) var c
    let pattern: HapticPattern
    var body: some View {
        GeometryReader { g in
            let samples = 160
            let seconds = pattern.durationMS / 1000
            let line = Path { p in
                for i in 0..<samples {
                    let x = Double(i) / Double(samples - 1)
                    let y = PatternMath.level(pattern, at: x * seconds)
                    let q = CGPoint(x: x * g.size.width, y: (1 - y) * (g.size.height - 10) + 5)
                    if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
                }
            }
            ZStack {
                line.fill(LinearGradient(colors: [c.accent.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom))
                line.stroke(c.accent, style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
            }
        }.frame(height: 48).accessibilityLabel(T("pattern.wave"))
    }
}
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
