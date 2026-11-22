import AppKit

struct TypewriterMetrics {
    static let columns = 60
    static let bellColumn = 54
    static let tabWidth = 8
    static let lineHeight: CGFloat = 28
    static let margin: CGFloat = 44
    static let font = NSFont(name: "Courier", size: 17) ?? .monospacedSystemFont(ofSize: 17, weight: .regular)
    static let pitch = ("0" as NSString).size(withAttributes: [.font: font]).width
    static let paperWidth = ceil(pitch * CGFloat(columns + 1) + 2 * margin)

    static func column(in text: NSString, at offset: Int) -> Int {
        let index = min(max(0, offset), text.length)
        let line = text.lineRange(for: NSRange(location: index, length: 0))
        return advancing(0, by: text.substring(with: NSRange(location: line.location, length: index - line.location)))
    }

    static func advancing(_ column: Int, by text: String) -> Int {
        text.reduce(column) { position, character in
            character == "\t" ? position + tabWidth - position % tabWidth : position + 1
        }
    }
}

private enum TypewriterPaper {
    private static func adaptive(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    static let sheet = adaptive(NSColor(srgbRed: 0.992, green: 0.986, blue: 0.971, alpha: 1),
                                NSColor(srgbRed: 0.145, green: 0.166, blue: 0.185, alpha: 1))
    static let ink = adaptive(NSColor(srgbRed: 0.15, green: 0.18, blue: 0.20, alpha: 1),
                              NSColor(srgbRed: 0.92, green: 0.93, blue: 0.92, alpha: 1))
    static let typewriterInk = NSColor(srgbRed: 0.09, green: 0.13, blue: 0.14, alpha: 1)
    static let ivory: NSColor = {
        // One repeatable fine-grain tile keeps the paper matte at any zoom.
        let side = 128
        guard let tile = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: side * 3, bitsPerPixel: 24),
            let pixels = tile.bitmapData else { return .init(srgbRed: 0.966, green: 0.947, blue: 0.913, alpha: 1) }
        var seed: UInt32 = 438
        for index in 0..<(side * side) {
            seed = seed &* 1664525 &+ 1013904223
            let grain = Int(seed >> 29) - 3
            pixels[index * 3] = UInt8(247 + grain)
            pixels[index * 3 + 1] = UInt8(242 + grain)
            pixels[index * 3 + 2] = UInt8(232 + grain)
        }
        let image = NSImage(size: NSSize(width: 64, height: 64))
        tile.size = image.size
        image.addRepresentation(tile)
        return NSColor(patternImage: image)
    }()
}

enum TypewriterSound: String {
    case key1, key2, key3, space, backspace, carriage, bell, stop
}

@MainActor final class TypewriterTextView: NSTextView {
    var sound: (TypewriterSound) -> Void = { _ in }
    var marginReleased = false
    var newline = "\n"
    private var typing = false
    private var struckKey = false
    private var emptyBackspace = false
    private var nextStrike = 0
    private let storage = NSTextStorage()
    private var optionShortcut = MarkdownOptionShortcut()
    private var optionEventMonitor: Any?

    init() {
        let layout = NSLayoutManager()
        let container = A4TextContainer(containerSize: NSSize(width: 10_000_000, height: 10_000_000))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        container.lineFragmentPadding = 0
        super.init(frame: NSRect(x: 0, y: 0, width: TypewriterMetrics.paperWidth, height: 0), textContainer: container)
        autoresizingMask = []
        isHorizontallyResizable = true
        isVerticallyResizable = true
        minSize = NSSize(width: TypewriterMetrics.paperWidth, height: 0)
        maxSize = NSSize(width: 10_000_000, height: 10_000_000)
        textContainerInset = NSSize(width: TypewriterMetrics.margin, height: 110)
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticTextCompletionEnabled = false
        usesFindPanel = false
        drawsBackground = false
        insertionPointColor = TypewriterPaper.ink
        selectedTextAttributes = [.backgroundColor: NSColor.selectedTextBackgroundColor,
                                  .foregroundColor: NSColor.selectedTextColor]
        setAccessibilityLabel("Foglio della macchina da scrivere")
    }

    required init?(coder: NSCoder) { nil }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if let optionEventMonitor { NSEvent.removeMonitor(optionEventMonitor) }
        optionEventMonitor = nil
        let center = NotificationCenter.default
        center.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        resetOptionShortcut()
        guard let newWindow else { return }
        center.addObserver(self, selector: #selector(resetOptionShortcut), name: NSWindow.didResignKeyNotification, object: newWindow)
        // Observe chords before AppKit routes key equivalents or an Option-click to another control.
        optionEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel
        ]) { [weak self] event in
            guard let self, let window = self.window else { return event }
            guard (event.window ?? NSApp.keyWindow) === window, window.firstResponder === self,
                  self.isEditable, !self.hasMarkedText() else {
                self.resetOptionShortcut()
                return event
            }
            if self.optionShortcut.shouldOpen(on: event) { self.showMarkdownMenuAtCaret() }
            return event
        }
    }

    @objc private func resetOptionShortcut() { optionShortcut = MarkdownOptionShortcut() }

    override func resignFirstResponder() -> Bool {
        resetOptionShortcut()
        return super.resignFirstResponder()
    }

    private(set) var mechanical = true
    private(set) var paper = A4Paper(scale: 1)

    private func paperAttributes() -> [NSAttributedString.Key: Any] {
        let font = mechanical
            ? NSFontManager.shared.convert(TypewriterMetrics.font, toSize: TypewriterMetrics.font.pointSize * paper.scale)
            : NSFont.systemFont(ofSize: 15 * paper.scale)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = paper.lineHeight
        paragraph.maximumLineHeight = paper.lineHeight
        paragraph.tabStops = []
        paragraph.defaultTabInterval = paper.pitch * CGFloat(TypewriterMetrics.tabWidth)
        defaultParagraphStyle = paragraph
        return [.font: font, .foregroundColor: mechanical ? TypewriterPaper.typewriterInk : TypewriterPaper.ink, .paragraphStyle: paragraph, .ligature: 0]
    }

    func configurePaper(scale: CGFloat, mechanical: Bool) {
        guard paper.scale != scale || self.mechanical != mechanical else { return }
        guard scale.isFinite, scale > 0, let container = textContainer as? A4TextContainer else { return }
        breakUndoCoalescing()
        self.mechanical = mechanical
        insertionPointColor = mechanical ? TypewriterPaper.typewriterInk : TypewriterPaper.ink
        setAccessibilityLabel(mechanical ? "Foglio della macchina da scrivere" : "Scrittura normale")
        paper = A4Paper(scale: scale)
        container.paper = paper
        container.containerSize.width = mechanical ? 10_000_000 : paper.width - 2 * paper.horizontalMargin
        isHorizontallyResizable = mechanical
        if !mechanical {
            minSize.width = paper.width
            setFrameSize(NSSize(width: paper.width, height: frame.height))
        }
        let attributes = paperAttributes()
        textStorage?.addAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        typingAttributes = attributes
        layoutManager?.textContainerChangedGeometry(container)
        layoutManager?.ensureLayout(for: container)
        updatePaperExtent()
        sizeToFit()
    }

    var lastPage: Int {
        guard let layoutManager, let textContainer else { return 0 }
        let bottom = max(layoutManager.usedRect(for: textContainer).maxY, layoutManager.extraLineFragmentRect.maxY)
        return paper.pageIndex(at: max(0, bottom - 1))
    }

    func updatePaperExtent() {
        let top = textContainerInset.height - paper.verticalMargin
        let bottom = top + CGFloat(lastPage) * paper.pageStride + paper.height + 8
        let viewport = enclosingScrollView?.contentView.bounds.height ?? 0
        var extent = max(bottom, viewport)
        if mechanical, let layoutManager, let textContainer {
            let textEnd = max(layoutManager.usedRect(for: textContainer).maxY, layoutManager.extraLineFragmentRect.maxY)
            extent = max(extent, textContainerOrigin.y + textEnd + viewport / 2)
        }
        let size = NSSize(width: paper.width, height: extent)
        if minSize != size {
            minSize = size
            sizeToFit()
        }
    }

    override func didChangeText() {
        super.didChangeText()
        updatePaperExtent()
        enclosingScrollView?.contentView.needsDisplay = true
        followTypingLine()
    }

    func load(_ text: String, selection: NSRange) {
        let attributes = paperAttributes()
        textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes))
        typingAttributes = attributes
        newline = text.first(where: \.isNewline).map(String.init) ?? "\n"
        let end = (text as NSString).length
        let start = min(selection.location, end)
        setSelectedRange(NSRange(location: start, length: min(selection.length, end - start)))
        updatePaperExtent()
    }

    override func keyDown(with event: NSEvent) {
        guard mechanical else { super.keyDown(with: event); return }
        defer { followTypingLine() }
        guard event.modifierFlags.intersection([.command, .control]).isEmpty, isEditable else {
            super.keyDown(with: event)
            return
        }
        typing = true
        struckKey = false
        emptyBackspace = event.keyCode == 51 && selectedRange() == NSRange(location: 0, length: 0)
        super.keyDown(with: event)
        typing = false
        if emptyBackspace, !struckKey { sound(.backspace) }
    }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard let replacementString, typing, !hasMarkedText() else {
            return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
        }
        let lineFeed = replacementString.contains(where: \.isNewline)
        let column = TypewriterMetrics.column(in: string as NSString, at: affectedCharRange.location)
        let end = TypewriterMetrics.advancing(column, by: replacementString)
        if !marginReleased, !lineFeed, affectedCharRange.length == 0, !replacementString.isEmpty,
           end > TypewriterMetrics.columns {
            sound(.stop)
            return false
        }
        guard super.shouldChangeText(in: affectedCharRange, replacementString: replacementString) else { return false }
        struckKey = true
        if lineFeed { sound(.carriage) }
        else if replacementString.isEmpty { sound(.backspace) }
        else if replacementString == " " || replacementString == "\t" { sound(.space) }
        else {
            let strikes: [TypewriterSound] = [.key1, .key2, .key3]
            sound(strikes[nextStrike])
            nextStrike = (nextStrike + 1) % strikes.count
        }
        if !lineFeed, column < TypewriterMetrics.bellColumn, end >= TypewriterMetrics.bellColumn { sound(.bell) }
        return true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let selection = selectedRange()
        let menu = super.menu(for: event)?.copy() as? NSMenu ?? NSMenu()
        guard isEditable else { return menu }
        var target = selection
        if selection.length == 0, event.type == .rightMouseDown || event.type == .leftMouseDown {
            let point = convert(event.locationInWindow, from: nil)
            target = NSRange(location: characterIndexForInsertion(at: point), length: 0)
        }
        if !menu.items.isEmpty { menu.insertItem(.separator(), at: 0) }
        let markdown = markdownMenu(for: target)
        let item = NSMenuItem(title: markdown.title, action: nil, keyEquivalent: "")
        item.submenu = markdown
        menu.insertItem(item, at: 0)
        return menu
    }

    override func insertNewline(_ sender: Any?) {
        insertText(newline, replacementRange: selectedRange())
    }

    override func insertTab(_ sender: Any?) {
        insertText("\t", replacementRange: selectedRange())
    }

    var insertionOffset: Int {
        let selection = selectedRange()
        return selectionAffinity == .upstream ? selection.location : NSMaxRange(selection)
    }

    /// TextKit supplies the actual insertion position, including tabs, composed characters and page gaps.
    func caretRect(in clip: NSClipView) -> NSRect? {
        let offset = insertionOffset
        guard offset <= storage.length, let layoutManager, let textContainer else { return nil }
        if let window {
            let rect = firstRect(forCharacterRange: NSRange(location: offset, length: 0), actualRange: nil)
            if rect.height > 0 { return clip.convert(window.convertFromScreen(rect), from: nil) }
        }
        // AppKit's screen rect can be empty when the insertion point is outside the viewport.
        layoutManager.ensureLayout(for: textContainer)
        var line = layoutManager.extraLineFragmentRect
        var x = line.minX
        if offset < storage.length || (line.isEmpty && storage.length > 0) {
            let glyph = layoutManager.glyphIndexForCharacter(at: min(offset, storage.length - 1))
            line = layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            x = offset == storage.length ? line.maxX : line.minX + layoutManager.location(forGlyphAt: glyph).x
        }
        let rect = NSRect(x: textContainerOrigin.x + x, y: textContainerOrigin.y + line.minY,
                          width: 0, height: line.height > 0 ? line.height : paper.lineHeight)
        return clip.convert(rect, from: self)
    }

    func followTypingLine() {
        guard mechanical, let scroll = enclosingScrollView as? TypewriterScrollView else { return }
        scroll.scheduleRulerUpdate()
        let clip = scroll.contentView
        var viewport = clip.bounds
        guard viewport.width > 0, viewport.height > 0, let caret = caretRect(in: clip) else { return }
        let threshold = viewport.height * 2 / 3
        let step = min(3 * paper.lineHeight, viewport.height / 4)
        if caret.midY >= viewport.minY + threshold {
            viewport.origin.y = caret.midY - threshold + step
        } else if caret.minY < viewport.minY + TypewriterRuler.clearance {
            viewport.origin.y = caret.minY - TypewriterRuler.clearance
        }
        // A cropped sheet or an unlocked long line can extend beyond the window.
        let sideInset = min(viewport.width / 8, 4 * paper.pitch)
        if caret.minX < viewport.minX {
            viewport.origin.x = caret.minX - sideInset
        } else if caret.maxX >= viewport.maxX {
            viewport.origin.x = caret.maxX - viewport.width + sideInset
        }
        let origin = clip.constrainBoundsRect(viewport).origin
        guard origin != clip.bounds.origin else { return }
        clip.scroll(to: origin)
        scroll.reflectScrolledClipView(clip)
    }
}

final class TypewriterClipView: NSClipView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let editor = documentView as? TypewriterTextView else { return }
        let paper = editor.paper
        let origin = convert(NSPoint(x: 0, y: editor.textContainerOrigin.y - paper.verticalMargin), from: editor)
        let first = paper.pageIndex(at: dirtyRect.minY - origin.y - 14)
        let last = min(editor.lastPage, paper.pageIndex(at: dirtyRect.maxY - origin.y + 14))
        guard first <= last else { return }
        for page in first...last {
            let sheet = NSRect(x: origin.x, y: origin.y + CGFloat(page) * paper.pageStride,
                               width: paper.width, height: paper.height)
            drawSheet(sheet, mechanical: editor.mechanical)
        }
    }

    private func drawSheet(_ sheet: NSRect, mechanical: Bool) {
        let outline = NSBezierPath(roundedRect: sheet, xRadius: mechanical ? 1 : 7, yRadius: mechanical ? 1 : 7)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.19)
        shadow.shadowBlurRadius = 12
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        shadow.set()
        (mechanical ? TypewriterPaper.ivory : TypewriterPaper.sheet).setFill()
        outline.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.labelColor.withAlphaComponent(0.13).setStroke()
        outline.lineWidth = 0.7
        outline.stroke()
    }

    override func setBoundsOrigin(_ newOrigin: NSPoint) {
        super.setBoundsOrigin(newOrigin)
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        documentView?.needsDisplay = true
    }

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        if let editor = documentView as? TypewriterTextView, editor.paper.width <= bounds.width {
            let centered = editor.frame.minX + (editor.paper.width - bounds.width) / 2
            let right = editor.mechanical && editor.frame.width > editor.paper.width + 1
                ? max(centered, editor.frame.maxX - bounds.width) : centered
            bounds.origin.x = min(max(proposedBounds.minX, centered), right)
        }
        return bounds
    }
}

struct TypewriterRuler: Equatable {
    static let height: CGFloat = 35
    static let gap: CGFloat = 6
    static let clearance = height + gap + 8
    let caret: CGPoint
    let zeroX: CGFloat
}

@MainActor final class TypewriterScrollView: NSScrollView {
    let editor = TypewriterTextView()
    private var previousViewportSize = NSSize.zero
    var onFocus: ((TypewriterTextView) -> Void)?
    var onDisplayChange: ((PaperDisplay) -> Void)?
    var onRulerChange: ((TypewriterRuler?) -> Void)?
    private var rulerUpdateScheduled = false

    var rulerPosition: TypewriterRuler? {
        let clip = contentView
        guard editor.mechanical, let caret = editor.caretRect(in: clip),
              caret.maxY >= clip.bounds.minY, caret.minY <= clip.bounds.maxY else { return nil }
        let zero = clip.convert(editor.textContainerOrigin, from: editor)
        let offset = CGPoint(x: clip.frame.minX - clip.bounds.minX, y: clip.frame.minY - clip.bounds.minY)
        return TypewriterRuler(caret: CGPoint(x: caret.minX + offset.x, y: caret.minY + offset.y),
                               zeroX: zero.x + offset.x)
    }

    func scheduleRulerUpdate() {
        guard onRulerChange != nil, !rulerUpdateScheduled else { return }
        rulerUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.rulerUpdateScheduled = false
            self.onRulerChange?(self.rulerPosition)
        }
    }

    override func reflectScrolledClipView(_ clip: NSClipView) {
        super.reflectScrolledClipView(clip)
        scheduleRulerUpdate()
    }

    init() {
        super.init(frame: .zero)
        contentView = TypewriterClipView()
        contentView.drawsBackground = false
        drawsBackground = false
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
        documentView = editor
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let center = NotificationCenter.default
        center.removeObserver(self, name: NSWindow.didChangeScreenNotification, object: nil)
        center.removeObserver(self, name: NSWindow.didChangeBackingPropertiesNotification, object: nil)
        center.removeObserver(self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if let window {
            for name in [NSWindow.didChangeScreenNotification, NSWindow.didChangeBackingPropertiesNotification] {
                center.addObserver(self, selector: #selector(displayDidChange), name: name, object: window)
            }
            center.addObserver(self, selector: #selector(displayDidChange), name: NSApplication.didChangeScreenParametersNotification, object: nil)
            displayDidChange()
            if editor.isEditable { window.makeFirstResponder(editor) }
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, self.window === window, self.editor.isEditable else { return }
                window?.makeFirstResponder(self.editor)
                self.editor.followTypingLine()
                self.onFocus?(self.editor)
            }
        }
    }

    @objc private func displayDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let screen = self.window?.screen else { return }
            self.onDisplayChange?(PaperDisplay(screen: screen))
        }
    }

    func applyPaperScale(_ scale: CGFloat, mechanical: Bool = true) {
        guard editor.paper.scale != scale || editor.mechanical != mechanical else { return }
        editor.configurePaper(scale: scale, mechanical: mechanical)
        previousViewportSize = .zero
        needsLayout = true
        contentView.needsDisplay = true
    }

    override func layout() {
        super.layout()
        let height = contentView.bounds.height
        let paper = editor.paper
        let top = editor.mechanical
            ? max(8, height * 0.4 - paper.lineHeight / 2 - paper.verticalMargin)
            : max(8, (height - paper.height) / 2)
        let inset = NSSize(width: paper.horizontalMargin, height: ceil(top + paper.verticalMargin))
        if height > 0, editor.textContainerInset != inset || previousViewportSize != contentView.bounds.size {
            previousViewportSize = contentView.bounds.size
            editor.textContainerInset = inset
            editor.updatePaperExtent()
            if editor.mechanical {
                editor.followTypingLine()
            } else {
                editor.scrollRangeToVisible(editor.selectedRange())
            }
        }
        scheduleRulerUpdate()
    }
}
