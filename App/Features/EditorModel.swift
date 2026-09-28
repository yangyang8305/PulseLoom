import PulseLoomCore
import SwiftUI
import UIKit

@MainActor final class EditorModel: ObservableObject {
    enum Tool: String, CaseIterable { case tap, basic, curve, xy }
    @Published var tool: Tool = .tap
    @Published var draft = HapticPattern()
    @Published var selected = 0
    @Published var zoom = 1
    @Published var recording = false
    @Published var down = false
    @Published var seconds = 0.0
    @Published var touches = 0
    @Published var x = 0.25
    @Published var y = 0.5
    @Published var saved = false
    @Published var error: String?
    private var history = EditHistory<HapticPattern>()
    private var recorder = TouchRecorder()
    private var xy: [(Double, Double, Double)] = []
    private var xyStart = 0.0
    private var timer: Timer?
    private weak var app: AppModel?
    private var checkpoint: HapticPattern?
    var canUndo: Bool { !history.undoStack.isEmpty }
    var canRedo: Bool { !history.redoStack.isEmpty }
    var validationError: String? {
        do {
            try Validation.pattern(draft, requireName: false)
            return nil
        } catch { return error.localizedDescription }
    }
    init() {}
    func attach(_ app: AppModel) {
        guard self.app == nil else { return }
        self.app = app
        if let d = app.library.draft {
            draft = d
            tool = d.mode == .curve ? .curve : d.mode == .recorded ? .tap : .basic
        }
    }
    func edit(_ p: HapticPattern, copy: Bool = false) {
        endTouch()
        end()
        history = EditHistory()
        draft = copy || p.builtin ? p.copyForEditing() : p
        tool = draft.mode == .curve ? .curve : .basic
        selected = 0
        saved = false
        persist()
    }
    func choose(_ t: Tool) {
        endTouch()
        end()
        tool = t
        if t == .curve, draft.mode != .curve {
            remember()
            let duration = max(100, min(30000, draft.durationMS))
            let old = draft
            draft.mode = .curve
            draft.nodes = (0..<17).map { i in
                let ms = duration * Double(i) / 16
                return CurveNode(time: ms, value: PatternMath.level(old, at: ms / 1000))
            }
            draft.cycle = duration
            draft.segments = []
            persist()
        } else if t == .basic, draft.mode == .curve {
            remember()
            let old = draft
            let n = 16
            draft.mode = .basic
            draft.segments = (0..<n).map { i in
                Segment(
                    duration: old.cycle / Double(n), gap: 0,
                    gain: PatternMath.level(old, at: Double(i) * old.cycle / Double(n) / 1000),
                    sharp: old.sharpness)
            }
            draft.nodes = []
            persist()
        }
    }
    func new() {
        endTouch()
        end()
        history = EditHistory()
        draft = HapticPattern()
        tool = .tap
        selected = 0
        xy = []
        touches = 0
        seconds = 0
        saved = false
        persist()
    }
    func remember() {
        history.record(draft)
        saved = false
    }
    func change(_ action: (inout HapticPattern) -> Void) {
        remember()
        action(&draft)
        draft.updatedAt = Date()
        persist()
    }
    func beginEditingGesture() { if checkpoint == nil { checkpoint = draft } }
    func endEditingGesture() {
        if let checkpoint, checkpoint != draft {
            history.record(checkpoint)
            saved = false
        }
        checkpoint = nil
        persist()
    }
    func persist() { app?.library.saveDraft(draft) }
    func undo() {
        if let d = history.undo(draft) {
            draft = d
            selected = min(selected, max(0, draft.segments.count - 1))
            persist()
        }
    }
    func redo() {
        if let d = history.redo(draft) {
            draft = d
            selected = min(selected, max(0, draft.segments.count - 1))
            persist()
        }
    }
    func addSegment() {
        guard draft.segments.count < (draft.mode == .recorded ? 128 : 16) else {
            error = T("editor.segmentLimit")
            return
        }
        change { $0.segments.append(Segment()) }
        selected = draft.segments.count - 1
    }
    func duplicate() {
        guard draft.segments.indices.contains(selected),
            draft.segments.count < (draft.mode == .recorded ? 128 : 16)
        else { return }
        var e = draft.segments[selected]
        e.id = UUID()
        change { $0.segments.insert(e, at: selected + 1) }
        selected += 1
    }
    func deleteSegment() {
        guard draft.segments.indices.contains(selected) else { return }
        change { $0.segments.remove(at: selected) }
        selected = max(0, selected - 1)
    }
    func move(_ direction: Int) {
        let next = selected + direction
        guard draft.segments.indices.contains(next) else { return }
        change { $0.segments.swapAt(selected, next) }
        selected = next
    }
    func segmentBinding(_ key: WritableKeyPath<Segment, Double>) -> Binding<Double> {
        Binding(
            get: {
                self.draft.segments.indices.contains(self.selected)
                    ? self.draft.segments[self.selected][keyPath: key] : 0
            },
            set: { v in
                guard v.isFinite, self.draft.segments.indices.contains(self.selected) else { return }
                self.beginEditingGesture()
                self.draft.segments[self.selected][keyPath: key] = v
                self.persist()
            })
    }
    func nodeChanged(_ index: Int, time: Double, value: Double) {
        guard time.isFinite, value.isFinite, draft.nodes.indices.contains(index) else { return }
        beginEditingGesture()
        let left = index == 0 ? 0 : draft.nodes[index - 1].time + 1
        let right = index == draft.nodes.count - 1 ? draft.cycle : draft.nodes[index + 1].time - 1
        draft.nodes[index].time =
            index == 0 ? 0 : index == draft.nodes.count - 1 ? draft.cycle : min(right, max(left, time))
        draft.nodes[index].value = min(1, max(0, value))
        persist()
    }
    func applyCurveTemplate(_ name: String) {
        change { p in
            p.mode = .curve
            p.segments = []
            p.cycle = max(100, min(30000, p.cycle))
            p.nodes = (0...16).map { i in
                let x = Double(i) / 16
                let v =
                    name == "rise"
                    ? 0.15 + 0.65 * x
                    : name == "fall" ? 0.8 - 0.65 * x : 0.15 + 0.65 * pow(sin(Double.pi * x), 2)
                return CurveNode(time: x * p.cycle, value: v)
            }
        }
    }
    func addNode(time: Double? = nil) {
        guard draft.nodes.count < 64 else { return }
        change { p in
            let intervals = zip(p.nodes, p.nodes.dropFirst()).map { ($0.0.time, $0.1.time) }
            guard let biggest = intervals.max(by: { $0.1 - $0.0 < $1.1 - $1.0 }) else { return }
            let t = min(p.cycle - 1, max(1, time ?? (biggest.0 + biggest.1) / 2))
            guard !p.nodes.contains(where: { abs($0.time - t) < 1 }) else { return }
            let v = PatternMath.level(p, at: t / 1000)
            p.nodes.append(CurveNode(time: t, value: v))
            p.nodes.sort { $0.time < $1.time }
        }
    }
    func removeNode(_ id: UUID) {
        guard draft.nodes.first?.id != id, draft.nodes.last?.id != id else { return }
        change { $0.nodes.removeAll { $0.id == id } }
    }
    func length(_ seconds: Double) {
        guard (0.1...30).contains(seconds) else { return }
        change { p in
            let old = p.cycle
            p.cycle = seconds * 1000
            p.nodes = p.nodes.map {
                var n = $0
                n.time = n.time / old * p.cycle
                return n
            }
        }
    }
    func start() {
        guard !recording else { return }
        remember()
        saved = false
        seconds = 0
        touches = 0
        xy = []
        xyStart = ProcessInfo.processInfo.systemUptime
        recorder.start(now: xyStart)
        recording = true
        app?.stopAll()
        timer?.invalidate()
        timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    func touchBegan(_ point: CGPoint) {
        guard recording, !down else { return }
        down = true
        let now = ProcessInfo.processInfo.systemUptime
        if tool == .xy {
            x = point.x
            y = 1 - point.y
            xy.append((seconds, x, y))
        } else {
            _ = recorder.down(now: now, gain: 0.5, sharpness: 0.25)
        }
        sendLevel()
    }
    func touchMoved(_ point: CGPoint) {
        guard recording, down, tool == .xy else { return }
        x = point.x
        y = 1 - point.y
        sendLevel()
    }
    func endTouch() {
        guard down else { return }
        down = false
        recorder.up(now: ProcessInfo.processInfo.systemUptime)
        if tool == .xy { xy.append((seconds, x, 0)) }
        app?.playback.stopStream()
        touches = recorder.segments.count
    }
    private func sendLevel() {
        guard let app else { return }
        guard app.playback.driver.supported else { return }
        do {
            try app.playback.stream(
                tool == .xy ? y : 0.5, sharpness: tool == .xy ? x : 0.25, source: "recording")
        } catch {
            self.error = error.localizedDescription
            endTouch()
            end()
        }
    }
    private func tick() {
        guard recording else { return }
        let now = ProcessInfo.processInfo.systemUptime
        seconds = min(30, now - xyStart)
        recorder.tick(now: now)
        if tool == .xy, down, xy.last.map { seconds - $0.0 >= 0.25 } ?? true, xy.count < 128 {
            xy.append((seconds, x, y))
        }
        if tool != .xy, down, !recorder.isDown { endTouch() }
        touches = tool == .xy ? xy.count : recorder.segments.count
        if seconds >= 30 || touches >= 128 {
            endTouch()
            end()
        }
    }
    func end() {
        guard recording else { return }
        endTouch()
        recording = false
        timer?.invalidate()
        timer = nil
        recorder.finish(now: ProcessInfo.processInfo.systemUptime)
        do {
            if tool == .xy {
                guard !xy.isEmpty else { return }
                let points = xy
                var segments: [Segment] = []
                for i in points.indices {
                    let next = i + 1 < points.count ? points[i + 1].0 : max(points[i].0 + 0.05, seconds)
                    let dt = max(50, min(10000, (next - points[i].0) * 1000))
                    segments.append(Segment(duration: dt, gap: 0, gain: points[i].2, sharp: points[i].1))
                }
                var candidate = HapticPattern(
                    name: draft.name, mode: .recorded, segments: Array(segments.prefix(128)))
                candidate.id = draft.id
                try Validation.pattern(candidate, requireName: false)
                draft = candidate
            } else if !recorder.segments.isEmpty {
                var p = try recorder.pattern(name: draft.name)
                p.id = draft.id
                draft = p
            }
            persist()
        } catch { self.error = error.localizedDescription }
    }
    func removeLastTouch() {
        if recording {
            recorder.undo()
            touches = recorder.segments.count
        } else if !draft.segments.isEmpty {
            change { $0.segments.removeLast() }
        }
    }
    func save() {
        end()
        guard let app else { return }
        app.perform {
            var p = draft
            p.name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
            try app.library.save(p, pro: app.pro)
            draft = p
            saved = true
        }
    }
    func preview() {
        end()
        guard let app else { return }
        app.perform {
            try Validation.pattern(draft, requireName: false)
            var p = draft
            p.name = p.name.isEmpty ? T("editor.untitled") : p.name
            app.preview(p)
        }
    }
}

/// UIKit touch cancellation is explicit: a system gesture or removed view terminates output.
struct TouchSurface: UIViewRepresentable {
    let began: (CGPoint) -> Void
    let moved: (CGPoint) -> Void
    let ended: () -> Void
    func makeUIView(context: Context) -> Pad {
        let v = Pad()
        v.isMultipleTouchEnabled = true
        v.backgroundColor = .clear
        v.began = began
        v.moved = moved
        v.ended = ended
        v.isAccessibilityElement = true
        v.accessibilityLabel = T("record.pad")
        return v
    }
    func updateUIView(_ view: Pad, context: Context) {
        view.began = began
        view.moved = moved
        view.ended = ended
    }
    static func dismantleUIView(_ uiView: Pad, coordinator: ()) { uiView.finish() }
    final class Pad: UIView {
        var began: ((CGPoint) -> Void)?, moved: ((CGPoint) -> Void)?, ended: (() -> Void)?
        private var primary: UITouch?
        func location(_ touch: UITouch) -> CGPoint {
            let p = touch.location(in: self)
            return CGPoint(
                x: min(1, max(0, p.x / max(1, bounds.width))), y: min(1, max(0, p.y / max(1, bounds.height))))
        }
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard primary == nil, let t = touches.first else { return }
            primary = t
            began?(location(t))
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = primary, touches.contains(t) else { return }
            moved?(location(t))
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            if let t = primary, touches.contains(t) { finish() }
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { finish() }
        func finish() {
            if primary != nil {
                primary = nil
                ended?()
            }
        }
    }
}
