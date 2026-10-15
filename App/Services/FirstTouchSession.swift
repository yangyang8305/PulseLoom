import Combine
import Foundation
import PulseLoomCore

/// A successful engine submission is not a comfort measurement: only the user confirms the level.
@MainActor final class FirstTouchSession: ObservableObject {
    enum Stage { case ready, playing, feedback, saved }
    @Published private(set) var stage: Stage = .ready
    @Published private(set) var gain: Double
    @Published private(set) var message: String?
    let app: AppModel
    private var outputID: UUID?
    init(app: AppModel) {
        self.app = app
        // Re-enter gently even if the previously confirmed output level was high.
        gain = min(0.25, app.prefs.firstTouchGain ?? 0.25)
    }
    var availabilityError: String? {
        do {
            _ = try HapticRoutePolicy.choose(app.playback.outputs.controllers.choice,
                devices: app.playback.outputs.controllers.devices, phoneSupported: app.playback.driver.supported)
            return nil
        } catch { return UserFacingError.message(error) }
    }
    func start() {
        guard stage != .playing else { return }
        message = nil
        stage = .ready
        do {
            let p = HapticPattern(name: T("touch.title"), segments: [
                Segment(duration: 180, gap: 180, gain: 1, sharp: 0.5),
                Segment(duration: 400, gap: 0, gain: 1, sharp: 0.5)
            ], loop: false)
            try app.playback.begin(p, duration: 0.76, gain: gain, kind: "first_touch")
            outputID = app.playback.outputID
            stage = .playing
        } catch { outputID = nil; message = UserFacingError.message(error, fallback: "error.outputStart") }
    }
    func playbackChanged() {
        guard stage == .playing || stage == .feedback, let outputID else { return }
        guard outputID == app.playback.outputID else {
            self.outputID = nil; stage = .ready; message = T("touch.interrupted"); return
        }
        switch app.playback.state {
        case .completed: stage = .feedback
        case .failed, .interrupted, .paused, .idle:
            stage = .ready
            message = app.playback.lastError.map { UserFacingError.message(LoomError.unavailable($0)) } ?? T("touch.interrupted")
        default: break
        }
    }
    func adjust(stronger: Bool) {
        guard stage == .feedback else { return }
        let old = gain
        gain = (min(1, max(0.1, gain + (stronger ? 0.2 : -0.2))) * 100).rounded() / 100
        stage = .ready
        message = old == gain ? T(stronger ? "touch.ceiling" : "touch.minimum") : T("touch.retest")
    }
    func save() {
        guard stage == .feedback, outputID == app.playback.outputID, app.playback.state == .completed else { return }
        do {
            try app.library.preferences {
                $0.gain = gain
                $0.firstTouchGain = gain
                $0.onboarded = true
            }
            stage = .saved
            cancelOutput()
        } catch { message = UserFacingError.message(error) }
    }
    func stopByUser() {
        app.stopAll()
        stop()
    }
    func stop() {
        let hadTest = stage == .playing || stage == .feedback
        cancelOutput()
        if hadTest { stage = .ready; message = T("touch.interrupted") }
    }
    private func cancelOutput() {
        if let outputID, outputID == app.playback.outputID { app.playback.stop() }
        outputID = nil
    }
}
