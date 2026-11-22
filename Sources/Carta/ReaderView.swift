import SwiftUI
import UniformTypeIdentifiers

struct ReaderView: View {
    @ObservedObject var state: ReaderState
    @FocusState private var searchFocused: Bool
    @Environment(\.colorScheme) private var scheme
    private var accent: Color {
        scheme == .dark ? Color(red: 0.47, green: 0.82, blue: 0.82) : Color(red: 0.08, green: 0.40, blue: 0.42)
    }

    var body: some View {
        VStack(spacing: 0) {
            switch state.mode {
            case .reading:
                readerToolbar
                readingArea
            case .normal, .typewriter:
                writerToolbar
                WriterView(state: state)
            }
        }
        .background { WritingDesk() }
        .tint(state.mode.isWriting ? .accentColor : accent)
        .overlay {
            if state.isDropTarget {
                RoundedRectangle(cornerRadius: 12).fill(accent.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accent, style: StrokeStyle(lineWidth: 2, dash: [8])))
                    .padding(6).allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $state.isDropTarget, perform: acceptDrop)
        .alert("Operazione non riuscita", isPresented: Binding(get: { state.errorMessage != nil }, set: { if !$0 { state.errorMessage = nil } })) {
            Button("OK") { state.errorMessage = nil }
        } message: { Text(state.errorMessage ?? "") }
        .onChange(of: state.searchVisible) { visible in
            if !visible { searchFocused = false; state.searchText = ""; state.web.find("", state: state) }
        }
        .onChange(of: state.searchText) { query in state.web.find(query, state: state) }
        .onExitCommand { state.searchVisible = false }
    }

    private var readingArea: some View {
        HStack(alignment: .top, spacing: 14) {
            if state.sidebarVisible {
                OutlineSidebar(outline: state.outline, sourceVisible: state.sourceVisible,
                               accent: accent, close: { state.sidebarVisible = false }, navigate: state.web.scroll(to:))
                    .frame(width: 200)
            }
            VStack(spacing: 6) {
                if state.searchVisible {
                    searchBar.writingGlass(in: RoundedRectangle(cornerRadius: 12))
                }
                WebReader(state: state)
                    .overlay(alignment: .topTrailing) {
                        if state.isLoading { ProgressView().controlSize(.small).padding(16) }
                    }
                ReadingTimeFooter(web: state.web, documentID: state.documentID)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 18)
    }

    private var modeMenu: some View {
        Menu {
            ForEach(CartaMode.allCases) { mode in
                Button { state.selectMode(mode) } label: {
                    Label(mode.label, systemImage: state.mode == mode ? "checkmark" : mode.icon)
                }
            }
        } label: {
            Label(state.mode.label, systemImage: state.mode.icon)
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help("Scegli Lettura, Scrittura normale o Macchina da scrivere")
        .accessibilityLabel("Modalità")
        .accessibilityValue(state.mode.label)
        .disabled(state.isLoading)
    }

    private var writerToolbar: some View {
        HStack(spacing: 16) {
            modeMenu
                .padding(.horizontal, 13)
                .frame(height: 34)
                .writingGlass(in: Capsule())
            VStack(alignment: .leading, spacing: 2) {
                Text(state.document.filename)
                    .font(.system(size: 13, weight: .semibold))
                    .truncationMode(.middle)
                Text(documentLocation)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Button(action: state.newDocument) {
                    Image(systemName: "square.and.pencil").frame(width: 36, height: 32)
                }
                .help("Nuovo documento (⌘N)").accessibilityLabel("Nuovo documento")
                Button(action: state.chooseFile) {
                    Image(systemName: "folder").frame(width: 36, height: 32)
                }
                .help("Apri un file (⌘O)").accessibilityLabel("Apri un file")
                Divider().frame(height: 16)
                Button { state.save() } label: {
                    Label("Salva", systemImage: "square.and.arrow.down")
                        .padding(.horizontal, 8).frame(height: 32)
                }
                .disabled(state.isLoading || (state.document.url != nil && !state.hasUnsavedChanges))
                .help("Salva il documento (⌘S)")
            }
            .buttonStyle(.borderless)
            .tint(.primary)
            .padding(3)
            .writingGlass(in: Capsule())
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private var readerToolbar: some View {
        HStack(spacing: 11) {
            modeMenu
                .padding(.horizontal, 13).frame(height: 34)
                .writingGlass(in: Capsule())
            Button { state.sidebarVisible.toggle() } label: {
                Image(systemName: "sidebar.left").frame(width: 38, height: 34)
            }
            .writingGlass(in: Capsule())
            .help("Mostra o nascondi l’indice (⌃⌘S)")
            .accessibilityLabel("Mostra o nascondi indice")
            Text(state.document.filename)
                .font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                .help(documentLocation)
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Button(action: state.chooseFile) { Image(systemName: "folder").frame(width: 27, height: 30) }
                    .help("Apri un file (⌘O)").accessibilityLabel("Apri un file")
                Divider().frame(height: 16)
                readerControls
            }
            .padding(.horizontal, 10).frame(height: 36)
            .writingGlass(in: Capsule())
        }
        .buttonStyle(.borderless).tint(.primary)
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var documentLocation: String {
        if state.hasUnsavedChanges { return "Modifiche da salvare" }
        if let url = state.document.url { return url.deletingLastPathComponent().lastPathComponent }
        return state.document.isWelcome ? "Uno spazio per leggere." : "Nuovo documento"
    }

    private var readerControls: some View {
        Group {
            Button { state.searchVisible.toggle() } label: { Image(systemName: "magnifyingglass").frame(width: 26, height: 30) }
                .help("Cerca nel documento (⌘F)").accessibilityLabel("Cerca nel documento")
            Menu {
                Picker("Aspetto", selection: $state.theme) {
                    ForEach(ReadingTheme.allCases) { theme in Text(theme.label).tag(theme) }
                }
                Divider()
                Button("Ingrandisci testo") { state.adjustFont(1) }.disabled(state.fontSize >= 24)
                Button("Riduci testo") { state.adjustFont(-1) }.disabled(state.fontSize <= 13)
                Button("Dimensione originale") { state.fontSize = 17 }
                Divider()
                Text("\(state.readingDocument.wordCount) parole · \(state.document.encoding) · \(state.fontSize) px")
                Button("Stampa / Salva PDF…") { state.web.printDocument() }
            } label: { Image(systemName: "textformat.size") }
                .menuStyle(.borderlessButton).fixedSize().help("Aspetto e dimensione del testo")
                .accessibilityLabel("Aspetto e dimensione del testo")
            Button { state.sourceVisible.toggle() } label: {
                Image(systemName: state.sourceVisible ? "doc.richtext" : "chevron.left.forwardslash.chevron.right")
                    .foregroundStyle(state.sourceVisible ? accent : .primary).frame(width: 26, height: 30)
            }.help(state.sourceVisible ? "Mostra anteprima (⇧⌘U)" : "Mostra sorgente (⇧⌘U)")
                .accessibilityLabel(state.sourceVisible ? "Mostra anteprima" : "Mostra sorgente")
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Cerca nel documento", text: $state.searchText)
                .textFieldStyle(.plain).focused($searchFocused)
                .onAppear { DispatchQueue.main.async { searchFocused = true } }
                .onSubmit { state.web.find(state.searchText, state: state) }
            Text(state.searchResult).font(.system(size: 11)).foregroundStyle(.secondary)
            Button { state.web.find(state.searchText, backwards: true, state: state) } label: { Image(systemName: "chevron.up") }
                .accessibilityLabel("Risultato precedente")
            Button { state.web.find(state.searchText, state: state) } label: { Image(systemName: "chevron.down") }
                .accessibilityLabel("Risultato successivo")
            Button("Fine") { state.searchVisible = false }
        }.font(.system(size: 12)).padding(.horizontal, 20).frame(height: 42)
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in state.open(url) }
        }
        return true
    }
}

private struct ReadingTimeFooter: View {
    @ObservedObject var web: WebActions
    let documentID: String

    private var duration: String {
        guard let time = web.readingTime, time.documentID == documentID else { return "…" }
        let minutes = time.seconds / 60
        let seconds = time.seconds % 60
        if minutes == 0 { return "\(seconds) s" }
        if seconds == 0 { return "\(minutes) min" }
        return "\(minutes) min \(seconds) s"
    }

    var body: some View {
        Text("Tempo di lettura rimanente · \(duration)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)
    }
}

private struct OutlineSidebar: View {
    @ObservedObject var outline: ReadingOutline
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var marker
    let sourceVisible: Bool
    let accent: Color
    let close: () -> Void
    let navigate: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Indice").font(.system(size: 13, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: close) { Image(systemName: "chevron.down").font(.caption) }
                    .buttonStyle(.plain).accessibilityLabel("Chiudi indice")
            }
            .padding(.horizontal, 14).padding(.top, 14)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        if sourceVisible || outline.items.isEmpty {
                            Text(sourceVisible ? "Passa all’anteprima per navigare tra i titoli." : "Il documento non contiene titoli.")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                        } else {
                            ForEach(outline.items) { item in
                                let isActive = item.id == outline.activeID
                                Button { navigate(item.id) } label: {
                                    Text(item.title)
                                        .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                                        .lineLimit(2).multilineTextAlignment(.leading)
                                        .padding(.leading, 11 + CGFloat(min(item.level - 1, 3) * 10))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(SidebarButtonStyle())
                                .background(isActive ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
                                .overlay(alignment: .leading) {
                                    if isActive {
                                        RoundedRectangle(cornerRadius: 2).fill(accent)
                                            .frame(width: 3, height: 14)
                                            .matchedGeometryEffect(id: "active-section", in: marker)
                                            .padding(.leading, 10)
                                            .allowsHitTesting(false)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .accessibilityAddTraits(isActive ? .isSelected : [])
                                .id(item.id)
                            }
                        }
                    }
                    .padding(.horizontal, 8).padding(.bottom, 8)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: outline.activeID)
                }
                .onChange(of: outline.activeID) { id in
                    if let id { proxy.scrollTo(id) }
                }
                .onAppear {
                    if let id = outline.activeID { proxy.scrollTo(id) }
                }
            }
        }
        .frame(maxHeight: sourceVisible || outline.items.isEmpty ? 112 : CGFloat(outline.items.count) * 38 + 50)
        .writingGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.top, 6)
    }
}

private struct SidebarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 10).padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(configuration.isPressed ? Color.primary.opacity(0.08) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
