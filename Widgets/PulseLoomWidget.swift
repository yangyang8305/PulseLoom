import SwiftUI
import WidgetKit

struct LoomEntry: TimelineEntry {
    let date: Date
    let title: String
    let patternID: String
    let dark: Bool
}
struct LoomProvider: TimelineProvider {
    func placeholder(in context: Context) -> LoomEntry {
        LoomEntry(date: Date(), title: "Pulse Loom", patternID: "p02", dark: false)
    }
    func getSnapshot(in context: Context, completion: @escaping (LoomEntry) -> Void) { completion(entry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LoomEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(3600))))
    }
    private func entry() -> LoomEntry {
        let group = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? ""
        let d = UserDefaults(suiteName: group)
        let id = d?.string(forKey: "patternID") ?? "p02"
        return LoomEntry(
            date: Date(),
            title: d?.string(forKey: "title") ?? NSLocalizedString("widget.privateTitle", comment: ""),
            patternID: id, dark: d?.string(forKey: "theme") == "night")
    }
}
struct LoomWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: LoomEntry
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
        }.containerBackground(for: .widget) {
            entry.dark ? Color(red: 0.10, green: 0.09, blue: 0.14) : Color(red: 0.97, green: 0.93, blue: 0.93)
        }.widgetURL(URL(string: "pulseloom://pattern/" + entry.patternID))
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
