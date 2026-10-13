import PulseLoomCore
import SwiftUI
import UIKit

/// Create keeps one tool visible at a time with a one-line hint, then name and save.
/// Rarely used options stay in a collapsed group at the end.
struct CreateView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var editor: EditorModel
    @Environment(\.loom) var c
    @Environment(\.scenePhase) var scenePhase
    @State private var confirmNew = false
    @State private var nameText = ""
    @State private var nameWorkspace: UUID?
    @FocusState private var nameFocused: Bool
    var body: some View {
        let workspace = editor.workspaceID
        PlainScene(spacing: 12) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(T("create.title")).font(.system(.title3, design: .serif).italic())
                    Text(T("create.subtitle")).font(.caption2).foregroundStyle(c.muted).lineLimit(1)
                }
                Spacer()
                LoomIconButton(symbol: "plus", label: T("common.new")) { confirmNew = true }
            }
            Picker(T("create.tool"), selection: Binding(get: { editor.tool }, set: { editor.choose($0) })) {
                ForEach(EditorModel.Tool.allCases, id: \.self) { t in
                    Text(T("create.tool." + t.rawValue)).tag(t)
                }
            }.pickerStyle(.segmented)
            Text(T("create.hint." + editor.tool.rawValue)).font(.caption).foregroundStyle(c.muted)
                .fixedSize(horizontal: false, vertical: true)
            if editor.tool == .tap || editor.tool == .xy {
                recorder(workspace)
            } else if editor.tool == .basic {
                SegmentEditorView()
            } else {
                CurveEditorView()
            }
            HStack(spacing: 10) {
                TextField(T("editor.name"), text: $nameText)
                    .textFieldStyle(.roundedBorder).accessibilityIdentifier("patternName")
                    .focused($nameFocused).submitLabel(.done).onSubmit { finishNameEditing() }
                LoomButton(title: editor.saved ? "editor.saved" : "editor.save", symbol: "checkmark", fill: false) {
                    finishNameEditing()
                    editor.save()
                }.accessibilityIdentifier("savePattern")
            }
            if let e = editor.validationError { Text(e).font(.caption).foregroundStyle(.red) }
            if editor.tool != .tap && editor.tool != .xy {
                HStack(spacing: 10) {
                    LoomButton(title: "pattern.preview", symbol: "hand.tap", secondary: true, compact: true) { editor.preview() }
                    LoomButton(title: "common.stop", symbol: "stop.fill", secondary: true, compact: true, fill: false) { app.stopAll() }
                }
            }
            DisclosureGroup(T("editor.options")) {
                VStack(spacing: 10) {
                    Toggle(T("editor.loop"), isOn: Binding(get: { editor.draft.loop }, set: { v in editor.change { $0.loop = v } }))
                    Stepper(
                        String(format: T("editor.fadeIn"), Int(editor.draft.fadeIn)),
                        value: Binding(get: { editor.draft.fadeIn }, set: { v in editor.change { $0.fadeIn = v } }),
                        in: 0...5000, step: 100)
                    Stepper(
                        String(format: T("editor.fadeOut"), Int(editor.draft.fadeOut)),
                        value: Binding(get: { editor.draft.fadeOut }, set: { v in editor.change { $0.fadeOut = v } }),
                        in: 0...5000, step: 100)
                    HStack {
                        Button(T("common.undo")) { editor.undo() }.disabled(!editor.canUndo)
                        Spacer()
                        Button(T("common.redo")) { editor.redo() }.disabled(!editor.canRedo)
                    }.frame(minHeight: 44)
                    LoomButton(title: "common.export", symbol: "square.and.arrow.up", secondary: true, compact: true) {
                        finishNameEditing()
                        app.perform {
                            try Validation.pattern(editor.draft)
                            app.export(editor.draft, name: "PulseLoom-pattern")
                        }
                    }
                    Text(T("editor.localHelp")).font(.caption2).foregroundStyle(c.muted)
                }.padding(.top, 8)
            }.font(.subheadline)
        }.toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(T("common.done")) { finishNameEditing() }
                    .accessibilityIdentifier("editorKeyboardDone")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            editor.attach(app)
            syncName()
        }.onDisappear {
            commitName()
            nameFocused = false
            editor.endTouch()
            editor.end()
            editor.persist()
        }.onChange(of: scenePhase) { _, p in
            if p != .active {
                commitName()
                nameFocused = false
                editor.endTouch()
                editor.end()
            }
        }
        .onChange(of: editor.workspaceID) { _, _ in
            nameFocused = false
            syncName()
        }
        .onChange(of: editor.draft.name) { _, _ in
            if !nameFocused { syncName() }
        }
        .onChange(of: nameFocused) { _, focused in
            if !focused { commitName() }
        }
        .onChange(of: nameText) { _, value in
            if value.count > 30 { nameText = String(value.prefix(30)) }
        }
        .task(id: nameText) {
            // Keep rapid text entry local: publishing the draft and whole app
            // on every key can replace the text control while events arrive.
            let lease = nameWorkspace
            do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return }
            guard nameFocused, lease == editor.workspaceID else { return }
            commitName()
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
    @ViewBuilder private func recorder(_ workspace: UUID) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [c.tint, c.surface], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(c.line, lineWidth: 0.8))
            if editor.tool == .xy {
                Circle().fill(c.accent).frame(width: 28, height: 28)
                    .shadow(color: c.accent.opacity(0.4), radius: 8)
                    .offset(x: (editor.x - 0.5) * 260, y: (0.5 - editor.y) * 150)
            } else {
                HeroArt(level: editor.down ? 1 : 0, playing: editor.down).padding(16)
            }
            if !editor.recording {
                Text(T("record.startHint")).font(.system(.subheadline, design: .serif)).foregroundStyle(c.muted)
                    .padding(8).background(c.surface.opacity(0.8), in: Capsule())
            }
            TouchSurface(
                began: { if editor.workspaceID == workspace { editor.touchBegan($0) } },
                moved: { if editor.workspaceID == workspace { editor.touchMoved($0) } },
                ended: { if editor.workspaceID == workspace { editor.endTouch() } })
        }.frame(height: 190)
        HStack {
            Text(timeText(editor.seconds) + " / 00:30").font(.subheadline.monospacedDigit())
            Spacer()
            Text(String(format: T("record.count"), editor.touches)).font(.caption).foregroundStyle(c.muted)
        }
        HStack(spacing: 10) {
            LoomButton(title: editor.recording ? "record.end" : "record.begin", symbol: "record.circle") {
                if editor.recording { editor.end() } else { editor.start() }
            }.accessibilityIdentifier("recordStart")
            LoomIconButton(symbol: "arrow.uturn.backward", label: T("common.undo")) { editor.removeLastTouch() }
            LoomIconButton(symbol: "hand.tap", label: T("pattern.preview")) { editor.preview() }
        }
        // Accessible tap recording also has an ordinary button, independent of spatial gestures.
        if editor.recording {
            Button(T("record.accessibleTap")) {
                editor.touchBegan(CGPoint(x: editor.x, y: 1 - editor.y))
                let take = editor.recordingID
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    guard editor.workspaceID == workspace else { return }
                    editor.endTouch(recording: take)
                }
            }.frame(minHeight: 44)
        }
    }
    private func finishNameEditing() {
        commitName()
        nameFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        editor.persist()
    }
    private func syncName() {
        nameWorkspace = editor.workspaceID
        nameText = editor.draft.name
    }
    private func commitName() {
        guard nameWorkspace == editor.workspaceID, nameText != editor.draft.name else { return }
        editor.nameBinding.wrappedValue = nameText
    }
}

/// Bars show each segment's length and strength; the selected one is adjusted with two sliders and
/// two steppers, in plain words.
struct SegmentEditorView: View {
    @EnvironmentObject var editor: EditorModel
    @Environment(\.loom) var c
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(editor.draft.segments.enumerated()), id: \.element.id) { i, s in
                        Button {
                            editor.selected = i
                        } label: {
                            VStack(spacing: 3) {
                                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(
                                    editor.selected == i ? c.accent : c.hero2
                                ).frame(
                                    width: CGFloat(max(22, (s.duration + s.gap) / 15)) * CGFloat(editor.zoom),
                                    height: 18 + s.gain * 42)
                                Text("\(i+1)").font(.caption2).foregroundStyle(editor.selected == i ? c.ink : c.muted)
                            }
                        }.buttonStyle(.plain)
                    }
                }.padding(6)
            }
            .background(c.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            HStack {
                Text(String(format: T("editor.segmentCount"), editor.draft.segments.count, editor.draft.durationMS / 1000))
                    .font(.caption).foregroundStyle(c.muted)
                Spacer()
                Button("\(editor.zoom)×") { editor.zoom = editor.zoom == 4 ? 1 : editor.zoom * 2 }.font(.caption).frame(minHeight: 32)
                Button {
                    editor.addSegment()
                } label: {
                    Label(T("editor.add"), systemImage: "plus").font(.caption)
                }.frame(minHeight: 32)
            }
            if editor.draft.segments.indices.contains(editor.selected) {
                LoomCard(padding: 14) {
                    VStack(spacing: 10) {
                        HStack {
                            Text(String(format: T("editor.segment"), editor.selected + 1)).font(.headline)
                            Spacer()
                            Button { editor.move(-1) } label: { Image(systemName: "arrow.left").frame(width: 36, height: 36) }
                                .accessibilityLabel(T("editor.moveBefore"))
                            Button { editor.move(1) } label: { Image(systemName: "arrow.right").frame(width: 36, height: 36) }
                                .accessibilityLabel(T("editor.moveAfter"))
                            Button { editor.duplicate() } label: { Image(systemName: "doc.on.doc").frame(width: 36, height: 36) }
                                .accessibilityLabel(T("common.duplicate"))
                            Button { editor.deleteSegment() } label: { Image(systemName: "trash").frame(width: 36, height: 36) }
                                .accessibilityLabel(T("common.delete"))
                        }
                        LoomSlider(title: "home.intensity", value: editor.segmentBinding(\.gain)) { editor.endEditingGesture() }
                        LoomSlider(title: "home.texture", value: editor.segmentBinding(\.sharp)) { editor.endEditingGesture() }
                        Toggle(T("editor.tapType"), isOn: tapBinding).font(.subheadline)
                        if !isTap {
                            Stepper(
                                T("editor.duration") + ": \(Int(editor.segmentBinding(\.duration).wrappedValue)) " + T("unit.ms"),
                                value: editor.segmentBinding(\.duration), in: 50...2000, step: 50,
                                onEditingChanged: { if !$0 { editor.endEditingGesture() } }
                            ).font(.subheadline)
                        }
                        Stepper(
                            T("editor.gap") + ": \(Int(editor.segmentBinding(\.gap).wrappedValue)) " + T("unit.ms"),
                            value: editor.segmentBinding(\.gap), in: 0...5000, step: 50,
                            onEditingChanged: { if !$0 { editor.endEditingGesture() } }
                        ).font(.subheadline)
                    }
                }
            }
        }
    }
    private var isTap: Bool {
        editor.draft.segments.indices.contains(editor.selected) && editor.draft.segments[editor.selected].type == .transient
    }
    private var tapBinding: Binding<Bool> {
        Binding(get: { isTap }, set: { on in
            guard editor.draft.segments.indices.contains(editor.selected) else { return }
            let index = editor.selected
            editor.change { p in
                p.segments[index].type = on ? .transient : .continuous
                p.segments[index].duration = on ? 30 : max(50, p.segments[index].duration)
            }
        })
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
// Keep each view-builder expression small enough for Apple SDK type checking.
struct CurveEditorView: View {
    @EnvironmentObject var editor: EditorModel
    var body: some View {
        VStack(spacing: 12) {
            CurveCanvasView().frame(height: 180)
            cycleControl
            templateButtons
            LoomButton(title: "editor.addNode", symbol: "plus", secondary: true, compact: true) { editor.addNode() }
            DisclosureGroup(T("editor.nodeValues")) {
                ForEach(editor.draft.nodes) { node in
                    CurveNodeFields(nodeID: node.id)
                }
            }.font(.subheadline)
        }
    }
    private var cycleControl: some View {
        Stepper(
            String(format: T("editor.cycle"), editor.draft.cycle / 1000),
            value: Binding(get: { editor.draft.cycle / 1000 }, set: { editor.length($0) }),
            in: 0.1...30, step: 0.5).font(.subheadline)
    }
    private var templateButtons: some View {
        HStack(spacing: 8) {
            ForEach(["wave", "rise", "fall"], id: \.self) { name in
                LoomChip(title: T("curve.template." + name)) { editor.applyCurveTemplate(name) }
            }
        }
    }
}

private struct CurveCanvasView: View {
    @EnvironmentObject var editor: EditorModel
    @Environment(\.loom) var c
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [c.tint, c.surface], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(c.line, lineWidth: 0.8))
                    .onTapGesture(coordinateSpace: .local) { point in
                        editor.addNode(time: time(at: point.x, size: geometry.size))
                    }
                curvePath(in: geometry.size).stroke(c.accent, lineWidth: 1.5)
                    .allowsHitTesting(false)
                ForEach(editor.draft.nodes) { node in
                    nodeHandle(node, size: geometry.size)
                }
            }.coordinateSpace(name: "curve")
        }
    }
    private func position(_ node: CurveNode, size: CGSize) -> CGPoint {
        let cycle = max(1, editor.draft.cycle)
        let x = 12 + CGFloat(node.time / cycle) * max(1, size.width - 24)
        let y = 12 + CGFloat(1 - node.value) * max(1, size.height - 24)
        return CGPoint(x: x, y: y)
    }
    private func time(at x: CGFloat, size: CGSize) -> Double {
        Double((x - 12) / max(1, size.width - 24)) * editor.draft.cycle
    }
    private func curvePath(in size: CGSize) -> Path {
        Path { path in
            for (index, node) in editor.draft.nodes.enumerated() {
                let point = position(node, size: size)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }
    private func nodeHandle(_ node: CurveNode, size: CGSize) -> some View {
        let number = (editor.draft.nodes.firstIndex { $0.id == node.id } ?? 0) + 1
        return Circle().fill(c.surface)
            .overlay(Circle().stroke(c.accent, lineWidth: 2))
            .frame(width: 22, height: 22)
            .position(position(node, size: size))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("curve"))
                    .onChanged { gesture in
                        guard let index = editor.draft.nodes.firstIndex(where: { $0.id == node.id }) else {
                            return
                        }
                        let value = 1 - Double((gesture.location.y - 12) / max(1, size.height - 24))
                        editor.nodeChanged(index, time: time(at: gesture.location.x, size: size), value: value)
                    }
                    .onEnded { _ in editor.endEditingGesture() }
            )
            .accessibilityLabel(String(format: T("editor.node"), number))
    }
}

private struct CurveNodeFields: View {
    @EnvironmentObject var editor: EditorModel
    let nodeID: UUID
    private var index: Int? { editor.draft.nodes.firstIndex { $0.id == nodeID } }
    private var node: CurveNode? { editor.draft.nodes.first { $0.id == nodeID } }
    var body: some View {
        if let index {
            VStack {
                Text(String(format: T("editor.node"), index + 1)).font(.caption)
                HStack {
                    TextField(T("editor.time"), value: timeBinding, format: .number)
                        .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                    TextField(T("home.intensity"), value: intensityBinding, format: .number)
                        .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                    Button {
                        editor.removeNode(nodeID)
                    } label: {
                        Image(systemName: "trash").frame(width: 44, height: 44)
                    }.disabled(index == 0 || index == editor.draft.nodes.count - 1)
                }
            }.padding(.vertical, 6)
        }
    }
    // Resolve by identity on every edit so deletion never leaves a stale captured index/value.
    private var timeBinding: Binding<Double> {
        Binding(
            get: { node?.time ?? 0 },
            set: { value in
                guard let index, let node else { return }
                editor.nodeChanged(index, time: value, value: node.value)
                editor.endEditingGesture()
            })
    }
    private var intensityBinding: Binding<Double> {
        Binding(
            get: { (node?.value ?? 0) * 100 },
            set: { value in
                guard let index, let node else { return }
                editor.nodeChanged(index, time: node.time, value: value / 100)
                editor.endEditingGesture()
            })
    }
}
