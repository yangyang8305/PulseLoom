import SwiftUI
import WidgetKit

struct LoomEntry: TimelineEntry {
    let date: Date
    let title: String
    let patternID: String
    let light: [String]
    let dark: [String]
}
struct LoomProvider: TimelineProvider {
    func placeholder(in context: Context) -> LoomEntry {
        LoomEntry(date: Date(), title: "Pulse Loom", patternID: "p02",
                  light: ["#fcf7f3", "#423238", "#966879"], dark: ["#15151a", "#f1eef7", "#d6a9bd"])
    }
    func getSnapshot(in context: Context, completion: @escaping (LoomEntry) -> Void) { completion(entry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LoomEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(3600))))
    }
    private func entry() -> LoomEntry {
        let group = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? ""
        let d = group.isEmpty ? nil : UserDefaults(suiteName: group)
        let requested = d?.string(forKey: "patternID") ?? "p02"
        let id = requested.range(of: "^p(0[1-9]|1[0-6])$", options: .regularExpression) != nil ? requested : "p02"
        let palettes = d?.dictionary(forKey: "widgetPalette")
        let light = palettes?["light"] as? [String] ?? []
        let dark = palettes?["dark"] as? [String] ?? []
        return LoomEntry(
            date: Date(),
            title: d?.string(forKey: "title") ?? NSLocalizedString("widget.privateTitle", comment: ""),
            patternID: id,
            light: light.count == 3 ? light : ["#fcf7f3", "#423238", "#966879"],
            dark: dark.count == 3 ? dark : ["#15151a", "#f1eef7", "#d6a9bd"])
    }
}
private func widgetColor(_ hex: String) -> Color {
    let number = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
    return Color(.sRGB, red: Double((number >> 16) & 255) / 255,
                 green: Double((number >> 8) & 255) / 255,
                 blue: Double(number & 255) / 255, opacity: 1)
}
struct LoomWidgetView: View {
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var colorScheme
    let entry: LoomEntry
    // Explicit light/dark overrides are already resolved in the published pair.
    // No theme-name heuristic: switching system appearance can render immediately.
    private var colors: [String] { colorScheme == .dark ? entry.dark : entry.light }
    private var accessory: Bool { family == .accessoryCircular || family == .accessoryRectangular }
    var body: some View {
        Group {
            if family == .accessoryCircular {
                Image(systemName: "hand.tap").font(.title2)
            } else if family == .accessoryRectangular {
                VStack(alignment: .leading) {
                    Text("Pulse Loom").font(.headline)
                    Text(entry.title).font(.caption)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pulse Loom").font(.system(.headline, design: .serif).italic())
                    Spacer(minLength: 0)
                    Text(entry.title).font(.title3).lineLimit(2)
                    Label("widget.opensApp", systemImage: "hand.tap").font(.caption)
                }.padding(3)
            }
        }
        // Lock-screen accessories use the system's monochrome rendering semantics.
        .foregroundStyle(accessory ? AnyShapeStyle(.primary) : AnyShapeStyle(widgetColor(colors[1])))
        .tint(widgetColor(colors[2]))
        .containerBackground(for: .widget) { widgetColor(colors[0]) }
        .widgetURL(URL(string: "pulseloom://pattern/" + entry.patternID))
    }
}
@main struct PulseLoomWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PulseLoomQuickPattern", provider: LoomProvider()) {
            LoomWidgetView(entry: $0)
        }.configurationDisplayName("widget.title").description("widget.opensApp").supportedFamilies([
            .systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular,
        ])
    }
}
