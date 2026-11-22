import AppKit
import WebKit

struct VerificationError: Error, CustomStringConvertible { let description: String }

@main @MainActor final class TestRunner: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    static var runner: TestRunner!
    var web: WKWebView!
    var checks = 0
    var navigationContinuation: CheckedContinuation<Void, Error>?
    var activeHeadingID: String?
    var remainingSeconds: Int?

    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        runner = TestRunner()
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) {
            fputs("FAIL: WebKit verification timed out\n", stderr); exit(1)
        }
        Task { @MainActor in
            do {
                try runner.testDocuments()
                try runner.testWriting()
                try runner.testMarkdownMarkers()
                try runner.testMarkdownShortcut()
                try runner.testPhysicalPaper()
                if CommandLine.arguments.contains("--without-webkit") {
                    print("PASS: \(runner.checks) document and typewriter checks.")
                } else {
                    try await runner.testRenderer()
                    try await runner.testTableLayout()
                    try await runner.testOutlineTracking()
                    print("PASS: \(runner.checks) checks, including actual WebKit rendering.")
                }
                exit(0)
            } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
        }
        NSApp.run()
    }

    func testWriting() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Bozza.md")
        let draft = "# Una città\n\nCaffè ☕\n"
        let saved = try MarkdownDocument().write(draft, to: file)
        try check(try MarkdownDocument.read(file).text == draft, "Save a Markdown draft in UTF-8")
        let external = "# Versione esterna"
        try Data(external.utf8).write(to: file)
        do {
            _ = try saved.write("Bozza da proteggere", to: file)
            throw VerificationError(description: "Overwrote changes made by another editor")
        } catch DocumentError.changedOnDisk { checks += 1 }
        try check(try MarkdownDocument.read(file).text == external, "External changes survive a save conflict")

        let utf16 = Data([0xFE, 0xFF]) + draft.data(using: .utf16BigEndian)!
        try utf16.write(to: file)
        let legacy = try MarkdownDocument.read(file)
        let updated = try legacy.write(draft + "Fine.", to: file)
        try check(updated.encoding == "UTF-16" && updated.fileData?.starts(with: [0xFE, 0xFF]) == true,
                  "In-place save preserves UTF-16 byte order")
        let copy = try updated.write(updated.text, to: root.appendingPathComponent("Copia.md"))
        try check(copy.encoding == "UTF-8" && copy.text == updated.text, "Save As starts a UTF-8 file")

        let scroll = TypewriterScrollView()
        let editor = scroll.editor
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 500),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = scroll
        editor.load("", selection: NSRange(location: 0, length: 0))
        scroll.layoutSubtreeIfNeeded()
        window.makeFirstResponder(editor)
        var sounds: [TypewriterSound] = []
        editor.sound = { sounds.append($0) }
        func press(_ characters: String, keyCode: UInt16) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                         windowNumber: window.windowNumber, context: nil, characters: characters,
                                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
            editor.keyDown(with: event)
        }

        let clip = scroll.contentView
        func ruler() throws -> TypewriterRuler {
            guard let ruler = scroll.rulerPosition else { throw VerificationError(description: "Active line has no visible ruler") }
            return ruler
        }
        let initial = clip.bounds.origin
        let start = try ruler()
        try check(initial.x < 0 && abs(start.caret.x - start.zeroX) < 1, "Centered paper starts the index at zero")
        press("a", keyCode: 0)
        let first = try ruler()
        try check(clip.bounds.origin == initial && first.zeroX == start.zeroX && first.caret.y == start.caret.y,
                  "A keystroke leaves the sheet and ruler scale stationary")
        try check(abs(first.caret.x - start.caret.x - editor.paper.pitch) < 1, "The index advances by one character")
        press("\r", keyCode: 36)
        let nextRow = try ruler()
        try check(clip.bounds.origin == initial && editor.string == "a\n" && abs(nextRow.caret.x - nextRow.zeroX) < 1,
                  "Return brings the index to the margin without moving the sheet")
        try check(abs(nextRow.caret.y - start.caret.y - editor.paper.lineHeight) < 1, "The ruler follows the next row")

        var stationaryRows = 1
        while clip.bounds.origin == initial && stationaryRows < 30 {
            press("\r", keyCode: 36)
            if clip.bounds.origin == initial { stationaryRows += 1 }
        }
        let afterFeed = clip.bounds.origin
        try check(stationaryRows >= 2 && afterFeed.y - initial.y >= editor.paper.lineHeight * 2.9,
                  "The sheet waits several lines, then scrolls a few rows together")
        let after = try ruler()
        let beforeScrollMidY = after.caret.y + editor.paper.lineHeight / 2 + afterFeed.y - initial.y
        let threshold = clip.bounds.height * 2 / 3
        try check(beforeScrollMidY >= threshold - 1 && beforeScrollMidY < threshold + editor.paper.lineHeight + 1,
                  "The first feed occurs at two thirds of the writing area")
        press("a", keyCode: 0)
        press("\r", keyCode: 36)
        try check(clip.bounds.origin == afterFeed, "The paper rests again after scrolling")

        let beforeManualScroll = try ruler()
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: clip.bounds.minY + 30))
        let manual = try ruler()
        try check(abs(manual.caret.y - beforeManualScroll.caret.y + 30) < 1, "Manual scrolling moves the ruler with its row")
        let editableText = String(repeating: "Parola ", count: 26)
        let mark = NSRange(location: 30, length: 6)
        editor.load(editableText, selection: mark)
        scroll.applyPaperScale(1, mechanical: false)
        scroll.layoutSubtreeIfNeeded()
        try check(editor.string == editableText && editor.selectedRange() == mark, "Normal writing keeps the selection and draft")
        let layout = editor.layoutManager!
        layout.ensureLayout(for: editor.textContainer!)
        let wrapped = layout.lineFragmentRect(forGlyphAt: layout.numberOfGlyphs - 1, effectiveRange: nil)
        try check(wrapped.minY > 0, "Normal writing wraps a long paragraph")
        editor.setSelectedRange(NSRange(location: editableText.utf16.count, length: 0))
        let strikes = sounds.count
        press("a", keyCode: 0)
        try check(editor.string == editableText + "a" && sounds.count == strikes, "Normal writing is silent and continues beyond column 60")
        scroll.applyPaperScale(1, mechanical: true)
        scroll.layoutSubtreeIfNeeded()
        try check(editor.string == editableText + "a" && editor.selectedRange().location == editableText.utf16.count + 1,
                  "Switching back to the typewriter preserves the edit and insertion point")

        let bell = TypewriterMetrics.bellColumn
        let margin = TypewriterMetrics.columns
        editor.load(String(repeating: "a", count: bell - 1), selection: NSRange(location: bell - 1, length: 0))
        for _ in (bell - 1)...margin { press("a", keyCode: 0) }
        try check(editor.string.count == margin, "Typing stops at the right margin")
        try check(sounds.filter { $0 == .bell }.count == 1 && sounds.last == .stop, "Bell and margin stop have distinct sounds")
        press("\r", keyCode: 36)
        press("è", keyCode: 0)
        try check(editor.string.hasSuffix("\nè") && sounds.contains(.carriage), "Return feeds a line and accepts accented text")
        press("\u{7F}", keyCode: 51)
        try check(editor.string.hasSuffix("\n") && sounds.last == .backspace, "Backspace corrects the last strike")
        editor.load("a\tè\r\né", selection: NSRange(location: 6, length: 0))
        try check(TypewriterMetrics.column(in: editor.string as NSString, at: 3) == 9, "Tab and accent use fixed columns")
        try check(TypewriterMetrics.column(in: editor.string as NSString, at: 6) == 1, "CRLF starts a new column count")
        press("\r", keyCode: 36)
        try check(editor.string.hasSuffix("é\r\n"), "Return preserves existing CRLF line endings")

        editor.load(String(repeating: "a", count: margin), selection: NSRange(location: margin, length: 0))
        editor.marginReleased = true
        press("a", keyCode: 0)
        try check(editor.string.count == margin + 1, "The margin release allows a longer line")
        editor.load(String(repeating: "a", count: 180), selection: NSRange(location: 180, length: 0))
        editor.layoutManager?.ensureLayout(for: editor.textContainer!)
        editor.sizeToFit()
        try check(editor.frame.width > scroll.contentView.bounds.width, "Existing long lines remain horizontally scrollable")
        editor.followTypingLine()
        let farEnd = try ruler()
        try check((0..<clip.bounds.width).contains(farEnd.caret.x), "A long unlocked line reveals its insertion point")
        clip.scroll(to: NSPoint(x: clip.bounds.maxX, y: clip.bounds.minY + clip.bounds.height))
        try check(scroll.rulerPosition == nil, "Scrolling away to read hides the ruler of the offscreen line")
        press("\r", keyCode: 36)
        let marginAgain = try ruler()
        try check(abs(marginAgain.caret.x - marginAgain.zeroX) < 1 && marginAgain.caret.x >= 0,
                  "The next Return reveals the start of the new line after manual scrolling")
    }

    func testMarkdownMarkers() throws {
        func apply(_ marker: MarkdownMarker, to text: String, range: NSRange, newline: String = "\n") -> (String, String) {
            let edit = marker.edit(in: text as NSString, selection: range, newline: newline)
            let result = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
            return (result, (result as NSString).substring(with: edit.selection))
        }
        // Exercise every menu leaf for both empty documents and non-ASCII selections.
        func visit(_ entries: [MarkdownMenuEntry]) throws {
            for entry in entries {
                switch entry {
                case let .group(_, children): try visit(children)
                case let .item(title, marker):
                    let empty = apply(marker, to: "", range: NSRange(location: 0, length: 0))
                    let sample = "☕️ Città 🍎\r\nSeconda voce"
                    let range = NSRange(location: 0, length: sample.utf16.count)
                    let selected = apply(marker, to: sample, range: range, newline: "\r\n")
                    try check(!empty.0.isEmpty && !selected.0.isEmpty, "Menu insertion and selection ranges: " + title)
                }
            }
        }
        try visit(MarkdownMenuEntry.categories)
        let emphasis = apply(.inline("**", "testo", "**"), to: " città ", range: NSRange(location: 0, length: 7))
        try check(emphasis == (" **città** ", "città"), "Inline emphasis keeps selection spaces outside markers")
        let task = "- [ ] Luce"
        try check(apply(.lines("- [x] ", "Attività"), to: task, range: NSRange(location: 6, length: 0)).0 == "- [x] Luce",
                  "Checking an existing task replaces its marker")
        let list = "Prima\r\nSeconda\r\nTerza"
        try check(apply(.ordered(")"), to: list, range: NSRange(location: 0, length: 16), newline: "\r\n").0 ==
                  "1) Prima\r\n2) Seconda\r\nTerza", "Formatting selected lines preserves CRLF and the following line")
        let fence = "prima\n```\ndopo"
        try check(apply(.fence("`", language: ""), to: fence, range: NSRange(location: 0, length: fence.utf16.count)).0 ==
                  "````\n" + fence + "\n````", "Code fences grow around literal backticks")
        let table = "| Nome | Dato |\r\n| --- | --- |\r\n| A \\| B | C |"
        let aligned = apply(.alignment(":---:"), to: table, range: (table as NSString).range(of: "C"), newline: "\r\n").0
        try check(aligned == table.replacingOccurrences(of: "| --- | --- |", with: "| --- | :---: |"),
                  "Aligning a body cell changes the matching delimiter despite escaped pipes")
        let tsv = "Nome\tValore\nA|B\t3"
        try check(apply(.table, to: tsv, range: NSRange(location: 0, length: tsv.utf16.count)) ==
                  ("| Nome | Valore |\n| --- | --- |\n| A\\|B | 3 |", "Nome"), "Tabular text preserves cells and selects the header")
        try check(apply(.heading(3), to: "# Uno", range: NSRange(location: 3, length: 0)).0 == "### Uno",
                  "Heading levels replace the existing marker")
    }

    func testMarkdownShortcut() throws {
        func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags, type: NSEvent.EventType = .flagsChanged) -> NSEvent {
            NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0,
                             windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                             isARepeat: false, keyCode: code)!
        }
        func checkGesture(_ events: [NSEvent], opensOnLast: Bool, _ description: String) throws {
            var shortcut = MarkdownOptionShortcut()
            let results = events.map { shortcut.shouldOpen(on: $0) }
            try check(!results.dropLast().contains(true) && results.last == opensOnLast, description)
        }
        let press = key(58, .option), release = key(58, [])
        try checkGesture([press, release], opensOnLast: true, "Left Option opens on release")
        try checkGesture([key(61, [.capsLock, .option]), key(61, .capsLock)], opensOnLast: true, "Right Option works with Caps Lock")
        try checkGesture([press, key(123, .option, type: .keyDown), release], opensOnLast: false, "Option-arrow only moves the caret")
        try checkGesture([press, key(14, .option, type: .keyDown), release], opensOnLast: false, "Option characters do not open the menu")
        try checkGesture([press, key(55, [.command, .option]), key(55, .option), release], opensOnLast: false, "Releasing Command before Option does not trigger the menu")
        try checkGesture([press, key(61, .option), key(58, .option), key(61, [])], opensOnLast: false, "Holding both Option keys is not a solo tap")
        let click = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: .option, timestamp: 0,
                                       windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        try checkGesture([press, click, release], opensOnLast: false, "Option-click does not trigger the menu")
        try checkGesture([release], opensOnLast: false, "Focus gained while Option is held does not trigger the menu")

        let editor = TypewriterTextView()
        let selected = NSRange(location: 4, length: 5)
        editor.load("Una città", selection: selected)
        let menu = editor.markdownMenu(for: selected)
        let titles = MarkdownMenuEntry.categories.compactMap { entry -> String? in
            if case let .group(title, _) = entry { return title }
            return nil
        }
        try check(menu.items.map(\.title) == titles, "Keyboard menu starts with just the Markdown categories")
        guard let styles = menu.item(withTitle: "Stile del testo")?.submenu else {
            throw VerificationError(description: "Missing style submenu")
        }
        styles.performActionForItem(at: 0)
        try check(editor.string == "Una **città**", "Menu action formats the original selection")
    }

    func testPhysicalPaper() throws {
        var display = PaperDisplay()
        display.points = CGSize(width: 1800, height: 1200)
        display.millimetres = CGSize(width: 360, height: 240)
        let scroll = TypewriterScrollView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = scroll
        let editor = scroll.editor
        let clip = scroll.contentView
        func displayedSheet() -> NSRect {
            clip.convert(NSRect(x: 0, y: 0, width: editor.paper.width, height: editor.paper.height), to: nil)
        }
        scroll.applyPaperScale(display.magnification)
        scroll.layoutSubtreeIfNeeded()
        try check(abs(displayedSheet().width - 1050) < 0.1 && abs(displayedSheet().height - 1485) < 0.1,
                  "The drawn sheet measures 210 × 297 mm at five logical points per mm")
        try check(displayedSheet().width > scroll.bounds.width, "A narrow window crops rather than shrinks the sheet")
        window.setContentSize(NSSize(width: 1500, height: 900))
        scroll.layoutSubtreeIfNeeded()
        try check(abs(displayedSheet().width - 1050) < 0.1, "A window resize preserves physical scale")
        editor.load("Prima riga", selection: NSRange(location: 10, length: 0))
        let normalOrigin = editor.frame.origin
        editor.setFrameOrigin(NSPoint(x: normalOrigin.x, y: -480))
        editor.followTypingLine()
        let firstLine = clip.convert(editor.textContainerOrigin, from: editor)
        try check(clip.bounds.minY <= firstLine.y && firstLine.y + editor.paper.lineHeight <= clip.bounds.maxY,
                  "The first typed line remains visible when AppKit offsets the document frame")
        editor.setFrameOrigin(normalOrigin)
        display.points = CGSize(width: 1200, height: 1800)
        try check(abs(TypewriterMetrics.paperWidth * display.magnification - 1050) < 0.1, "Portrait display with unrotated EDID")
        display.diagonalInches = display.diagonalForReference(measuredMM: 48, referencePoints: 240)
        display.millimetres = .zero
        try check(abs(TypewriterMetrics.paperWidth * display.magnification - 1050) < 0.1, "The measured ruler calibrates a display with no physical data")
        let rowsPerPage = Int((editor.paper.height - 2 * editor.paper.verticalMargin) / editor.paper.lineHeight)
        let text = String(repeating: "Riga\n", count: rowsPerPage)
        editor.load(text, selection: NSRange(location: text.utf16.count, length: 0))
        let layout = editor.layoutManager!
        let container = editor.textContainer!
        layout.ensureLayout(for: container)
        try check(abs(layout.extraLineFragmentRect.minY - editor.paper.pageStride) < 1, "The insertion point after the last row starts on the next sheet")
        editor.insertText("È", replacementRange: editor.selectedRange())
        layout.ensureLayout(for: container)
        let last = layout.lineFragmentRect(forGlyphAt: layout.numberOfGlyphs - 1, effectiveRange: nil)
        try check(abs(last.minY - editor.paper.pageStride) < 1 && editor.string == text + "È", "Page feed preserves the exact Markdown text")
        let bottom = editor.textContainerOrigin.y - editor.paper.verticalMargin + editor.paper.pageStride + editor.paper.height
        let requested = clip.bounds.offsetBy(dx: 0, dy: 100_000)
        try check(clip.constrainBoundsRect(requested).maxY >= bottom - 1, "The bottom edge of the last sheet can be reached")
        let selection = editor.selectedRange()
        display.points = CGSize(width: 900, height: 1350)
        scroll.applyPaperScale(display.magnification)
        scroll.layoutSubtreeIfNeeded()
        try check(abs(displayedSheet().width - 787.5) < 0.1 && editor.selectedRange() == selection && editor.string == text + "È",
                  "Changing display scale resizes the existing sheet and preserves selection and text")
    }

    func check(_ condition: Bool, _ description: String) throws {
        guard condition else { throw VerificationError(description: description) }
        checks += 1
    }

    func testDocuments() throws {
        let text = "# Caffè ☕\n\nUna città, un’idea."
        try check(try MarkdownDocument.decode(Data(("\u{FEFF}" + text).utf8)).0 == text, "UTF-8 BOM")
        try check(try MarkdownDocument.decode(text.data(using: .utf16)!).0 == text, "UTF-16 BOM")
        do { _ = try MarkdownDocument.decode(Data([0, 1, 0, 2])); throw VerificationError(description: "Binary accepted") }
        catch is DocumentError { checks += 1 }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Appunti.md")
        try "Ciao mondo\n\nUna nuova idea".write(to: file, atomically: true, encoding: .utf8)
        let document = try MarkdownDocument.read(file)
        try check(document.title == "Appunti" && document.wordCount == 5 && document.readingSeconds == 2, "File metadata and reading estimate")
        try check(MarkdownDocument().readingSeconds == 0, "Empty document has no reading time")
        try check(document.encoding == "UTF-8" && document.modified != nil, "Encoding and modification date")
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(MarkdownDocument.maximumBytes + 1)); try handle.close()
        do { _ = try MarkdownDocument.read(file); throw VerificationError(description: "Oversized file accepted") }
        catch is DocumentError { checks += 1 }

        let folder = URL(fileURLWithPath: "/tmp/carta-test-docs")
        try check(AssetAccess.resolve(URL(string: "carta-asset://local/tmp/carta-test-docs/images/test.png")!, inside: folder) != nil, "Local image")
        for path in ["/tmp/carta-test-docs/../private.png", "/tmp/carta-test-docs-neighbor/test.png", "/tmp/carta-test-docs/secret.txt"] {
            try check(AssetAccess.resolve(URL(string: "carta-asset://local" + path)!, inside: folder) == nil, "Image access: \(path)")
        }
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try Data([1]).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        let link = root.appendingPathComponent("escape.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        var request = URLComponents(); request.scheme = "carta-asset"; request.host = "local"; request.path = link.path
        try check(AssetAccess.resolve(request.url!, inside: root) == nil, "Symlink escape")
    }

    func testRenderer() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        func resource(_ name: String) throws -> String { try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8) }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(self, name: "carta")
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700), configuration: configuration)
        web.navigationDelegate = self
        let html = try resource("reader.html")
            .replacingOccurrences(of: "/* MARKED_LIBRARY */", with: resource("vendor/marked.js"))
            .replacingOccurrences(of: "/* PURIFY_LIBRARY */", with: resource("vendor/purify.js"))
            .replacingOccurrences(of: "/* READER_SCRIPT */", with: resource("reader.js"))
            .replacingOccurrences(of: "/* READER_STYLES */", with: resource("reader.css"))
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            navigationContinuation = continuation
            web.loadHTMLString(html, baseURL: nil)
        }
        let fixture = """
        # Caffè & idee
        ## Ripetuto
        ## Ripetuto
        ## Ripetuto-1

        | Nome | Stato |
        | --- | --- |
        | Carta | Pronta |

        - [x] Fatto

        ```swift
        let saluto = "Ciao"
        ```

        **grassetto** e *corsivo*

        [Capitolo](secondo.md)

        <script>window.compromised = true</script>
        <img src="bad:" onerror="window.compromised = true">
        <a href="javascript:window.compromised=true">male</a>
        <iframe src="https://example.com"></iframe>
        """
        let payload: [String: Any] = ["text": fixture, "readingSeconds": 90, "theme": "paper", "fontSize": 18, "source": false,
                                      "documentID": "test", "documentURL": "file:///tmp/test.md", "assetBase": "carta-asset://local/tmp/"]
        _ = try await web.callAsyncJavaScript("Carta.render(payload)", arguments: ["payload": payload], in: nil, contentWorld: .page)
        let result = try await web.evaluateJavaScript("""
        ({headings:[...document.querySelectorAll('h1,h2')].map(e=>e.id), tables:document.querySelectorAll('table').length,
          strong:document.querySelector('strong').textContent, code:document.querySelector('pre code').textContent,
          unsafe:document.querySelectorAll('#reader script,#reader iframe,[onerror],a[href^="javascript:"]').length,
          compromised:!!window.compromised, checkbox:document.querySelector('input').disabled,
          link:document.querySelector('a').href, theme:document.documentElement.dataset.theme})
        """) as! [String: Any]
        try check(result["headings"] as? [String] == ["caffè-idee", "ripetuto", "ripetuto-1", "ripetuto-1-1"], "Heading IDs including duplicates")
        try check(result["tables"] as? Int == 1, "GFM table")
        try check(result["strong"] as? String == "grassetto", "Bold text")
        try check((result["code"] as? String)?.contains("let saluto") == true, "Fenced code")
        try check(result["unsafe"] as? Int == 0, "Unsafe HTML removed")
        try check(result["compromised"] as? Bool == false, "Scripts never executed")
        try check(result["checkbox"] as? Bool == true, "Read-only checkbox")
        try check(result["link"] as? String == "file:///tmp/secondo.md", "Relative Markdown link")
        try check(result["theme"] as? String == "paper", "Paper theme")
        let found = try await web.find("grassetto", configuration: WKFindConfiguration())
        try check(found.matchFound, "Native document search")
        var source = payload; source["source"] = true
        _ = try await web.callAsyncJavaScript("Carta.render(payload)", arguments: ["payload": source], in: nil, contentWorld: .page)
        let sourceText = try await web.evaluateJavaScript("document.querySelector('.source-content').textContent") as? String
        try check(sourceText == fixture, "Source displays original text")
        let scripts = try await web.evaluateJavaScript("document.querySelectorAll('#reader script').length") as? Int
        try check(scripts == 0, "Source mode cannot execute scripts")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationContinuation?.resume(); navigationContinuation = nil
    }

    func testTableLayout() async throws {
        let fixture = """
        # Tabella con sei colonne

        Un paragrafo mantiene una larghezza comoda per la lettura.

        | Ruolo | Obiettivo | Club attuale | Tetto provvisorio | Elemento a favore | Rischio da considerare |
        | :--- | --- | :---: | ---: | --- | --- |
        | O | **Giulia Rossi** | Milano | **23** | Molti punti e numerosi attacchi nello storico; riferimento per il capitano | Nuovo allenatore e concorrenza nel reparto; impiego da controllare partita per partita |
        | S | **Anna Verdi** | Vallefoglia | **14** | Continuità di impiego e buoni risultati durante la preparazione | Verificare la disponibilità e la concorrenza delle alternative nel ruolo |
        """
        for (width, fontSize) in [(900, 17), (530, 17), (900, 24), (1500, 17)] {
            web.setFrameSize(NSSize(width: width, height: 700))
            let payload: [String: Any] = ["text": fixture, "readingSeconds": 30, "theme": "dark", "fontSize": fontSize, "source": false,
                                          "documentID": "table-layout", "documentURL": "file:///tmp/table.md", "assetBase": "carta-asset://local/tmp/"]
            _ = try await web.callAsyncJavaScript("Carta.render(payload)", arguments: ["payload": payload], in: nil, contentWorld: .page)
            let metrics = try await web.evaluateJavaScript("""
            (() => {
              const table = document.querySelector('table'), wrapper = table.parentElement;
              const role = table.querySelector('th'), club = table.querySelector('tbody tr td:nth-child(3)');
              const textHeight = element => { const range = document.createRange(); range.selectNodeContents(element); return range.getBoundingClientRect().height; };
              const rect = wrapper.getBoundingClientRect();
              wrapper.scrollLeft = 10000;
              return {
                roleOnOneLine: textHeight(role) <= parseFloat(getComputedStyle(role).lineHeight) * 1.1,
                clubOnOneLine: textHeight(club) <= parseFloat(getComputedStyle(club).lineHeight) * 1.1,
                numericAlignment: getComputedStyle(table.querySelector('tbody tr td:nth-child(4)')).textAlign,
                centerAlignment: getComputedStyle(club).textAlign,
                pageFits: document.documentElement.scrollWidth <= innerWidth + 1 && rect.left >= -1 && rect.right <= innerWidth + 1,
                tableWidth: rect.width, proseWidth: document.querySelector('p').getBoundingClientRect().width,
                scrollable: wrapper.scrollLeft > 0
              };
            })()
            """) as! [String: Any]
            let context = "(viewport \(width), font \(fontSize))"
            try check(metrics["roleOnOneLine"] as? Bool == true, "Table heading must not split into letters \(context)")
            try check(metrics["clubOnOneLine"] as? Bool == true, "Short table values must not split into letters \(context)")
            try check(metrics["numericAlignment"] as? String == "right", "Markdown right alignment \(context)")
            try check(metrics["centerAlignment"] as? String == "center", "Markdown center alignment \(context)")
            try check(metrics["pageFits"] as? Bool == true, "Table overflow must stay inside its scroll area \(context)")
            if width >= 900 {
                try check((metrics["tableWidth"] as! Double) > (metrics["proseWidth"] as! Double), "Wide tables use available window width \(context)")
            } else {
                try check(metrics["scrollable"] as? Bool == true, "Wide table can scroll horizontally in a narrow window")
            }
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error); navigationContinuation = nil
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        if let id = body["activeHeadingID"] { activeHeadingID = id as? String }
        if let seconds = body["remainingSeconds"] as? Int { remainingSeconds = seconds }
    }

    func testOutlineTracking() async throws {
        func expectActive(_ id: String?) async throws {
            for _ in 0..<100 {
                if activeHeadingID == id { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            try check(activeHeadingID == id, "Active outline heading: expected \(id ?? "none"), got \(activeHeadingID ?? "none")")
        }
        func evaluate(_ script: String) async throws {
            _ = try await web.evaluateJavaScript(script)
        }
        func expectTime(_ range: ClosedRange<Int>) async throws {
            for _ in 0..<100 {
                if let seconds = remainingSeconds, range.contains(seconds) { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            try check(range.contains(remainingSeconds ?? -1), "Remaining reading time should be in \(range), got \(String(describing: remainingSeconds))")
        }

        // WebKit suspends animation frames when the view is detached from a window.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 500),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = web
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        let paragraphs = String(repeating: "Una riga di testo per scorrere il documento.\n\n", count: 28)
        let fixture = "# Inizio\n\n\(paragraphs)## Seconda\n\n\(paragraphs)### Sottosezione\n\n\(paragraphs)## Quasi fine\n\n## Fine\n\nUltima riga."
        var payload: [String: Any] = ["text": fixture, "readingSeconds": 240, "theme": "light", "fontSize": 17, "source": false,
                                      "documentID": "outline", "documentURL": "", "assetBase": "carta-asset://local/tmp/"]
        _ = try await web.callAsyncJavaScript("Carta.render(payload)", arguments: ["payload": payload], in: nil, contentWorld: .page)
        try await expectActive("inizio")
        try await expectTime(240...240)
        try await evaluate("window.scrollTo(0, window.scrollY + document.getElementById('seconda').getBoundingClientRect().top + 80)")
        try await expectActive("seconda")
        try await expectTime(1...239)
        try await evaluate("Carta.scrollTo('sottosezione')")
        try await expectActive("sottosezione")
        try await Task.sleep(nanoseconds: 450_000_000)
        let jumpPosition = try await web.evaluateJavaScript("document.getElementById('sottosezione').getBoundingClientRect().top") as? Double
        try check(abs((jumpPosition ?? -1000) - 60) < 3, "Outline navigation reaches the selected subsection")
        try await expectTime(1...120)
        try await evaluate("window.scrollTo(0, 0)")
        try await expectActive("inizio")
        try await expectTime(240...240)
        try await evaluate("window.scrollTo(0, document.documentElement.scrollHeight)")
        try await expectActive("fine")
        try await expectTime(0...0)
        try await evaluate("Carta.scrollTo('quasi-fine')")
        try await expectActive("quasi-fine")
        try await Task.sleep(nanoseconds: 180_000_000)
        try check(activeHeadingID == "quasi-fine", "Click remains selected when two headings share the bottom scroll position")
        payload["source"] = true
        _ = try await web.callAsyncJavaScript("Carta.render(payload)", arguments: ["payload": payload], in: nil, contentWorld: .page)
        try await expectActive(nil)
        try await evaluate("window.scrollTo(0, 0)")
        try await expectTime(240...240)
        payload["text"] = "Una riga senza titolo."
        payload["documentID"] = "short-document"
        payload["readingSeconds"] = 2
        payload["source"] = false
        _ = try await web.callAsyncJavaScript("Carta.render(payload)", arguments: ["payload": payload], in: nil, contentWorld: .page)
        try await expectTime(2...2)
    }
}
