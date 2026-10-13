import CoreHaptics
import Foundation
import GameController

/// Plays a fixed sequence of maximum-strength bursts on a game controller so the owner can tell
/// which locality / frequency combination feels strongest on that hardware. Each step uses a fresh
/// engine and a basic pattern player (controllers reject advanced players).
@MainActor final class ControllerProbe: ObservableObject {
    struct Step: Identifiable {
        let id: Int
        let title: String
        let locality: GCHapticsLocality
        let sharpness: Float
        let transient: Bool
    }
    static let steps: [Step] = [
        Step(id: 1, title: "默认位 · 低频 0.0", locality: .default, sharpness: 0, transient: false),
        Step(id: 2, title: "默认位 · 中频 0.5", locality: .default, sharpness: 0.5, transient: false),
        Step(id: 3, title: "默认位 · 高频 1.0", locality: .default, sharpness: 1, transient: false),
        Step(id: 4, title: "全部马达 · 低频 0.0", locality: .all, sharpness: 0, transient: false),
        Step(id: 5, title: "双握把 · 低频 0.0", locality: .handles, sharpness: 0, transient: false),
        Step(id: 6, title: "默认位 · 连打 10 下/秒", locality: .default, sharpness: 0, transient: true),
        Step(id: 7, title: "扳机马达 · 低频 0.0", locality: .triggers, sharpness: 0, transient: false),
        Step(id: 8, title: "全部马达含扳机 · 中低频 0.3", locality: .all, sharpness: 0.3, transient: false),
    ]
    /// Trigger-motor sweep: frequency, each trigger alone, bursts, and triggers mixed with handles.
    static let triggerSteps: [Step] = [
        Step(id: 1, title: "扳机 · 频率 0.0", locality: .triggers, sharpness: 0, transient: false),
        Step(id: 2, title: "扳机 · 频率 0.25", locality: .triggers, sharpness: 0.25, transient: false),
        Step(id: 3, title: "扳机 · 频率 0.5", locality: .triggers, sharpness: 0.5, transient: false),
        Step(id: 4, title: "扳机 · 频率 0.75", locality: .triggers, sharpness: 0.75, transient: false),
        Step(id: 5, title: "扳机 · 频率 1.0", locality: .triggers, sharpness: 1, transient: false),
        Step(id: 6, title: "左扳机 · 频率 0.0", locality: .leftTrigger, sharpness: 0, transient: false),
        Step(id: 7, title: "右扳机 · 频率 0.0", locality: .rightTrigger, sharpness: 0, transient: false),
        Step(id: 8, title: "扳机 · 连打 10 下/秒", locality: .triggers, sharpness: 0, transient: true),
        Step(id: 9, title: "扳机 + 握把 · 频率 0.0", locality: .all, sharpness: 0, transient: false),
    ]
    @Published private(set) var current: Step?
    @Published private(set) var total = 0
    @Published private(set) var running = false
    @Published private(set) var log: [String] = []
    private var engine: CHHapticEngine?
    private var task: Task<Void, Never>?

    func run(on controller: GCController, steps: [Step] = ControllerProbe.steps) {
        guard !running else { return }
        running = true
        total = steps.count
        log = []
        task = Task { [weak self] in
            guard let self else { return }
            for step in steps {
                guard !Task.isCancelled else { break }
                self.current = step
                self.play(step, on: controller)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self.teardown()
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
            self.current = nil
            self.running = false
        }
    }
    func cancel() {
        task?.cancel()
        teardown()
        current = nil
        running = false
    }
    private func play(_ step: Step, on controller: GCController) {
        teardown()
        guard let haptics = controller.haptics else { note("\(step.id): no haptics"); return }
        note("localities: \(haptics.supportedLocalities.map { "\($0.rawValue)" }.sorted())")
        guard haptics.supportedLocalities.contains(step.locality) else { note("\(step.id): locality unsupported"); return }
        guard let e = haptics.createEngine(withLocality: step.locality) else { note("\(step.id): engine nil"); return }
        engine = e
        do {
            try e.start()
            let events: [CHHapticEvent]
            if step.transient {
                events = stride(from: 0.0, to: 1.5, by: 0.1).map {
                    CHHapticEvent(eventType: .hapticTransient, parameters: [
                        .init(parameterID: .hapticIntensity, value: 1), .init(parameterID: .hapticSharpness, value: step.sharpness),
                    ], relativeTime: $0)
                }
            } else {
                events = [CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    .init(parameterID: .hapticIntensity, value: 1), .init(parameterID: .hapticSharpness, value: step.sharpness),
                ], relativeTime: 0, duration: 1.5)]
            }
            let player = try e.makePlayer(with: CHHapticPattern(events: events, parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
            note("\(step.id): playing \(step.title)")
        } catch {
            let n = error as NSError
            note("\(step.id): FAILED \(n.domain) \(n.code) \(n.localizedDescription)")
        }
    }
    private func teardown() {
        engine?.stop(completionHandler: { _ in })
        engine = nil
    }
    private func note(_ s: String) {
        log.append(s)
        DiagLog.write("probe " + s)
    }
}
