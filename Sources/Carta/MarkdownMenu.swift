import AppKit
import Carbon.HIToolbox

struct MarkdownOptionShortcut {
    private var optionWasDown = false
    private var candidateKey: UInt16?

    mutating func shouldOpen(on event: NSEvent) -> Bool {
        let previousKey = candidateKey
        candidateKey = nil
        guard event.type == .flagsChanged else { return false }
        let modifiers = event.modifierFlags.intersection([.option, .shift, .control, .command, .function])
        let wasDown = optionWasDown
        optionWasDown = modifiers.contains(.option)
        guard [kVK_Option, kVK_RightOption].contains(Int(event.keyCode)) else { return false }
        if !wasDown, modifiers == .option { candidateKey = event.keyCode }
        return wasDown && modifiers.isEmpty && previousKey == event.keyCode
    }
}

enum MarkdownMenuEntry {
    case group(String, [MarkdownMenuEntry])
    case item(String, MarkdownMarker)

    static let categories: [Self] = [
        .group("Titoli e paragrafi", [
            .group("Titolo", (1...6).map { .item("Livello \($0)   " + String(repeating: "#", count: $0), .heading($0)) } + [
                .item("Livello 1 sottolineato   ===", .setext("===")),
                .item("Livello 2 sottolineato   ---", .setext("---"))
            ]),
            .item("Nuovo paragrafo", .literal("\n\n")),
            .group("A capo", [
                .item("Con due spazi", .literal("  \n")), .item("Con backslash", .literal("\\\n")),
                .item("Con tag HTML   <br>", .literal("<br>"))
            ]),
            .group("Separatore", ["---", "***", "___"].map { .item($0, .divider($0)) })
        ]),
        .group("Stile del testo", [
            .item("Grassetto   **", .inline("**", "testo", "**")),
            .item("Corsivo   *", .inline("*", "testo", "*")),
            .item("Grassetto e corsivo   ***", .inline("***", "testo", "***")),
            .item("Barrato   ~~", .inline("~~", "testo", "~~")),
            .item("Sottolineato", .inline("<u>", "testo", "</u>")),
            .item("Evidenziato", .inline("<mark>", "testo", "</mark>")),
            .item("Apice", .inline("<sup>", "2", "</sup>")),
            .item("Pedice", .inline("<sub>", "2", "</sub>")),
            .group("Altre grafie", [
                .item("Grassetto   __", .inline("__", "testo", "__")),
                .item("Corsivo   _", .inline("_", "testo", "_")),
                .item("Grassetto e corsivo   ___", .inline("___", "testo", "___")),
                .item("Enfasi dentro il grassetto", .inline("**Una frase con _", "enfasi", "_**")),
                .item("Barrato   ~", .inline("~", "testo", "~"))
            ])
        ]),
        .group("Elenchi e attività", [
            .group("Elenco puntato", ["-", "*", "+"].map { .item("Punto elenco   " + $0, .lines($0 + " ", "Voce")) }),
            .group("Elenco numerato", [
                .item("Numeri con punto   1.", .ordered(".")), .item("Numeri con parentesi   1)", .ordered(")"))
            ]),
            .item("Sottoelenco", .sublist),
            .item("Attività da fare   [ ]", .lines("- [ ] ", "Attività")),
            .item("Attività completata   [x]", .lines("- [x] ", "Attività"))
        ]),
        .group("Citazioni", [
            .item("Citazione   >", .lines("> ", "Citazione")),
            .item("Citazione annidata   > >", .lines("> > ", "Citazione"))
        ]),
        .group("Link e immagini", [
            .item("Link web", link("https://esempio.it")),
            .item("Link con titolo", link("https://esempio.it", suffix: " \"Titolo\")")),
            .item("Link a un file Markdown", link("appunti.md")),
            .item("Link a una sezione", link("#titolo")),
            .group("Indirizzi automatici", [
                .item("URL tra parentesi angolari", .inline("<", "https://esempio.it", ">")),
                .item("Email tra parentesi angolari", .inline("<", "nome@esempio.it", ">")),
                .item("URL semplice", .inline("", "https://esempio.it", "")),
                .item("Indirizzo www", .inline("", "www.esempio.it", "")),
                .item("Email semplice", .inline("", "nome@esempio.it", ""))
            ]),
            .group("Immagini", [
                .item("Immagine locale", image("immagini/foto.jpg")),
                .item("Immagine dal web", image("https://esempio.it/foto.jpg")),
                .item("Immagine cliccabile", .linked(prefix: "[![", caption: "Descrizione", middle: "](immagini/foto.jpg)](", destination: "https://esempio.it", suffix: ")"))
            ]),
            .group("Riferimenti", [
                .item("Link con identificatore", .linked(prefix: "[", caption: "Testo", middle: "][", destination: "id", suffix: "]")),
                .item("Link abbreviato   [id][]", .reference(label: "id", short: false)),
                .item("Link implicito   [id]", .reference(label: "id", short: true)),
                .item("Immagine con identificatore", .linked(prefix: "![", caption: "Descrizione", middle: "][", destination: "id", suffix: "]")),
                .item("Definizione di riferimento", .definition)
            ])
        ]),
        .group("Codice", [
            .item("Codice in linea", .inlineCode),
            .item("Blocco con backtick", .fence("`", language: "")),
            .item("Blocco con tilde", .fence("~", language: "")),
            .item("Blocco con linguaggio", .fence("`", language: "python")),
            .item("Blocco con quattro spazi", .indentedCode)
        ]),
        .group("Tabelle", [
            .item("Inserisci tabella", .table),
            .group("Allineamento colonna", [
                .item("Sinistra   :---", .alignment(":---")), .item("Centro   :---:", .alignment(":---:")),
                .item("Destra   ---:", .alignment("---:"))
            ]),
            .item("Barra verticale nella cella", .literal("\\|"))
        ]),
        .group("Simboli e commenti", [
            .item("Mostra i simboli letteralmente   \\", .escaped),
            .item("Spazio indivisibile", .literal("&nbsp;")),
            .item("Copyright", .literal("&copy;")),
            .item("E commerciale", .literal("&amp;")),
            .item("Commento nascosto", .inline("<!-- ", "Nota di revisione", " -->"))
        ]),
        .group("Altri editor · solo sorgente", [
            .item("Evidenziato   ==", .inline("==", "testo", "==")),
            .item("Collegamento wiki", .inline("[[", "Nome nota", "]]")),
            .item("Allegato wiki", .inline("![[", "allegato", "]]")),
            .item("Richiamo a nota a piè di pagina", .inline("[^", "1", "]")),
            .item("Definizione di nota a piè di pagina", .footnote),
            .item("Riquadro nota", .quoteAlert)
        ])
    ]

    private static func link(_ destination: String, suffix: String = ")") -> MarkdownMarker {
        .linked(prefix: "[", caption: "Testo", middle: "](", destination: destination, suffix: suffix)
    }

    private static func image(_ destination: String) -> MarkdownMarker {
        .linked(prefix: "![", caption: "Descrizione", middle: "](", destination: destination, suffix: ")")
    }
}

extension TypewriterTextView {
    private struct MarkdownMenuAction {
        let marker: MarkdownMarker
        let selection: NSRange
    }

    func markdownMenu(for selection: NSRange) -> NSMenu {
        func makeItem(_ entry: MarkdownMenuEntry) -> NSMenuItem {
            switch entry {
            case let .group(title, entries):
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                let menu = NSMenu(title: title)
                for entry in entries { menu.addItem(makeItem(entry)) }
                item.submenu = menu
                return item
            case let .item(title, marker):
                let item = NSMenuItem(title: title, action: #selector(insertMarkdown(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = MarkdownMenuAction(marker: marker, selection: selection)
                return item
            }
        }
        let menu = NSMenu(title: "Inserisci Markdown")
        for category in MarkdownMenuEntry.categories { menu.addItem(makeItem(category)) }
        return menu
    }

    func showMarkdownMenuAtCaret() {
        let selection = selectedRange()
        let insertion = selectionAffinity == .upstream ? selection.location : NSMaxRange(selection)
        let caret = NSRange(location: insertion, length: 0)
        scrollRangeToVisible(caret)
        let rect = firstRect(forCharacterRange: caret, actualRange: nil)
        guard rect.height > 0, let window else { return }
        let anchor = window.convertPoint(fromScreen: NSPoint(x: rect.maxX + 6, y: rect.maxY))
        markdownMenu(for: selection).popUp(positioning: nil, at: convert(anchor, from: nil), in: self)
    }

    @objc private func insertMarkdown(_ sender: NSMenuItem) {
        guard isEditable, let action = sender.representedObject as? MarkdownMenuAction,
              NSMaxRange(action.selection) <= string.utf16.count else { return }
        window?.makeFirstResponder(self)
        let edit = action.marker.edit(in: string as NSString, selection: action.selection, newline: newline)
        setSelectedRange(edit.range)
        breakUndoCoalescing()
        insertText(edit.replacement, replacementRange: edit.range)
        breakUndoCoalescing()
        guard NSMaxRange(edit.selection) <= string.utf16.count else { return }
        setSelectedRange(edit.selection)
        scrollRangeToVisible(edit.selection)
        followTypingLine()
    }
}
