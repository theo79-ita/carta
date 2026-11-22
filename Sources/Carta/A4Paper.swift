import AppKit
import CoreGraphics
import IOKit.graphics
import Darwin

/// All dimensions are expressed in the same AppKit coordinate system as
/// the text view. Scrolling and window resizing never change their scale.
struct A4Paper {
    static let widthMM: CGFloat = 210
    static let heightMM: CGFloat = 297
    let scale: CGFloat
    var width: CGFloat { TypewriterMetrics.paperWidth * scale }
    var height: CGFloat { width * Self.heightMM / Self.widthMM }
    var verticalMargin: CGFloat { width * 18 / Self.widthMM }
    var horizontalMargin: CGFloat { TypewriterMetrics.margin * scale }
    var pitch: CGFloat { TypewriterMetrics.pitch * scale }
    var lineHeight: CGFloat { (TypewriterMetrics.lineHeight * scale).rounded() }
    var pageStride: CGFloat { ceil(height) + 14 }

    func pageIndex(at offset: CGFloat) -> Int {
        max(0, Int(floor(offset / pageStride)))
    }
}

struct PaperDisplay: Equatable {
    var name = ""
    var preferenceKey: String?
    var points = CGSize.zero
    var millimetres = CGSize.zero
    var diagonalInches: Double?

    @MainActor init(screen: NSScreen? = nil) {
        guard let screen, let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return }
        let id = CGDirectDisplayID(number.uint32Value)
        name = screen.localizedName
        points = screen.frame.size
        millimetres = CGDisplayScreenSize(id)
        if CGDisplayIsBuiltin(id) != 0, let panel = Self.builtInPanelSize(id) {
            millimetres = panel
        }
        if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
            let key = "A4.diagonal." + (CFUUIDCreateString(nil, uuid) as String)
            preferenceKey = key
            diagonalInches = UserDefaults.standard.object(forKey: key) as? Double
        }
    }

    private static func builtInPanelSize(_ display: CGDirectDisplayID) -> CGSize? {
        // The 16-inch November 2023 panel is physically 345.6 × 223.4 mm,
        // including the menu-bar region. The logical resolution can vary.
        if ["Mac15,7", "Mac15,9", "Mac15,11"].contains(hardwareModel) {
            return CGSize(width: 345.6, height: 223.4)
        }
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        let modes = CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode] ?? []
        for mode in modes where mode.ioFlags & UInt32(kDisplayModeNativeFlag) != 0 {
            let pixels = CGSize(width: mode.pixelWidth, height: mode.pixelHeight)
            if pixels == CGSize(width: 3456, height: 2234) || pixels == CGSize(width: 3024, height: 1964) {
                // Both of these Liquid Retina XDR panels have 254 physical pixels/inch.
                return CGSize(width: pixels.width / 10, height: pixels.height / 10)
            }
        }
        return nil
    }

    private static let hardwareModel: String = {
        var length = 0
        guard sysctlbyname("hw.model", nil, &length, nil, 0) == 0, length > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: length)
        guard sysctlbyname("hw.model", &buffer, &length, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }()

    func diagonalForReference(measuredMM: Double, referencePoints: CGFloat) -> Double? {
        guard measuredMM.isFinite, measuredMM > 0, referencePoints > 0, points.width > 0, points.height > 0 else { return nil }
        return measuredMM * hypot(points.width, points.height) / (referencePoints * 25.4)
    }

    var magnification: CGFloat {
        let density: CGFloat
        if let inches = diagonalInches, inches.isFinite, inches > 0, points.width > 0, points.height > 0 {
            density = hypot(points.width, points.height) / (inches * 25.4)
        } else if points.width > 0, millimetres.width > 0, millimetres.height > 0 {
            // Some drivers return the unrotated EDID dimensions on a portrait display.
            let swapped = (points.width > points.height) != (millimetres.width > millimetres.height)
            density = points.width / (swapped ? millimetres.height : millimetres.width)
        } else {
            density = 72 / 25.4
        }
        return A4Paper.widthMM * density / TypewriterMetrics.paperWidth
    }
}

/// Keep the same editable text storage across sheets. The printable area
/// starts at y = 0 in container coordinates, after the first top margin.
final class A4TextContainer: NSTextContainer {
    var paper = A4Paper(scale: 1)
    override var isSimpleRectangularTextContainer: Bool { false }

    override func lineFragmentRect(forProposedRect proposed: NSRect, at index: Int,
                                   writingDirection direction: NSWritingDirection,
                                   remaining remainder: NSRectPointer?) -> NSRect {
        var rect = proposed
        let offset = rect.minY.truncatingRemainder(dividingBy: paper.pageStride)
        let printableHeight = paper.height - 2 * paper.verticalMargin
        if offset + max(rect.height, paper.lineHeight) > printableHeight {
            rect.origin.y += paper.pageStride - offset
        }
        return super.lineFragmentRect(forProposedRect: rect, at: index, writingDirection: direction, remaining: remainder)
    }
}

@MainActor final class PaperCalibrationView: NSView {
    private let display: PaperDisplay
    private let method = NSPopUpButton()
    let field = NSTextField()
    private let referencePoints: CGFloat = 240

    init(display: PaperDisplay) {
        self.display = display
        super.init(frame: NSRect(x: 0, y: 0, width: 310, height: 84))
        method.addItems(withTitles: [L10n.text("paper.rulerMethod"), L10n.text("paper.diagonalMethod")])
        method.frame = NSRect(x: 0, y: 42, width: 220, height: 26)
        method.target = self
        method.action = #selector(changeMethod)
        field.frame = NSRect(x: 224, y: 43, width: 76, height: 24)
        addSubview(method)
        addSubview(field)
        changeMethod()
    }

    required init?(coder: NSCoder) { nil }

    var selectedDiagonal: Double? {
        let input = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let number = Double(input) else { return nil }
        if method.indexOfSelectedItem == 1 { return number }
        return display.diagonalForReference(measuredMM: number, referencePoints: referencePoints)
    }

    @objc private func changeMethod() {
        let useRuler = method.indexOfSelectedItem == 0
        field.stringValue = ""
        field.placeholderString = useRuler ? "mm" : L10n.text("paper.inches")
        if !useRuler, let inches = display.diagonalInches {
            field.stringValue = inches.formatted(.number.precision(.fractionLength(0...3)))
        }
        field.setAccessibilityLabel(useRuler ? L10n.text("paper.rulerLabel") : L10n.text("paper.diagonalLabel"))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard method.indexOfSelectedItem == 0 else { return }
        let line = NSBezierPath()
        let start: CGFloat = 12
        for x in [start, start + referencePoints] {
            line.move(to: NSPoint(x: x, y: 12))
            line.line(to: NSPoint(x: x, y: 28))
        }
        line.move(to: NSPoint(x: start, y: 20))
        line.line(to: NSPoint(x: start + referencePoints, y: 20))
        NSColor.labelColor.setStroke()
        line.stroke()
    }
}
