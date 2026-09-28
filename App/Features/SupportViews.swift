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
                if app.purchase.outcome != .idle { Notice(text: outcomeText) }
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
struct TroubleshootingView: View {
    @EnvironmentObject var app: AppModel
    @State private var felt = false
    var body: some View {
        PlainScene {
            Label(
                T(app.playback.driver.supported ? "help.supported" : "error.hapticsUnavailable"),
                systemImage: app.playback.driver.supported ? "checkmark.circle" : "exclamationmark.circle")
            Notice(text: "help.testHelp")
            LoomButton(title: "help.test", symbol: "hand.tap") {
                app.perform {
                    let parts = [0.2, 0.4, 0.6].map {
                        Segment(duration: 500, gap: 500, gain: $0, sharp: 0.25)
                    }
                    var p = HapticPattern(name: T("help.test"), segments: parts)
                    p.loop = false
                    try app.playback.begin(p, duration: 3, gain: 1, kind: "test")
                }
            }.disabled(!app.playback.driver.supported)
            HStack {
                LoomButton(title: "help.felt", secondary: true) { felt = true }
                LoomButton(title: "common.stop", secondary: true) { app.stopAll() }
            }
            if felt { Notice(text: "help.confirmed") }
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
                                app.error = error.localizedDescription
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
