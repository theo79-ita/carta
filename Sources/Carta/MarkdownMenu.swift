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
        .group(L10n.text("markdown.headings"), [
            .group(L10n.text("markdown.heading"), (1...6).map { .item(L10n.format("markdown.headingLevel", $0) + "   " + String(repeating: "#", count: $0), .heading($0)) } + [
                .item(L10n.text("markdown.setext1"), .setext("===")),
                .item(L10n.text("markdown.setext2"), .setext("---"))
            ]),
            .item(L10n.text("markdown.newParagraph"), .literal("\n\n")),
            .group(L10n.text("markdown.lineBreak"), [
                .item(L10n.text("markdown.lineBreakSpaces"), .literal("  \n")), .item(L10n.text("markdown.lineBreakBackslash"), .literal("\\\n")),
                .item(L10n.text("markdown.lineBreakHTML"), .literal("<br>"))
            ]),
            .group(L10n.text("markdown.divider"), ["---", "***", "___"].map { .item($0, .divider($0)) })
        ]),
        .group(L10n.text("markdown.style"), [
            .item(L10n.text("markdown.boldStars"), .inline("**", L10n.text("sample.strongText"), "**")),
            .item(L10n.text("markdown.italicStar"), .inline("*", L10n.text("sample.strongText"), "*")),
            .item(L10n.text("markdown.boldItalicStars"), .inline("***", L10n.text("sample.strongText"), "***")),
            .item(L10n.text("markdown.strikeDouble"), .inline("~~", L10n.text("sample.strongText"), "~~")),
            .item(L10n.text("markdown.underline"), .inline("<u>", L10n.text("sample.strongText"), "</u>")),
            .item(L10n.text("markdown.highlight"), .inline("<mark>", L10n.text("sample.strongText"), "</mark>")),
            .item(L10n.text("markdown.superscript"), .inline("<sup>", "2", "</sup>")),
            .item(L10n.text("markdown.subscript"), .inline("<sub>", "2", "</sub>")),
            .group(L10n.text("markdown.alternateStyles"), [
                .item(L10n.text("markdown.boldUnderscores"), .inline("__", L10n.text("sample.strongText"), "__")),
                .item(L10n.text("markdown.italicUnderscore"), .inline("_", L10n.text("sample.strongText"), "_")),
                .item(L10n.text("markdown.boldItalicUnderscores"), .inline("___", L10n.text("sample.strongText"), "___")),
                .item(L10n.text("markdown.nestedEmphasis"), .inline(L10n.text("sample.emphasisPrefix"), L10n.text("sample.emphasis"), "_**")),
                .item(L10n.text("markdown.strikeSingle"), .inline("~", L10n.text("sample.strongText"), "~"))
            ])
        ]),
        .group(L10n.text("markdown.lists"), [
            .group(L10n.text("markdown.bullets"), ["-", "*", "+"].map { .item(L10n.text("markdown.bullet") + "   " + $0, .lines($0 + " ", L10n.text("sample.listItem"))) }),
            .group(L10n.text("markdown.ordered"), [
                .item(L10n.text("markdown.orderedPeriod"), .ordered(".")), .item(L10n.text("markdown.orderedParen"), .ordered(")"))
            ]),
            .item(L10n.text("markdown.sublist"), .sublist),
            .item(L10n.text("markdown.taskOpen"), .lines("- [ ] ", L10n.text("sample.task"))),
            .item(L10n.text("markdown.taskDone"), .lines("- [x] ", L10n.text("sample.task")))
        ]),
        .group(L10n.text("markdown.quotes"), [
            .item(L10n.text("markdown.quote"), .lines("> ", L10n.text("sample.quote"))),
            .item(L10n.text("markdown.nestedQuote"), .lines("> > ", L10n.text("sample.quote")))
        ]),
        .group(L10n.text("markdown.linksImages"), [
            .item(L10n.text("markdown.webLink"), link(L10n.text("sample.url"))),
            .item(L10n.text("markdown.titledLink"), link(L10n.text("sample.url"), suffix: " \"\(L10n.text("markdown.heading"))\")")),
            .item(L10n.text("markdown.markdownLink"), link(L10n.text("sample.document"))),
            .item(L10n.text("markdown.anchorLink"), link(L10n.text("sample.anchor"))),
            .group(L10n.text("markdown.autolinks"), [
                .item(L10n.text("markdown.angleURL"), .inline("<", L10n.text("sample.url"), ">")),
                .item(L10n.text("markdown.angleEmail"), .inline("<", L10n.text("sample.email"), ">")),
                .item(L10n.text("markdown.bareURL"), .inline("", L10n.text("sample.url"), "")),
                .item(L10n.text("markdown.www"), .inline("", L10n.text("sample.www"), "")),
                .item(L10n.text("markdown.bareEmail"), .inline("", L10n.text("sample.email"), ""))
            ]),
            .group(L10n.text("markdown.images"), [
                .item(L10n.text("markdown.localImage"), image(L10n.text("sample.imagePath"))),
                .item(L10n.text("markdown.webImage"), image(L10n.text("sample.imageURL"))),
                .item(L10n.text("markdown.linkedImage"), .linked(prefix: "[![", caption: L10n.text("sample.description"), middle: "](\(L10n.text("sample.imagePath")))](", destination: L10n.text("sample.url"), suffix: ")"))
            ]),
            .group(L10n.text("markdown.references"), [
                .item(L10n.text("markdown.referenceLink"), .linked(prefix: "[", caption: L10n.text("sample.capitalText"), middle: "][", destination: "id", suffix: "]")),
                .item(L10n.text("markdown.collapsedLink"), .reference(label: "id", short: false)),
                .item(L10n.text("markdown.shortcutLink"), .reference(label: "id", short: true)),
                .item(L10n.text("markdown.referenceImage"), .linked(prefix: "![", caption: L10n.text("sample.description"), middle: "][", destination: "id", suffix: "]")),
                .item(L10n.text("markdown.definition"), .definition)
            ])
        ]),
        .group(L10n.text("markdown.code"), [
            .item(L10n.text("markdown.inlineCode"), .inlineCode),
            .item(L10n.text("markdown.backtickBlock"), .fence("`", language: "")),
            .item(L10n.text("markdown.tildeBlock"), .fence("~", language: "")),
            .item(L10n.text("markdown.languageBlock"), .fence("`", language: "python")),
            .item(L10n.text("markdown.indentedBlock"), .indentedCode)
        ]),
        .group(L10n.text("markdown.tables"), [
            .item(L10n.text("markdown.table"), .table),
            .group(L10n.text("markdown.columnAlignment"), [
                .item(L10n.text("markdown.alignLeft"), .alignment(":---")), .item(L10n.text("markdown.alignCenter"), .alignment(":---:")),
                .item(L10n.text("markdown.alignRight"), .alignment("---:"))
            ]),
            .item(L10n.text("markdown.escapePipe"), .literal("\\|"))
        ]),
        .group(L10n.text("markdown.symbols"), [
            .item(L10n.text("markdown.escaped"), .escaped),
            .item(L10n.text("markdown.nbsp"), .literal("&nbsp;")),
            .item(L10n.text("markdown.copyright"), .literal("&copy;")),
            .item(L10n.text("markdown.ampersand"), .literal("&amp;")),
            .item(L10n.text("markdown.comment"), .inline("<!-- ", L10n.text("sample.reviewNote"), " -->"))
        ]),
        .group(L10n.text("markdown.sourceOnly"), [
            .item(L10n.text("markdown.highlightEquals"), .inline("==", L10n.text("sample.strongText"), "==")),
            .item(L10n.text("markdown.wikiLink"), .inline("[[", L10n.text("sample.noteName"), "]]")),
            .item(L10n.text("markdown.wikiAttachment"), .inline("![[", L10n.text("sample.attachment"), "]]")),
            .item(L10n.text("markdown.footnoteReference"), .inline("[^", "1", "]")),
            .item(L10n.text("markdown.footnoteDefinition"), .footnote),
            .item(L10n.text("markdown.note"), .quoteAlert)
        ])
    ]

    private static func link(_ destination: String, suffix: String = ")") -> MarkdownMarker {
        .linked(prefix: "[", caption: L10n.text("sample.capitalText"), middle: "](", destination: destination, suffix: suffix)
    }

    private static func image(_ destination: String) -> MarkdownMarker {
        .linked(prefix: "![", caption: L10n.text("sample.description"), middle: "](", destination: destination, suffix: ")")
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
        let menu = NSMenu(title: L10n.text("markdown.insert"))
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
