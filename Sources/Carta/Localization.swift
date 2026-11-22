import Foundation

enum Resource {
    static let directory: URL = {
        #if SWIFT_PACKAGE
        Bundle.module.resourceURL!.appendingPathComponent("Resources", isDirectory: true)
        #else
        // The standalone test runner receives the resource directory as its first argument.
        URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        #endif
    }()

    static func url(_ name: String) -> URL { directory.appendingPathComponent(name) }
    static func text(_ name: String) -> String { (try? String(contentsOf: url(name), encoding: .utf8)) ?? "" }

    static func readerPage(language: L10n.Language = L10n.current) -> String {
        let labels = [
            "language": language.rawValue,
            "document": L10n.text("web.document", language: language),
            "imageMissing": L10n.text("web.imageMissing", language: language),
            "code": L10n.text("web.code", language: language),
            "copy": L10n.text("web.copy", language: language),
            "copyCode": L10n.text("web.copyCode", language: language),
            "copied": L10n.text("web.copied", language: language),
            "table": L10n.text("web.table", language: language)
        ]
        let json = (try? JSONEncoder().encode(labels)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        let script = text("reader.js").replacingOccurrences(of: "/* READER_STRINGS */ {}", with: json)
        return text("reader.html")
            .replacingOccurrences(of: "/* MARKED_LIBRARY */", with: text("vendor/marked.js"))
            .replacingOccurrences(of: "/* PURIFY_LIBRARY */", with: text("vendor/purify.js"))
            .replacingOccurrences(of: "/* READER_SCRIPT */", with: script)
            .replacingOccurrences(of: "/* READER_STYLES */", with: text("reader.css"))
    }
}

enum L10n {
    enum Language: String, CaseIterable {
        case italian = "it"
        case english = "en"
    }

    static let current: Language = {
        if !Bundle.main.localizations.isEmpty, let preference = Bundle.main.preferredLocalizations.first,
           let supported = Language(rawValue: preference) { return supported }
        let supported = Language.allCases.map(\.rawValue)
        let preferred = Bundle.preferredLocalizations(from: supported, forPreferences: Locale.preferredLanguages)
        return preferred.first.flatMap(Language.init(rawValue:)) ?? .italian
    }()

    private static let bundles = Dictionary(uniqueKeysWithValues: Language.allCases.compactMap { language in
        Bundle(url: Resource.url("\(language.rawValue).lproj")).map { (language, $0) }
    })

    static func text(_ key: String, language: Language = current) -> String {
        bundles[language]?.localizedString(forKey: key, value: nil, table: nil) ?? key
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }

    static func wordCount(_ count: Int) -> String {
        count == 1 ? text("reader.oneWord") : format("reader.wordCount", count)
    }

    static func welcome(language: Language = current) -> String {
        let content = Resource.text("\(language.rawValue).lproj/Welcome.md")
        return content.isEmpty ? "# " + text("app.welcome", language: language) : content
    }
}
