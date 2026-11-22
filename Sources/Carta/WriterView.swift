import AppKit
import SwiftUI

struct WriterView: View {
    @ObservedObject var state: ReaderState
    private var ruler = State<TypewriterRuler?>(initialValue: nil)
    private var mechanical: Bool { state.mode == .typewriter }

    var body: some View {
        let paper = A4Paper(scale: state.paperDisplay.magnification)
        ZStack {
            if mechanical {
                LinearGradient(colors: [Color(red: 0.84, green: 0.88, blue: 0.91),
                                        Color(red: 0.76, green: 0.81, blue: 0.85)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .accessibilityHidden(true)
            }
            TypewriterEditor(state: state, scale: paper.scale, mechanical: mechanical,
                             marginReleased: state.marginReleased, editable: !state.isLoading) { position in
                if ruler.wrappedValue != position { ruler.wrappedValue = position }
            }
                .id(state.editorSession)
            if mechanical, let ruler = ruler.wrappedValue {
                GeometryReader { geometry in
                    let width = min(paper.width + 90, max(1, geometry.size.width - 32))
                    let left = (geometry.size.width - width) / 2
                    GlassCarriage(state: state, step: paper.pitch, zeroX: ruler.zeroX - left, indexX: ruler.caret.x - left)
                        .frame(width: width, height: TypewriterRuler.height)
                        .position(x: geometry.size.width / 2, y: ruler.caret.y - TypewriterRuler.gap - TypewriterRuler.height / 2)
                }
                .clipped()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button("A4", action: state.calibratePaper)
                .font(.system(size: 11, weight: .medium)).buttonStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .writingGlass(in: Capsule()).padding(12)
                .help("Calibra la misura del foglio A4 su questo schermo")
                .accessibilityLabel("Calibra la misura del foglio A4")
                .disabled(state.paperDisplay.preferenceKey == nil)
        }
        .overlay(alignment: .topTrailing) {
            if state.isLoading { ProgressView().controlSize(.small).padding(16) }
        }
    }
}

private struct GlassCarriage: View {
    @ObservedObject var state: ReaderState
    let step: CGFloat
    let zeroX: CGFloat
    let indexX: CGFloat
    private let controlWidth: CGFloat = 36
    private let sidePadding: CGFloat = 6
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.colorSchemeContrast) private var contrast
    private let ink = Color(red: 0.10, green: 0.17, blue: 0.18)
    private let teal = Color(red: 0.03, green: 0.48, blue: 0.46)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        HStack(spacing: 0) {
            Button { state.marginReleased.toggle() } label: {
                Image(systemName: state.marginReleased ? "lock.open" : "lock")
                    .frame(width: controlWidth, height: 32)
            }
            .accessibilityLabel("Margine a 60 colonne").accessibilityValue(state.marginReleased ? "Libero" : "Attivo")
            .help(state.marginReleased ? "Ripristina il margine a 60 colonne" : "Sblocca il margine destro")
            scale
                .allowsHitTesting(false)
                .accessibilityLabel("Colonna").accessibilityValue(String(state.editorColumn + 1))
            Button { state.typewriterSound.toggle() } label: {
                Image(systemName: state.typewriterSound ? "speaker.wave.2" : "speaker.slash")
                    .frame(width: controlWidth, height: 32)
            }
            .accessibilityLabel("Suoni della macchina da scrivere").accessibilityValue(state.typewriterSound ? "Attivi" : "Disattivati")
            .help(state.typewriterSound ? "Disattiva i suoni" : "Attiva i suoni")
        }
        .padding(.horizontal, sidePadding)
        .buttonStyle(.plain).foregroundStyle(ink)
        .background {
            if !opaque {
                shape.fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .light)
                    .opacity(0.72)
            }
            shape.fill(LinearGradient(colors: [
                Color(red: 0.77, green: 0.90, blue: 0.90).opacity(opaque ? 1 : 0.62),
                Color(red: 0.86, green: 0.94, blue: 0.93).opacity(opaque ? 1 : 0.29),
                Color(red: 0.69, green: 0.83, blue: 0.83).opacity(opaque ? 1 : 0.51)
            ], startPoint: .top, endPoint: .bottom))
            .shadow(color: .black.opacity(0.18), radius: 3, y: 4)
        }
        .overlay {
            shape.strokeBorder(ink.opacity(contrast == .increased ? 0.65 : 0.26), lineWidth: 0.8)
            shape.inset(by: 1).strokeBorder(.white.opacity(0.80), lineWidth: 0.8)
        }
        .overlay(alignment: .top) {
            Canvas { context, size in
                guard (0...size.width).contains(indexX) else { return }
                let index = Path { path in
                    path.move(to: CGPoint(x: indexX - 5.5, y: 0))
                    path.addLine(to: CGPoint(x: indexX + 5.5, y: 0))
                    path.addLine(to: CGPoint(x: indexX, y: size.height))
                    path.closeSubpath()
                }
                let nearMargin = state.editorColumn >= TypewriterMetrics.bellColumn && !state.marginReleased
                context.fill(index, with: .color(nearMargin ? .init(red: 0.67, green: 0.31, blue: 0.10) : teal))
            }
            .frame(height: 8).offset(y: -8).allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    private var scale: some View {
        Canvas { context, size in
            let zero = zeroX - sidePadding - controlWidth
            let lower = max(0, Int(ceil(-zero / step)))
            let upper = Int(floor((size.width - zero) / step))
            guard lower <= upper else { return }
            for tick in lower...upper {
                let x = zero + CGFloat(tick) * step
                let major = tick.isMultiple(of: 10)
                let height: CGFloat = major ? 11 : (tick.isMultiple(of: 5) ? 8 : 5)
                var mark = Path()
                mark.move(to: CGPoint(x: x, y: size.height - 2 - height))
                mark.addLine(to: CGPoint(x: x, y: size.height - 2))
                context.stroke(mark, with: .color(ink), lineWidth: major ? 1 : 0.65)
                if major {
                    context.draw(Text("\(tick)").font(.system(size: 11)).foregroundColor(ink),
                                 at: CGPoint(x: x, y: 9))
                }
            }
        }
    }
}

private struct TypewriterEditor: NSViewRepresentable {
    let state: ReaderState
    let scale: CGFloat
    let mechanical: Bool
    let marginReleased: Bool
    let editable: Bool
    let onRulerChange: (TypewriterRuler?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> TypewriterScrollView {
        let scroll = TypewriterScrollView()
        scroll.onRulerChange = onRulerChange
        scroll.onDisplayChange = { [weak state] display in state?.usePaperDisplay(display) }
        scroll.applyPaperScale(scale, mechanical: mechanical)
        let editor = scroll.editor
        editor.load(state.editingText, selection: state.editorSelection)
        editor.delegate = context.coordinator
        scroll.onFocus = { [weak coordinator = context.coordinator] editor in coordinator?.updateSelection(editor) }
        editor.sound = { [weak coordinator = context.coordinator] sound in coordinator?.play(sound) }
        return scroll
    }

    static func dismantleNSView(_ scroll: TypewriterScrollView, coordinator: Coordinator) {
        scroll.onRulerChange = nil
    }

    func updateNSView(_ scroll: TypewriterScrollView, context: Context) {
        context.coordinator.parent = self
        scroll.appearance = mechanical ? NSAppearance(named: .aqua) : nil
        scroll.applyPaperScale(scale, mechanical: mechanical)
        scroll.editor.marginReleased = marginReleased
        scroll.editor.isEditable = editable
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TypewriterEditor
        private var samples: [TypewriterSound: [NSSound]] = [:]
        private let undoManager = UndoManager()

        init(parent: TypewriterEditor) { self.parent = parent }

        func undoManager(for view: NSTextView) -> UndoManager? { undoManager }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.state.updateDraft(editor.string)
            updateSelection(editor)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            updateSelection(editor)
        }

        func updateSelection(_ editor: NSTextView) {
            guard let editor = editor as? TypewriterTextView else { return }
            parent.state.updateEditorSelection(editor.selectedRange(), insertion: editor.insertionOffset, in: editor.string as NSString)
            (editor.enclosingScrollView as? TypewriterScrollView)?.scheduleRulerUpdate()
        }

        func play(_ sound: TypewriterSound) {
            guard parent.state.typewriterSound else { return }
            if let available = samples[sound]?.first(where: { !$0.isPlaying }) {
                available.play()
            } else if let sample = NSSound(contentsOf: Resource.url("TypewriterSounds/\(sound.rawValue).wav"), byReference: true) {
                samples[sound, default: []].append(sample)
                sample.play()
            }
        }
    }
}
