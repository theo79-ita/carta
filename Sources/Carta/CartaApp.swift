import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let argument = CommandLine.arguments.dropFirst().first, !argument.hasPrefix("-") {
            ReaderState.shared.open(URL(fileURLWithPath: argument))
        }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first { ReaderState.shared.open(url) }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let state = ReaderState.shared
        guard state.confirmLeavingDocument() else { return .terminateCancel }
        state.discardDraft()
        return .terminateNow
    }
}

@main struct CartaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var state = ReaderState.shared

    var body: some Scene {
        Window("Carta", id: "reader") {
            ReaderView(state: state)
                .frame(minWidth: 760, minHeight: 520)
                .preferredColorScheme(state.theme.scheme)
                .background(WindowCloseGuard(state: state))
        }
        .defaultSize(width: 1140, height: 780)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L10n.text("document.new"), action: state.newDocument).keyboardShortcut("n")
                Button(L10n.text("document.open"), action: state.chooseFile).keyboardShortcut("o")
                Menu(L10n.text("document.openRecent")) {
                    ForEach(state.recentURLs, id: \.self) { url in
                        Button(url.lastPathComponent) { state.open(url) }
                    }
                    Divider()
                    Button(L10n.text("document.clearRecent"), action: state.clearRecents).disabled(state.recentURLs.isEmpty)
                }
            }
            CommandGroup(replacing: .saveItem) {
                Button(L10n.text("document.save")) { state.save() }.keyboardShortcut("s")
                    .disabled(state.document.isWelcome || state.isLoading || (state.document.url != nil && !state.hasUnsavedChanges))
                Button(L10n.text("document.saveAs")) { state.save(asCopy: true) }
                    .keyboardShortcut("s", modifiers: [.command, .shift]).disabled(state.document.isWelcome || state.isLoading)
                Button(L10n.text("document.reload")) { if let url = state.document.url { state.open(url) } }
                    .keyboardShortcut("r").disabled(!state.canReload)
            }
            CommandGroup(replacing: .printItem) {
                Button(L10n.text("document.print")) { state.web.printDocument() }.keyboardShortcut("p").disabled(state.mode.isWriting)
            }
            CommandGroup(after: .textEditing) {
                Button(L10n.text("document.searchCommand")) { state.searchVisible = true }.keyboardShortcut("f").disabled(state.mode.isWriting)
            }
            CommandGroup(after: .sidebar) {
                Button(L10n.text("mode.reading")) { state.selectMode(.reading) }.keyboardShortcut("1", modifiers: [.command, .option])
                Button(L10n.text("mode.writing")) { state.selectMode(.normal) }.keyboardShortcut("2", modifiers: [.command, .option])
                Button(L10n.text("mode.typewriter")) { state.selectMode(.typewriter) }.keyboardShortcut("3", modifiers: [.command, .option])
                Button(L10n.text("paper.calibrateCommand"), action: state.calibratePaper)
                    .disabled(!state.mode.isWriting || state.paperDisplay.preferenceKey == nil)
                Divider()
                Button(L10n.text("outline.toggleCommand")) { state.sidebarVisible.toggle() }
                    .keyboardShortcut("s", modifiers: [.command, .control]).disabled(state.mode.isWriting)
                Button(state.sourceVisible ? L10n.text("reader.preview") : L10n.text("reader.source")) { state.sourceVisible.toggle() }
                    .keyboardShortcut("u", modifiers: [.command, .shift]).disabled(state.mode.isWriting)
                Divider()
                Button(L10n.text("reader.zoomIn")) { state.adjustFont(1) }.keyboardShortcut("+").disabled(state.mode.isWriting)
                Button(L10n.text("reader.zoomOut")) { state.adjustFont(-1) }.keyboardShortcut("-").disabled(state.mode.isWriting)
                Button(L10n.text("reader.zoomReset")) { state.fontSize = 17 }.keyboardShortcut("0").disabled(state.mode.isWriting)
            }
            CommandGroup(replacing: .help) {
                Button(L10n.text("app.welcome"), action: state.showWelcome)
            }
        }
    }
}

private struct WindowCloseGuard: NSViewRepresentable {
    let state: ReaderState

    func makeNSView(context: Context) -> CloseAwareView { CloseAwareView(state: state) }
    func updateNSView(_ nsView: CloseAwareView, context: Context) {}

    final class CloseAwareView: NSView, NSWindowDelegate {
        let state: ReaderState
        weak var originalDelegate: NSWindowDelegate?

        init(state: ReaderState) {
            self.state = state
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window, window.delegate !== self else { return }
                self.originalDelegate = window.delegate
                window.delegate = self
            }
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard originalDelegate?.windowShouldClose?(sender) ?? true, state.confirmLeavingDocument() else { return false }
            state.discardDraft()
            return true
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || originalDelegate?.responds(to: selector) == true
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            if let originalDelegate, originalDelegate.responds(to: selector) { return originalDelegate }
            return super.forwardingTarget(for: selector)
        }
    }
}

