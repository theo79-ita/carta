import Foundation
import UniformTypeIdentifiers

struct OutlineItem: Identifiable, Equatable {
    let id: String
    let title: String
    let level: Int
}

struct MarkdownDocument {
    let url: URL?
    let text: String
    let encoding: String
    let modified: Date?
    let fileData: Data?
    let isWelcome: Bool
    var title: String { url?.deletingPathExtension().lastPathComponent ?? (isWelcome ? "Benvenuto in Carta" : "Senza titolo") }
    var filename: String { url?.lastPathComponent ?? (isWelcome ? "Benvenuto.md" : "Senza titolo.md") }
    var wordCount: Int { text.split(whereSeparator: { $0.isWhitespace }).count }
    var readingSeconds: Int { Int(ceil(Double(wordCount) * 60 / 220)) }

    static let extensions = ["md", "markdown", "mdown", "mkd", "mkdn", "mdx", "txt"]
    static let maximumBytes = 20 * 1024 * 1024

    init(url: URL? = nil, text: String = "", encoding: String = "UTF-8", modified: Date? = nil,
         fileData: Data? = nil, isWelcome: Bool = false) {
        self.url = url
        self.text = text
        self.encoding = encoding
        self.modified = modified
        self.fileData = fileData
        self.isWelcome = isWelcome
    }

    private static func readData(_ url: URL) throws -> (Data, Date?) {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= maximumBytes else {
            throw DocumentError.tooLarge
        }
        let data = try Data(contentsOf: url)
        guard data.count <= maximumBytes else { throw DocumentError.tooLarge }
        return (data, attributes[.modificationDate] as? Date)
    }

    static func read(_ url: URL) throws -> MarkdownDocument {
        let (data, modified) = try readData(url.resolvingSymlinksInPath())
        let decoded = try decode(data)
        return MarkdownDocument(url: url, text: decoded.0, encoding: decoded.1, modified: modified, fileData: data)
    }

    func replacingText(_ text: String) -> MarkdownDocument {
        MarkdownDocument(url: url, text: text, encoding: encoding, modified: modified, fileData: fileData, isWelcome: isWelcome)
    }

    func write(_ text: String, to destination: URL) throws -> MarkdownDocument {
        let target = destination.resolvingSymlinksInPath()
        let originalURL = url?.resolvingSymlinksInPath()
        let overwritesOriginal = originalURL?.path == target.path
        let data: Data
        if overwritesOriginal, fileData?.starts(with: [0xFF, 0xFE]) == true {
            guard let encoded = text.data(using: .utf16LittleEndian) else { throw DocumentError.invalidEncoding }
            data = Data([0xFF, 0xFE]) + encoded
        } else if overwritesOriginal, fileData?.starts(with: [0xFE, 0xFF]) == true {
            guard let encoded = text.data(using: .utf16BigEndian) else { throw DocumentError.invalidEncoding }
            data = Data([0xFE, 0xFF]) + encoded
        } else if overwritesOriginal, encoding == "Windows-1252", let legacy = text.data(using: .windowsCP1252),
                  let decoded = try? Self.decode(legacy), decoded.0.utf8.elementsEqual(text.utf8) {
            data = legacy
        } else if overwritesOriginal, fileData?.starts(with: [0xEF, 0xBB, 0xBF]) == true {
            data = Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
        } else {
            data = Data(text.utf8)
        }
        guard data.count <= Self.maximumBytes else { throw DocumentError.tooLarge }
        let savedEncoding = try Self.decode(data).1
        if overwritesOriginal, (try? Self.readData(target).0) != fileData {
            throw DocumentError.changedOnDisk
        }
        try data.write(to: target, options: .atomic)
        return MarkdownDocument(url: destination, text: text, encoding: savedEncoding,
                                modified: try? target.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                                fileData: data)
    }

    static func decode(_ data: Data) throws -> (String, String) {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) { return (text, "UTF-16") }
        if let text = String(data: data, encoding: .utf8), !text.contains("\0") {
            return (text.trimmingBOM, "UTF-8")
        }
        if !data.contains(0), let text = String(data: data, encoding: .windowsCP1252) {
            return (text, "Windows-1252")
        }
        throw DocumentError.invalidEncoding
    }
}

extension String {
    var trimmingBOM: String { hasPrefix("\u{FEFF}") ? String(dropFirst()) : self }
}

enum DocumentError: LocalizedError {
    case tooLarge, invalidEncoding, changedOnDisk
    var errorDescription: String? {
        switch self {
        case .tooLarge: return "Il documento supera il limite di 20 MB."
        case .invalidEncoding: return "Il file non contiene testo leggibile. Usa un file Markdown in UTF-8 o UTF-16."
        case .changedOnDisk: return "Il file è cambiato o è stato spostato. Usa Salva con nome per conservare le tue modifiche in un altro file."
        }
    }
}

enum AssetAccess {
    static let imageExtensions = Set(["png", "jpg", "jpeg", "gif", "webp", "svg", "avif", "heic", "bmp", "tiff", "ico"])
    static func resolve(_ request: URL, inside root: URL) -> URL? {
        guard request.scheme == "carta-asset", request.host == "local" else { return nil }
        let candidate = URL(fileURLWithPath: request.path).standardizedFileURL.resolvingSymlinksInPath()
        let folder = root.standardizedFileURL.resolvingSymlinksInPath()
        guard candidate.path.hasPrefix(folder.path.hasSuffix("/") ? folder.path : folder.path + "/"),
              imageExtensions.contains(candidate.pathExtension.lowercased()) else { return nil }
        return candidate
    }
}
