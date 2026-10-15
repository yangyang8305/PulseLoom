import PulseLoomCore
import SwiftUI
import UIKit

struct PremiumView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            PlainScene {
                TactileArt().frame(height: 125)
                Text("Pulse Loom Pro").font(.system(.largeTitle, design: .serif))
                Text(T("purchase.subtitle"))
                ForEach(
                    [
                        "purchase.patterns", "purchase.music", "purchase.create", "purchase.themes",
                        "purchase.extra",
                    ], id: \.self
                ) { k in Label(T(k), systemImage: "checkmark").font(.subheadline) }
                if app.pro {
                    Notice(text: "purchase.active")
                } else if let p = app.purchase.product {
                    LoomCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(p.displayPrice).font(.largeTitle)
                            Text(T("purchase.once")).font(.footnote)
                        }
                    }
                    LoomButton(title: "purchase.buy") {
                        app.stopAll()
                        Task { await app.purchase.buy() }
                    }.disabled(!app.purchase.canPurchase)
                } else {
                    if app.purchase.loading {
                        ProgressView()
                    } else {
                        Notice(text: "purchase.unavailable")
                        LoomButton(title: "common.retry", secondary: true) {
                            Task { await app.purchase.load() }
                        }
                    }
                }
                if app.purchase.outcome != .idle,
                    !(app.purchase.product == nil && app.purchase.outcome == .failed(T("purchase.unavailable"))) {
                    Notice(text: outcomeText)
                }
                LoomButton(title: "purchase.restore", secondary: true) {
                    app.stopAll()
                    Task { await app.purchase.restore() }
                }
                Button(T("common.continue")) { dismiss() }.frame(minHeight: 44)
                NavigationLink {
                    PrivacyView()
                } label: {
                    Text(T("privacy.title")).frame(minHeight: 44)
                }
                if let u = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                    Link(T("purchase.terms"), destination: u)
                }
            }.navigationTitle(T("purchase.title")).navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(T("common.close")) { dismiss() } }
            }
        }
    }
    var outcomeText: String {
        switch app.purchase.outcome {
        case .idle: return ""
        case .purchasing: return "purchase.processing"
        case .success: return "purchase.success"
        case .cancelled: return "purchase.cancelled"
        case .pending: return "purchase.pending"
        case .restored: return "purchase.restored"
        case .none: return "purchase.none"
        case .failed(let s): return s
        }
    }
}
/// Every event at 1.0 so the user feels this device's real ceiling, independent of presets and sliders.
enum HapticReference {
    static func pattern() -> HapticPattern {
        var p = HapticPattern(
            name: T("help.reference"),
            segments: [
                Segment(duration: 30, gap: 220, gain: 1, sharp: 1, type: .transient),
                Segment(duration: 30, gap: 220, gain: 1, sharp: 1, type: .transient),
                Segment(duration: 30, gap: 470, gain: 1, sharp: 1, type: .transient),
                Segment(duration: 1000, gap: 500, gain: 1, sharp: 0),
                Segment(duration: 1000, gap: 0, gain: 1, sharp: 1),
            ])
        p.loop = false
        return p
    }
}
struct TroubleshootingView: View {
    @EnvironmentObject var app: AppModel
    @State private var felt = false
    @StateObject private var probe = ControllerProbe()
    var body: some View {
        PlainScene {
            if let controller = app.playback.outputs.controllers.firstHapticController {
                LoomCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("手柄极限测试 · " + (controller.vendorName ?? "Controller")).font(.headline)
                        Text("每种 1.5 秒，全部满强度。记下哪一个最强。").font(.caption).foregroundStyle(.secondary)
                        if let step = probe.current {
                            Text("正在播放 \(step.id) / \(probe.total)：\(step.title)").font(.body.weight(.semibold))
                        }
                        HStack(spacing: 8) {
                            LoomButton(title: probe.running ? "common.stop" : "help.probe", symbol: "gamecontroller", compact: true) {
                                if probe.running { probe.cancel() } else { app.stopAll(); probe.run(on: controller) }
                            }
                            LoomButton(title: "help.probeTriggers", symbol: "arrow.down.to.line", secondary: true, compact: true) {
                                app.stopAll(); probe.cancel(); probe.run(on: controller, steps: ControllerProbe.triggerSteps)
                            }
                        }
                        Text("综合 8 项：").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(ControllerProbe.steps) { s in Text("\(s.id). \(s.title)").font(.caption).foregroundStyle(.secondary) }
                        Text("扳机 9 项：").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(ControllerProbe.triggerSteps) { s in Text("\(s.id). \(s.title)").font(.caption).foregroundStyle(.secondary) }
                        ForEach(probe.log, id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
            Label(
                T(app.playback.driver.supported ? "help.supported" : "error.hapticsUnavailable"),
                systemImage: app.playback.driver.supported ? "checkmark.circle" : "exclamationmark.circle")
            Notice(text: "help.referenceHelp")
            LoomButton(title: "help.reference", symbol: "bolt") {
                app.perform {
                    try app.playback.begin(
                        HapticReference.pattern(), duration: 4, gain: 1, speed: 1, sharp: 0.5, kind: "test")
                }
            }.disabled(!app.playback.outputs.supported).accessibilityIdentifier("referenceTest")
            Notice(text: "help.testHelp")
            LoomButton(title: "help.test", symbol: "hand.tap") {
                app.perform {
                    let parts = [0.4, 0.7, 1.0].map {
                        Segment(duration: 500, gap: 500, gain: $0, sharp: 0.5)
                    }
                    var p = HapticPattern(name: T("help.test"), segments: parts)
                    p.loop = false
                    try app.playback.begin(p, duration: 3, gain: 1, speed: 1, sharp: 0.5, kind: "test")
                }
            }.disabled(!app.playback.driver.supported)
            Text(T("help.testLevels")).font(.caption).foregroundStyle(.secondary)
            HStack {
                LoomButton(title: "help.felt", secondary: true) { felt = true }
                LoomButton(title: "common.stop", secondary: true) { app.stopAll() }
            }
            if felt { Notice(text: "help.confirmed") }
            Text(dispatchText).font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("lastDispatch")
            ForEach(
                ["help.settings", "help.case", "help.foreground", "help.temperature", "help.noBoost"],
                id: \.self
            ) { k in Notice(text: k) }
            if let e = app.playback.lastError { Notice(text: e) }
            Button(T("common.openSettings")) {
                if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
            }.frame(minHeight: 44)
        }.navigationTitle(T("help.troubleshoot"))
    }
    private var dispatchText: String {
        guard let d = app.playback.lastDispatch else { return T("help.dispatchNone") }
        let detail = String(
            format: T("help.dispatchFormat"), d.target, "\(d.events)",
            String(format: "%.2f", d.peakIntensity), String(format: "%.2f", d.sharpness))
        return String(format: T("help.lastDispatch"), detail)
    }
}
struct HelpView: View {
    var body: some View {
        PlainScene {
            ForEach(["home", "music", "create", "background", "backup", "remote", "privacy"], id: \.self) {
                k in
                DisclosureGroup(T("help.q." + k)) {
                    Text(T("help.a." + k)).font(.subheadline).padding(.vertical, 10)
                }
            }
            Notice(text: "help.notMedical")
        }.navigationTitle(T("help.title"))
    }
}
struct FeedbackView: View {
    @EnvironmentObject var app: AppModel
    @State private var text = ""
    var body: some View {
        PlainScene {
            TextEditor(text: $text).frame(minHeight: 150).overlay(
                RoundedRectangle(cornerRadius: 12).stroke(.secondary.opacity(0.3)))
            LoomButton(title: "feedback.save") {
                app.perform {
                    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !clean.isEmpty, clean.count <= 2000, app.library.snapshot.notes.count < 500 else {
                        throw LoomError.invalid(T("feedback.limit"))
                    }
                    try app.library.commit {
                        $0.notes.append(FeedbackNote(text: clean, screen: String(describing: app.tab)))
                    }
                    text = ""
                }
            }
            ForEach(app.library.snapshot.notes) { note in
                LoomCard {
                    HStack {
                        Text(note.text).font(.subheadline)
                        Spacer()
                        Button {
                            app.perform { try app.library.commit { $0.notes.removeAll { $0.id == note.id } } }
                        } label: {
                            Image(systemName: "trash").frame(width: 44, height: 44)
                        }
                    }
                }
            }
            LoomButton(title: "feedback.export", symbol: "square.and.arrow.up", secondary: true) {
                app.export(app.library.snapshot.notes, name: "PulseLoom-feedback")
            }
            if let support = Bundle.main.object(forInfoDictionaryKey: "SupportURL") as? String,
                let u = URL(string: support), u.scheme == "https"
            {
                Link(T("feedback.contact"), destination: u).frame(minHeight: 44)
            } else {
                Notice(text: "feedback.localOnly")
            }
        }.navigationTitle(T("feedback.title"))
    }
}
struct IconsView: View {
    @EnvironmentObject var app: AppModel
    var body: some View {
        PlainScene {
            ForEach(["default", "MistIcon", "NightIcon"], id: \.self) { name in
                Button {
                    guard UIApplication.shared.supportsAlternateIcons else {
                        app.error = T("icons.unavailable")
                        return
                    }
                    UIApplication.shared.setAlternateIconName(name == "default" ? nil : name) { error in
                        Task { @MainActor in
                            if let error {
                                app.error = UserFacingError.message(error)
                            } else {
                                app.perform { try app.library.preferences { $0.icon = name } }
                            }
                        }
                    }
                } label: {
                    LoomCard {
                        HStack {
                            Image(systemName: name == "NightIcon" ? "moon" : "leaf").font(.largeTitle)
                            Text(T("icons." + name))
                            Spacer()
                            if app.prefs.icon == name { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
            Notice(text: "icons.system")
        }.navigationTitle(T("icons.title"))
    }
}
