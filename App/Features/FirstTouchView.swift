import SwiftUI

struct FirstTouchView: View {
    @ObservedObject var app: AppModel
    @StateObject private var session: FirstTouchSession
    @Environment(\.loom) private var colors
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    init(app: AppModel) {
        self.app = app
        _session = StateObject(wrappedValue: FirstTouchSession(app: app))
    }
    var body: some View {
        PlainScene(spacing: 16) {
            Text(T("touch.intro")).font(.body)
            LoomCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label(T("touch.device"), systemImage: "iphone.radiowaves.left.and.right")
                        .font(.headline)
                    Text(app.playback.outputs.selectedName).accessibilityIdentifier("firstTouchDevice")
                    if let error = session.availabilityError {
                        Text(error).accessibilityIdentifier("firstTouchUnavailable")
                    } else {
                        Text(T("touch.capability")).font(.footnote)
                    }
                    NavigationLink { HapticOutputsView() } label: {
                        HStack {
                            Text(T("touch.checkDevice")).font(.body.weight(.semibold))
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").accessibilityHidden(true)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.foregroundStyle(colors.accent).accessibilityIdentifier("firstTouchCheckDevice")
                }
            }
            if session.stage == .saved {
                Notice(text: "touch.saved")
                LoomButton(title: "common.done", multiline: true) { dismiss() }.accessibilityIdentifier("firstTouchDone")
            } else {
                Text(String(format: T("touch.level"), Int((session.gain * 100).rounded())))
                    .font(.title2).accessibilityIdentifier("firstTouchLevel")
                Text(T("touch.shortTest")).font(.footnote)
                LoomButton(title: session.stage == .playing ? "touch.playing" : "touch.play", symbol: "hand.tap", multiline: true) {
                    session.start()
                }.disabled(session.stage == .playing || session.availabilityError != nil)
                    .opacity(session.stage == .playing || session.availabilityError != nil ? 0.45 : 1)
                    .accessibilityIdentifier("firstTouchPlay")
                if session.stage == .feedback {
                    Text(T("touch.question")).font(.headline)
                    LoomButton(title: "touch.comfortable", symbol: "checkmark", multiline: true) { session.save() }
                        .accessibilityIdentifier("firstTouchComfortable")
                    LoomButton(title: session.gain >= 1 ? "touch.notFeltMaximum" : "touch.notFelt", secondary: true, multiline: true) { session.adjust(stronger: true) }
                        .accessibilityIdentifier("firstTouchNotFelt")
                    LoomButton(title: session.gain <= 0.1 ? "touch.tooStrongMinimum" : "touch.tooStrong", secondary: true, multiline: true) { session.adjust(stronger: false) }
                        .accessibilityIdentifier("firstTouchTooStrong")
                }
                if let message = session.message { Text(message).accessibilityIdentifier("firstTouchMessage") }
                NavigationLink { TroubleshootingView() } label: { Text(T("help.troubleshoot")) }
                Text(T("help.settings")).font(.footnote)
                Text(T("touch.scope")).font(.footnote)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if session.stage != .saved {
                LoomButton(title: "common.stop", symbol: "stop.fill", secondary: true, multiline: true) {
                    session.stopByUser()
                }.accessibilityIdentifier("firstTouchStop")
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(colors.background)
            }
        }
        .navigationTitle(T("touch.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: app.playback.state) { _, _ in session.playbackChanged() }
        .onChange(of: app.playback.outputID) { _, _ in session.playbackChanged() }
        .onChange(of: phase) { _, phase in if phase != .active { session.stop() } }
        .onDisappear { session.stop() }
    }
}
