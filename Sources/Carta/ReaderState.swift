import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum CartaMode: String, CaseIterable, Identifiable {
    case reading, normal, typewriter
    var id: Self { self }
    var label: String {
        switch self {
        case .reading: return "Lettura"
        case .normal: return "Scrittura normale"
        case .typewriter: return "Macchina da scrivere"
        }
    }
    var isWriting: Bool { self != .reading }
    var icon: String {
        switch self {
        case .reading: return "book"
        case .normal: return "pencil"
        case .typewriter: return "keyboard"
        }
    }
}

enum ReadingTheme: String, CaseIterable, Identifiable {
    case system, light, dark, paper
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "Automatico"
        case .light: return "Chiaro"
        case .dark: return "Scuro"
        case .paper: return "Carta"
        }
    }
    var scheme: ColorScheme? { self == .dark ? .dark : (self == .system ? nil : .light) }
}

@MainActor final class ReaderState: ObservableObject {
    static let shared = ReaderState()
    @Published private(set) var document: MarkdownDocument
    @Published private(set) var mode: CartaMode = .reading
    private var lastWritingMode: CartaMode = .normal
    @Published private(set) var draft: String?
    @Published private(set) var editorSession = UUID()
    @Published private(set) var editorColumn = 0
    @Published private(set) var paperDisplay = PaperDisplay()
    @Published var marginReleased = false
    @Published var typewriterSound: Bool {
        didSet { UserDefaults.standard.set(typewriterSound, forKey: "typewriterSound") }
    }
    private(set) var editorSelection = NSRange(location: 0, length: 0)
    var editingText: String { draft ?? document.text }
    var readingDocument: MarkdownDocument { draft.map(document.replacingText) ?? document }
    var hasUnsavedChanges: Bool { draft != nil }
    var canReload: Bool { mode == .reading && document.url != nil && !isLoading }
    @Published var recentURLs: [URL] = []
    @Published var isLoading = false
    @Published var isDropTarget = false
    @Published var errorMessage: String?
    @Published var sidebarVisible = true
    @Published var sourceVisible = false
    @Published var searchVisible = false
    @Published var searchText = ""
    @Published var searchResult = ""
    @Published var theme: ReadingTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "readingTheme") }
    }
    @Published var fontSize: Int {
        didSet { UserDefaults.standard.set(fontSize, forKey: "fontSize") }
    }
    let web = WebActions()
    let outline = ReadingOutline()
    var documentID: String { document.url?.path ?? editorSession.uuidString }
    private var timer: Timer?
    private var loadID = UUID()
    private struct FileStamp: Equatable {
        let modified: Date
        let bytes: Int
    }
    private var lastObservedStamp: FileStamp?

    init() {
        document = Self.welcomeDocument()
        theme = ReadingTheme(rawValue: UserDefaults.standard.string(forKey: "readingTheme") ?? "") ?? .system
        typewriterSound = UserDefaults.standard.object(forKey: "typewriterSound") as? Bool ?? true
        let savedSize = UserDefaults.standard.integer(forKey: "fontSize")
        fontSize = savedSize == 0 ? 17 : min(24, max(13, savedSize))
        recentURLs = (UserDefaults.standard.stringArray(forKey: "recentFiles") ?? []).map { URL(fileURLWithPath: $0) }
        timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkForChanges() }
        }
    }

    private static func welcomeDocument() -> MarkdownDocument {
        let welcome = (try? String(contentsOf: Resource.url("Welcome.md"), encoding: .utf8)) ?? "# Benvenuto in Carta"
        return MarkdownDocument(text: welcome, isWelcome: true)
    }

    func selectMode(_ selected: CartaMode) {
        guard !isLoading, mode != selected else { return }
        if selected.isWriting {
            lastWritingMode = selected
            if document.isWelcome { replaceDocument(with: MarkdownDocument()) }
            searchVisible = false
        }
        mode = selected
    }

    func newDocument() {
        guard confirmLeavingDocument() else { return }
        loadID = UUID()
        isLoading = false
        replaceDocument(with: MarkdownDocument())
        selectMode(lastWritingMode)
    }

    func updateDraft(_ text: String) {
        guard !isLoading else { return }
        let wasEdited = hasUnsavedChanges
        let unchanged = text.utf8.count == document.text.utf8.count && text.utf8.elementsEqual(document.text.utf8)
        draft = unchanged ? nil : text
        if wasEdited != hasUnsavedChanges { updateWindow() }
    }

    func usePaperDisplay(_ display: PaperDisplay) {
        if paperDisplay != display { paperDisplay = display }
    }

    func calibratePaper() {
        guard let window = documentWindow, let screen = window.screen else { return }
        let display = PaperDisplay(screen: screen)
        guard let key = display.preferenceKey else { return }
        let alert = NSAlert()
        alert.messageText = "Calibra il foglio A4"
        alert.informativeText = "Schermo: \(display.name). Misura con un righello la distanza fra le due tacche e inseriscila in millimetri. Puoi anche scegliere la diagonale del monitor."
        let controls = PaperCalibrationView(display: display)
        alert.accessoryView = controls
        alert.addButton(withTitle: "Applica")
        alert.addButton(withTitle: "Annulla")
        alert.addButton(withTitle: "Usa misura automatica")
        alert.window.initialFirstResponder = controls.field
        alert.beginSheetModal(for: window) { [weak self, weak window] result in
            guard let self, result != .alertSecondButtonReturn, let screen = window?.screen else { return }
            var current = PaperDisplay(screen: screen)
            guard current.preferenceKey == key, current.points == display.points else {
                self.errorMessage = "Lo schermo è cambiato. Riapri la calibrazione sullo schermo da misurare."
                return
            }
            switch result {
            case .alertFirstButtonReturn:
                guard let inches = controls.selectedDiagonal, (1...1000).contains(inches) else {
                    self.errorMessage = "Inserisci una misura positiva, usando la virgola o il punto per i decimali."
                    return
                }
                current.diagonalInches = inches
                UserDefaults.standard.set(inches, forKey: key)
            case .alertThirdButtonReturn:
                current.diagonalInches = nil
                UserDefaults.standard.removeObject(forKey: key)
            default:
                return
            }
            self.usePaperDisplay(current)
        }
    }

    func updateEditorSelection(_ selection: NSRange, insertion: Int, in text: NSString) {
        editorSelection = selection
        let column = TypewriterMetrics.column(in: text, at: insertion)
        if editorColumn != column { editorColumn = column }
    }

    func discardDraft() {
        draft = nil
        updateWindow()
    }

    @discardableResult func save(asCopy: Bool = false) -> Bool {
        guard !isLoading, !document.isWelcome else { return false }
        let destination: URL
        if let url = document.url, !asCopy {
            guard hasUnsavedChanges else { return true }
            destination = url
        } else {
            let panel = NSSavePanel()
            panel.title = "Salva il documento"
            panel.nameFieldStringValue = document.filename
            panel.directoryURL = document.url?.deletingLastPathComponent()
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, .plainText]
            panel.allowsOtherFileTypes = true
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            destination = url
        }
        do {
            document = try document.write(editingText, to: destination)
            draft = nil
            lastObservedStamp = fileStamp(destination)
            noteRecent(destination)
            updateWindow()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func confirmLeavingDocument() -> Bool {
        guard hasUnsavedChanges else { return true }
        let alert = NSAlert()
        alert.messageText = "Salvare le modifiche a «\(document.filename)»?"
        alert.informativeText = "Le modifiche andranno perse se continui senza salvare."
        alert.addButton(withTitle: "Salva")
        alert.addButton(withTitle: "Annulla").keyEquivalent = "\u{1b}"
        alert.addButton(withTitle: "Non salvare")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return save()
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "Apri un file Markdown"
        panel.allowedContentTypes = MarkdownDocument.extensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL, automatic: Bool = false) {
        guard url.isFileURL else { return }
        if !automatic, !confirmLeavingDocument() { return }
        let requestID = UUID()
        loadID = requestID
        isLoading = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try MarkdownDocument.read(url) }
            }.value
            guard loadID == requestID else { return }
            isLoading = false
            switch result {
            case .success(let loaded):
                replaceDocument(with: loaded, resetNavigation: document.url != url || hasUnsavedChanges)
                if !automatic { noteRecent(url) }
            case .failure(let error):
                if !automatic { errorMessage = error.localizedDescription }
            }
        }
    }

    func showWelcome() {
        guard confirmLeavingDocument() else { return }
        loadID = UUID()
        isLoading = false
        mode = .reading
        replaceDocument(with: Self.welcomeDocument())
    }

    private func replaceDocument(with replacement: MarkdownDocument, resetNavigation: Bool = true) {
        document = replacement
        draft = nil
        lastObservedStamp = replacement.modified.flatMap { date in
            replacement.fileData.map { FileStamp(modified: date, bytes: $0.count) }
        }
        editorSession = UUID()
        editorSelection = NSRange(location: 0, length: 0)
        editorColumn = 0
        marginReleased = false
        if resetNavigation {
            outline.replaceItems([])
            searchText = ""
            searchResult = ""
        }
        updateWindow()
    }

    private func noteRecent(_ url: URL) {
        recentURLs.removeAll { $0 == url }
        recentURLs.insert(url, at: 0)
        recentURLs = Array(recentURLs.prefix(12))
        UserDefaults.standard.set(recentURLs.map(\.path), forKey: "recentFiles")
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    private var documentWindow: NSWindow? {
        NSApp.windows.first { $0.canBecomeMain && $0.isVisible }
    }

    private func updateWindow() {
        documentWindow?.representedURL = document.url
        documentWindow?.isDocumentEdited = hasUnsavedChanges
    }

    func clearRecents() {
        recentURLs = []
        UserDefaults.standard.removeObject(forKey: "recentFiles")
        NSDocumentController.shared.clearRecentDocuments(nil)
    }

    func adjustFont(_ delta: Int) { fontSize = min(24, max(13, fontSize + delta)) }

    private func fileStamp(_ url: URL) -> FileStamp? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.resolvingSymlinksInPath().path),
              let modified = attrs[.modificationDate] as? Date, let size = attrs[.size] as? NSNumber else { return nil }
        return FileStamp(modified: modified, bytes: size.intValue)
    }

    private func checkForChanges() {
        guard mode == .reading, !hasUnsavedChanges, !isLoading, let url = document.url,
              let stamp = fileStamp(url), stamp != lastObservedStamp else { return }
        lastObservedStamp = stamp
        open(url, automatic: true)
    }
}

@MainActor final class ReadingOutline: ObservableObject {
    @Published private(set) var items: [OutlineItem] = []
    @Published private(set) var activeID: String?

    func replaceItems(_ items: [OutlineItem]) {
        if self.items != items { self.items = items }
        if let activeID, !items.contains(where: { $0.id == activeID }) { self.activeID = nil }
    }

    func select(_ id: String?) {
        if activeID != id, id == nil || items.contains(where: { $0.id == id }) { activeID = id }
    }
}

enum Resource {
    static func url(_ name: String) -> URL {
        Bundle.module.resourceURL!.appendingPathComponent("Resources").appendingPathComponent(name)
    }
    static func text(_ name: String) -> String { (try? String(contentsOf: url(name), encoding: .utf8)) ?? "" }
}
