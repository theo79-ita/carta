import Foundation

/// Ranges use UTF-16, the same coordinates as NSTextView and its undo manager.
struct MarkdownEdit {
    var range: NSRange
    var replacement: String
    var selection: NSRange
}

enum MarkdownMarker {
    case inline(String, String, String)
    case lines(String, String)
    case ordered(String)
    case setext(String)
    case heading(Int)
    case literal(String)
    case divider(String)
    case inlineCode
    case fence(Character, language: String)
    case escaped
    case reference(label: String, short: Bool)
    case definition
    case linked(prefix: String, caption: String, middle: String, destination: String, suffix: String)
    case table
    case sublist, indentedCode, footnote
    case alignment(String)
    case quoteAlert

    func edit(in document: NSString, selection: NSRange, newline: String) -> MarkdownEdit {
        var range = selection
        let selected = document.substring(with: selection)

        // Keep the editable field selected. Literal insertions leave the caret after the marker.
        func field(_ before: String, _ value: String, _ after: String) -> MarkdownEdit {
            MarkdownEdit(range: range, replacement: before + value + after,
                         selection: NSRange(location: range.location + before.utf16.count, length: value.utf16.count))
        }

        // Blocks need blank lines on both sides, including when inserted inside a paragraph.
        func block(_ before: String, _ value: String, _ after: String) -> MarkdownEdit {
            func padding(at position: Int, backwards: Bool) -> String {
                var cursor = position
                for count in 0..<2 {
                    if backwards ? cursor == 0 : cursor == document.length { return "" }
                    let index = backwards ? cursor - 1 : cursor
                    let char = document.character(at: index)
                    guard char == 10 || char == 13 else { return String(repeating: newline, count: 2 - count) }
                    cursor += backwards ? -1 : 1
                    if backwards, char == 10, cursor > 0, document.character(at: cursor - 1) == 13 { cursor -= 1 }
                    if !backwards, char == 13, cursor < document.length, document.character(at: cursor) == 10 { cursor += 1 }
                }
                return ""
            }
            return field(padding(at: range.location, backwards: true) + before, value,
                         after + padding(at: NSMaxRange(range), backwards: false))
        }

        func appendLiteral(_ marker: String) -> MarkdownEdit {
            range = NSRange(location: NSMaxRange(selection), length: 0)
            return field(marker, "", "")
        }

        func formattedLines(sample: String, prefix: (Int) -> String, removing oldMarker: String? = nil) -> MarkdownEdit {
            var start = 0, contentsEnd = 0
            document.getLineStart(&start, end: nil, contentsEnd: &contentsEnd, for: selection)
            range = NSRange(location: start, length: contentsEnd - start)
            let original = document.substring(with: range)
            let rows = original.isEmpty ? [sample] : original.componentsByLine
            let formatted = rows.enumerated().map { index, row -> String in
                let content = oldMarker.map { row.replacingOccurrences(of: $0, with: "", options: .regularExpression) } ?? row
                return prefix(index) + content
            }.joined(separator: newline)
            return field(prefix(0), String(formatted.dropFirst(prefix(0).count)), "")
        }

        let listMarker = #"^(?:[-+*]|[0-9]{1,9}[.)])[ \t]+(?:\[[ xX]\][ \t]+)?"#
        switch self {
        case let .inline(before, placeholder, after):
            if before == after, let first = before.first, "*_~".contains(first),
               let start = selected.firstIndex(where: { !$0.isWhitespace }),
               let end = selected.lastIndex(where: { !$0.isWhitespace }) {
                return field(String(selected[..<start]) + before, String(selected[start...end]),
                             after + String(selected[selected.index(after: end)...]))
            }
            return field(before, selected.isEmpty ? placeholder : selected, after)
        case let .linked(before, placeholder, middle, destination, suffix):
            // With an existing caption, go directly to the destination.
            let caption = (selected.isEmpty ? placeholder : selected)
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "[", with: "\\[")
                .replacingOccurrences(of: "]", with: "\\]")
            if selected.isEmpty { return field(before, caption, middle + destination + suffix) }
            return field(before + caption + middle, destination, suffix)
        case let .literal(marker):
            return appendLiteral(marker.replacingOccurrences(of: "\n", with: newline))
        case let .divider(marker):
            range = NSRange(location: NSMaxRange(selection), length: 0)
            let after = NSMaxRange(range) == document.length ? newline + newline : ""
            var edit = block(marker, "", after)
            edit.selection.location = range.location + edit.replacement.utf16.count
            return edit
        case let .heading(level):
            return formattedLines(sample: "Titolo", prefix: { _ in String(repeating: "#", count: level) + " " }, removing: #"^ {0,3}#{1,6}(?:[ \t]+|$)"#)
        case let .lines(prefix, placeholder):
            return formattedLines(sample: placeholder, prefix: { _ in prefix }, removing: prefix.hasPrefix(">") ? nil : listMarker)
        case let .ordered(delimiter):
            return formattedLines(sample: "Prima voce", prefix: { "\($0 + 1)\(delimiter) " }, removing: listMarker)
        case let .setext(underline):
            var start = 0, end = 0
            document.getLineStart(&start, end: nil, contentsEnd: &end, for: selection)
            range = NSRange(location: start, length: end - start)
            let value = document.substring(with: range)
            return block("", value.isEmpty ? "Titolo" : value, newline + underline)
        case .inlineCode, .fence:
            let value = selected.isEmpty ? "codice" : selected
            let character: Character
            let minimum: Int
            if case let .fence(fence, _) = self { character = fence; minimum = 3 }
            else { character = "`"; minimum = 1 }
            let longest = value.split(whereSeparator: { $0 != character }).map(\.count).max() ?? 0
            let delimiter = String(repeating: character, count: max(minimum, longest + 1))
            if case let .fence(_, language) = self {
                return block(delimiter + language + newline, value, (value.last?.isNewline == true ? "" : newline) + delimiter)
            }
            let needsPadding = value.first == character || value.last == character ||
                (value.hasPrefix(" ") && value.hasSuffix(" ") && value.contains(where: { $0 != " " }))
            let pad = needsPadding ? " " : ""
            return field(delimiter + pad, value, pad + delimiter)
        case .escaped:
            let value = selected.isEmpty ? "*" : selected
            let escaped = value.map { character -> String in
                if let code = character.asciiValue, (33...47).contains(code) || (58...64).contains(code) ||
                    (91...96).contains(code) || (123...126).contains(code) { return "\\" + String(character) }
                return String(character)
            }.joined()
            return field("", escaped, "")
        case let .reference(label, short):
            return field("[", selected.isEmpty ? label : selected, short ? "]" : "][]")
        case .definition:
            return block("[", selected.isEmpty ? "id" : selected, "]: https://esempio.it \"Titolo\"")
        case .sublist:
            var start = 0, end = 0
            document.getLineStart(&start, end: nil, contentsEnd: &end, for: selection)
            // A sublist needs a parent. Use the preceding item's content column when available.
            if start > 0 {
                let previous = document.lineRange(for: NSRange(location: start - 1, length: 0))
                let line = document.substring(with: previous) as NSString
                let marker = line.range(of: #"^ *(?:[-+*]|[0-9]+[.)])[ \t]+"#, options: .regularExpression)
                if marker.location != NSNotFound {
                    return formattedLines(sample: "Sottovoce", prefix: { _ in String(repeating: " ", count: marker.length) + "- " }, removing: listMarker)
                }
            }
            range = NSRange(location: start, length: end - start)
            let content = document.substring(with: range)
            let rows = content.isEmpty ? ["Sottovoce"] : content.componentsByLine
            return block("- Voce" + newline + "  - ", rows.joined(separator: newline + "  - "), "")
        case .indentedCode:
            let value = selected.isEmpty ? "codice" : selected
            return block("    ", value.componentsByLine.joined(separator: newline + "    "), "")
        case .footnote:
            return block("[^1]: ", selected.isEmpty ? "Testo della nota" : selected, "")
        case .table, .alignment:
            var alignment = "---"
            if case let .alignment(marker) = self {
                if let edit = Self.alignColumn(marker, in: document, at: selection.location) { return edit }
                alignment = marker
            }
            // A tab-separated selection can be pasted from a spreadsheet and turned into a table.
            let lines = selected.componentsByLine
            var rows = selected.isEmpty ? [["Colonna 1", "Colonna 2"], ["Dato 1", "Dato 2"]] :
                lines.map { $0.components(separatedBy: "\t") }
            if rows.count > 1 && rows.last == [""] { rows.removeLast() }
            let columns = max(2, rows.map(\.count).max() ?? 2)
            if rows.count == 1 { rows.append(Array(repeating: "", count: columns)) }
            func escapeCell(_ value: String) -> String {
                value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "|", with: "\\|")
            }
            func row(_ cells: [String]) -> String {
                "| " + cells.map(escapeCell).joined(separator: " | ") + " |"
            }
            // GFM fills missing body cells. Only the header must match the delimiter width.
            rows[0] += Array(repeating: "", count: columns - rows[0].count)
            var output = rows.map(row)
            var separators = Array(repeating: "---", count: columns)
            separators[0] = alignment
            output.insert(row(separators), at: 1)
            var edit = block("", output.joined(separator: newline), "")
            edit.selection.location += 2
            edit.selection.length = escapeCell(rows[0][0]).utf16.count
            return edit
        case .quoteAlert:
            let value = selected.isEmpty ? "Testo della nota" : selected
            return block("> [!NOTE]" + newline + "> ", value.componentsByLine.joined(separator: newline + "> "), "")
        }
    }

    private static func alignColumn(_ marker: String, in document: NSString, at location: Int) -> MarkdownEdit? {
        func cells(on line: NSRange) -> [NSRange] {
            let end = NSMaxRange(line)
            var cells: [NSRange] = []
            var start = line.location
            var escaped = false
            for index in start..<end {
                let char = document.character(at: index)
                if char == 124 && !escaped {
                    cells.append(NSRange(location: start, length: index - start))
                    start = index + 1
                }
                escaped = char == 92 && !escaped
            }
            guard !cells.isEmpty else { return [] }
            cells.append(NSRange(location: start, length: end - start))
            let whitespace = CharacterSet.whitespacesAndNewlines
            if let last = cells.last, document.substring(with: last).trimmingCharacters(in: whitespace).isEmpty { cells.removeLast() }
            if let first = cells.first, document.substring(with: first).trimmingCharacters(in: whitespace).isEmpty { cells.removeFirst() }
            return cells
        }
        let current = document.lineRange(for: NSRange(location: location, length: 0))
        let currentCells = cells(on: current)
        guard !currentCells.isEmpty else { return nil }
        let column = currentCells.firstIndex(where: { location <= NSMaxRange($0) }) ?? currentCells.count - 1
        func alignmentEdit(on line: NSRange) -> MarkdownEdit? {
            let ranges = cells(on: line)
            guard ranges.indices.contains(column), line.location > 0 else { return nil }
            let separators = ranges.map { document.substring(with: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard separators.allSatisfy({ $0.range(of: #"^:?-+:?$"#, options: .regularExpression) != nil }) else { return nil }
            let header = document.lineRange(for: NSRange(location: line.location - 1, length: 0))
            guard cells(on: header).count == ranges.count else { return nil }
            let target = document.range(of: separators[column], options: .literal, range: ranges[column])
            let offset = NSMaxRange(target) <= location ? marker.utf16.count - target.length : 0
            let caret = NSLocationInRange(location, target) ? target.location + marker.utf16.count : location + offset
            return MarkdownEdit(range: target, replacement: marker, selection: NSRange(location: caret, length: 0))
        }
        if NSMaxRange(current) < document.length {
            let next = document.lineRange(for: NSRange(location: NSMaxRange(current), length: 0))
            if let edit = alignmentEdit(on: next) { return edit }
        }
        var line = current
        while !cells(on: line).isEmpty {
            if let edit = alignmentEdit(on: line) { return edit }
            guard line.location > 0 else { break }
            line = document.lineRange(for: NSRange(location: line.location - 1, length: 0))
        }
        return nil
    }

}

private extension String {
    var componentsByLine: [String] {
        split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
    }
}
