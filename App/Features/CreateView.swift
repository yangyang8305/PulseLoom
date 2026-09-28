import PulseLoomCore
import SwiftUI

struct CreateView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var editor: EditorModel
    @Environment(\.loom) var c
    @Environment(\.scenePhase) var scenePhase
    @State private var confirmNew = false
    var body: some View {
        PlainScene {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text(T("create.title")).font(.title.bold())
                    Text(T("create.subtitle")).font(.footnote).foregroundStyle(c.muted)
                }
                Spacer()
                Button {
                    confirmNew = true
                } label: {
                    Image(systemName: "plus").frame(width: 44, height: 44)
                }
            }
            Picker(T("create.tool"), selection: Binding(get: { editor.tool }, set: { editor.choose($0) })) {
                ForEach(EditorModel.Tool.allCases, id: \.self) { t in
                    Text(T("create.tool." + t.rawValue)).tag(t)
                }
            }.pickerStyle(.segmented)
            if editor.tool == .tap || editor.tool == .xy {
                ZStack {
                    if editor.tool == .xy {
                        RoundedRectangle(cornerRadius: 25).fill(
                            LinearGradient(colors: [c.hero2, c.surface], startPoint: .top, endPoint: .bottom))
                        Circle().fill(c.accent).frame(width: 30, height: 30).offset(
                            x: (editor.x - 0.5) * 270, y: (0.5 - editor.y) * 220)
                    } else {
                        TactileArt(style: "orb", level: editor.down ? 1 : 0)
                    }
                    if !editor.recording {
                        Text(T("record.startHint")).font(.system(.title3, design: .serif))
                    }
                    TouchSurface(
                        began: { editor.touchBegan($0) }, moved: { editor.touchMoved($0) },
                        ended: { editor.endTouch() })
                }.frame(height: 240)
                Text(timeText(editor.seconds) + " / 00:30").font(.title2.monospacedDigit()).frame(
                    maxWidth: .infinity)
                Text(String(format: T("record.count"), editor.touches)).font(.caption).foregroundStyle(
                    c.muted
                ).frame(maxWidth: .infinity)
                LoomButton(title: editor.recording ? "record.end" : "record.begin", symbol: "record.circle") {
                    if editor.recording { editor.end() } else { editor.start() }
                }.accessibilityIdentifier("recordStart")
                HStack {
                    LoomButton(title: "common.undo", symbol: "arrow.uturn.backward", secondary: true) {
                        editor.removeLastTouch()
                    }
                    LoomButton(title: "pattern.preview", symbol: "hand.tap", secondary: true) {
                        editor.preview()
                    }
                }
                // Accessible tap recording also has an ordinary button, independent of spatial gestures.
                if editor.recording {
                    Button(T("record.accessibleTap")) {
                        editor.touchBegan(CGPoint(x: editor.x, y: 1 - editor.y))
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { editor.endTouch() }
                    }.frame(minHeight: 44)
                }
                if editor.tool == .xy {
                    LoomSlider(title: "home.intensity", value: $editor.y)
                    LoomSlider(title: "home.texture", value: $editor.x)
                }
            } else if editor.tool == .basic {
                SegmentEditorView()
            } else {
                CurveEditorView()
            }
            TextField(
                T("editor.name"),
                text: Binding(
                    get: { editor.draft.name },
                    set: { v in
                        editor.draft.name = String(v.prefix(30))
                        editor.persist()
                    })
            ).textFieldStyle(.roundedBorder).accessibilityIdentifier("patternName")
            if let e = editor.validationError { Text(e).font(.caption).foregroundStyle(.red) }
            LoomButton(title: editor.saved ? "editor.saved" : "editor.save", symbol: "checkmark") {
                editor.save()
            }.accessibilityIdentifier("savePattern")
            if editor.tool != .tap {
                LoomButton(title: "pattern.preview", symbol: "hand.tap", secondary: true) { editor.preview() }
            }
            DisclosureGroup(T("editor.options")) {
                Toggle(
                    T("editor.loop"),
                    isOn: Binding(get: { editor.draft.loop }, set: { v in editor.change { $0.loop = v } })
                ).padding(.vertical, 10)
                Stepper(
                    String(format: T("editor.fadeIn"), Int(editor.draft.fadeIn)),
                    value: Binding(
                        get: { editor.draft.fadeIn }, set: { v in editor.change { $0.fadeIn = v } }),
                    in: 0...5000, step: 100)
                Stepper(
                    String(format: T("editor.fadeOut"), Int(editor.draft.fadeOut)),
                    value: Binding(
                        get: { editor.draft.fadeOut }, set: { v in editor.change { $0.fadeOut = v } }),
                    in: 0...5000, step: 100)
                HStack {
                    Button(T("common.undo")) { editor.undo() }.disabled(!editor.canUndo)
                    Spacer()
                    Button(T("common.redo")) { editor.redo() }.disabled(!editor.canRedo)
                }.frame(minHeight: 44)
                LoomButton(title: "common.export", symbol: "square.and.arrow.up", secondary: true) {
                    app.perform {
                        try Validation.pattern(editor.draft)
                        app.export(editor.draft, name: "PulseLoom-pattern")
                    }
                }
            }
            Notice(text: "editor.localHelp")
        }.toolbar(.hidden, for: .navigationBar).onAppear { editor.attach(app) }.onDisappear {
            editor.endTouch()
            editor.end()
            editor.persist()
        }.onChange(of: scenePhase) { _, p in
            if p != .active {
                editor.endTouch()
                editor.end()
            }
        }
        .alert(T("editor.replaceDraft"), isPresented: $confirmNew) {
            Button(T("common.cancel"), role: .cancel) {}
            Button(T("common.new"), role: .destructive) { editor.new() }
        } message: {
            Text(T("editor.replaceHelp"))
        }
        .alert(
            T("common.error"),
            isPresented: Binding(get: { editor.error != nil }, set: { if !$0 { editor.error = nil } })
        ) {
            Button(T("common.done")) { editor.error = nil }
        } message: {
            Text(editor.error ?? "")
        }
    }
}
struct SegmentEditorView: View {
    @EnvironmentObject var editor: EditorModel
    @Environment(\.loom) var c
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            ScrollView(.horizontal) {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(editor.draft.segments.enumerated()), id: \.element.id) { i, s in
                        Button {
                            editor.selected = i
                        } label: {
                            VStack {
                                RoundedRectangle(cornerRadius: 7).fill(
                                    editor.selected == i ? c.accent : c.hero2
                                ).frame(
                                    width: CGFloat(max(24, (s.duration + s.gap) / 15)) * CGFloat(editor.zoom),
                                    height: 20 + s.gain * 40)
                                Text("\(i+1)").font(.caption2)
                            }
                        }
                    }
                }.padding(5)
            }
            HStack {
                Text(
                    String(
                        format: T("editor.segmentCount"), editor.draft.segments.count,
                        editor.draft.durationMS / 1000)
                ).font(.caption)
                Spacer()
                Button("\(editor.zoom)×") { editor.zoom = editor.zoom == 4 ? 1 : editor.zoom * 2 }.frame(
                    minHeight: 44)
            }
            if editor.draft.segments.indices.contains(editor.selected) {
                LoomCard {
                    VStack(spacing: 14) {
                        HStack {
                            Text(String(format: T("editor.segment"), editor.selected + 1)).font(.headline)
                            Spacer()
                            Button {
                                editor.deleteSegment()
                            } label: {
                                Image(systemName: "trash").frame(width: 44, height: 44)
                            }
                        }
                        LoomSlider(title: "home.intensity", value: editor.segmentBinding(\.gain)) {
                            editor.endEditingGesture()
                        }
                        LoomSlider(title: "home.texture", value: editor.segmentBinding(\.sharp)) {
                            editor.endEditingGesture()
                        }
                        NumberInput(
                            title: "editor.duration", value: editor.segmentBinding(\.duration),
                            unit: "unit.ms"
                        ) { editor.endEditingGesture() }
                        NumberInput(title: "editor.gap", value: editor.segmentBinding(\.gap), unit: "unit.ms")
                        { editor.endEditingGesture() }
                        HStack {
                            Button {
                                editor.move(-1)
                            } label: {
                                Image(systemName: "arrow.left").frame(width: 44, height: 44)
                            }.accessibilityLabel(T("editor.moveBefore"))
                            Button {
                                editor.move(1)
                            } label: {
                                Image(systemName: "arrow.right").frame(width: 44, height: 44)
                            }.accessibilityLabel(T("editor.moveAfter"))
                            Spacer()
                            Button {
                                editor.duplicate()
                            } label: {
                                Image(systemName: "doc.on.doc").frame(width: 44, height: 44)
                            }.accessibilityLabel(T("common.duplicate"))
                            Button {
                                editor.addSegment()
                            } label: {
                                Image(systemName: "plus").frame(width: 44, height: 44)
                            }.accessibilityLabel(T("editor.add"))
                        }
                    }
                }
            } else {
                LoomButton(title: "editor.add", symbol: "plus", secondary: true) { editor.addSegment() }
            }
        }
    }
}
struct NumberInput: View {
    let title: String
    @Binding var value: Double
    var unit = ""
    var action: () -> Void = {}
    var body: some View {
        HStack {
            Text(T(title)).font(.subheadline)
            Spacer()
            TextField("", value: $value, format: .number.precision(.fractionLength(0...2))).keyboardType(
                .decimalPad
            ).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder).frame(maxWidth: 110).onSubmit(
                action
            ).accessibilityLabel(T(title))
            if !unit.isEmpty { Text(T(unit)).font(.caption) }
        }
    }
}
struct CurveEditorView: View {
    @EnvironmentObject var editor: EditorModel
    @Environment(\.loom) var c
    var body: some View {
        VStack(spacing: 15) {
            GeometryReader { g in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 20).fill(c.tint).onTapGesture(coordinateSpace: .local) {
                        point in
                        editor.addNode(time: (point.x - 12) / max(1, g.size.width - 24) * editor.draft.cycle)
                    }
                    Path { p in
                        for (i, n) in editor.draft.nodes.enumerated() {
                            let q = CGPoint(
                                x: 12 + n.time / editor.draft.cycle * (g.size.width - 24),
                                y: 12 + (1 - n.value) * (g.size.height - 24))
                            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
                        }
                    }.stroke(c.accent, lineWidth: 1.5)
                    ForEach(Array(editor.draft.nodes.enumerated()), id: \.element.id) { i, n in
                        Circle().fill(c.surface).overlay(Circle().stroke(c.accent, lineWidth: 2)).frame(
                            width: 22, height: 22
                        ).position(
                            x: 12 + n.time / editor.draft.cycle * (g.size.width - 24),
                            y: 12 + (1 - n.value) * (g.size.height - 24)
                        ).gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("curve")).onChanged { v in
                                editor.nodeChanged(
                                    i, time: (v.location.x - 12) / (g.size.width - 24) * editor.draft.cycle,
                                    value: 1 - (v.location.y - 12) / (g.size.height - 24))
                            }.onEnded { _ in editor.endEditingGesture() }
                        ).accessibilityLabel(String(format: T("editor.node"), i + 1))
                    }
                }.coordinateSpace(name: "curve")
            }.frame(height: 185)
            Stepper(
                String(format: T("editor.cycle"), editor.draft.cycle / 1000),
                value: Binding(get: { editor.draft.cycle / 1000 }, set: { editor.length($0) }), in: 0.1...30,
                step: 0.5)
            HStack {
                ForEach(["wave", "rise", "fall"], id: \.self) { name in
                    Button(T("curve.template." + name)) { editor.applyCurveTemplate(name) }.frame(
                        maxWidth: .infinity, minHeight: 44)
                }
            }
            LoomButton(title: "editor.addNode", symbol: "plus", secondary: true) { editor.addNode() }
            DisclosureGroup(T("editor.nodeValues")) {
                ForEach(Array(editor.draft.nodes.enumerated()), id: \.element.id) { i, n in
                    VStack {
                        Text(String(format: T("editor.node"), i + 1)).font(.caption)
                        HStack {
                            TextField(
                                T("editor.time"),
                                value: Binding(
                                    get: {
                                        editor.draft.nodes.indices.contains(i)
                                            ? editor.draft.nodes[i].time : 0
                                    },
                                    set: { v in
                                        editor.nodeChanged(i, time: v, value: n.value)
                                        editor.endEditingGesture()
                                    }), format: .number
                            ).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                            TextField(
                                T("home.intensity"),
                                value: Binding(
                                    get: {
                                        editor.draft.nodes.indices.contains(i)
                                            ? editor.draft.nodes[i].value * 100 : 0
                                    },
                                    set: { v in
                                        editor.nodeChanged(i, time: n.time, value: v / 100)
                                        editor.endEditingGesture()
                                    }), format: .number
                            ).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                            Button {
                                editor.removeNode(n.id)
                            } label: {
                                Image(systemName: "trash").frame(width: 44, height: 44)
                            }.disabled(i == 0 || i == editor.draft.nodes.count - 1)
                        }
                    }.padding(.vertical, 6)
                }
            }
        }
    }
}
