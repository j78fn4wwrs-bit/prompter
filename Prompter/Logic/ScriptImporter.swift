import Foundation
import PDFKit
import UniformTypeIdentifiers
import Compression

/// Turns a picked file into a script (title + body).
/// Supports plain text, RTF, PDF, Word .docx, legacy .doc (best effort) and Pages (via its preview PDF).
enum ScriptImporter {

    struct ImportError: LocalizedError, Equatable {
        let message: String
        var errorDescription: String? { message }
        static let unreadable = ImportError(message: "Couldn't read that file. Make sure it has finished downloading and try again.")
        static let empty = ImportError(message: "That file doesn't contain any text to prompt.")
        static let unsupported = ImportError(message: "That file type isn't supported. Import a plain text, RTF, PDF, Word (.docx) or Pages file.")
        static let pages = ImportError(message: "This Pages file can't be read directly. Export from Pages as PDF, Word, or plain text, then import.")
        static let legacyDoc = ImportError(message: "Older Word (.doc) files can't be read. Open it in Word or Pages, save as .docx (or PDF), then import.")
        static let scannedPDF = ImportError(message: "This PDF has no selectable text (it may be a scan). Export it with text, or paste the script instead.")
    }

    static let docxType = UTType("org.openxmlformats.wordprocessingml.document") ?? UTType(importedAs: "org.openxmlformats.wordprocessingml.document")
    static let docType = UTType("com.microsoft.word.doc") ?? UTType(importedAs: "com.microsoft.word.doc")
    static let pagesTypes: [UTType] = ["com.apple.iwork.pages.sec.pages", "com.apple.iwork.pages.pages"]
        .map { UTType($0) ?? UTType(importedAs: $0) }

    /// Types offered in the file picker.
    static var allowedContentTypes: [UTType] {
        [.plainText, .text, .rtf, .pdf, docxType, docType] + pagesTypes
    }

    // MARK: - Entry point for picked URLs

    /// Reads a URL returned by `.fileImporter`: opens the security scope, coordinates the read
    /// (downloads iCloud / provider files), copies to a temp location right away, then parses.
    static func importFile(at url: URL) throws -> (title: String, body: String) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let localCopy = tempDir.appendingPathComponent(url.lastPathComponent)

        var coordError: NSError?
        var copyError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordError) { readURL in
            do { try FileManager.default.copyItem(at: readURL, to: localCopy) } catch { copyError = error }
        }
        if coordError != nil || copyError != nil {
            throw ImportError.unreadable
        }

        let title = url.deletingPathExtension().lastPathComponent
        let body = try extractText(from: localCopy)
        return (title, body)
    }

    // MARK: - Parsing (testable, works on local file URLs)

    static func extractText(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        let type = UTType(filenameExtension: ext)
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

        let text: String
        if ext == "pages" || (type.map { t in pagesTypes.contains { t.conforms(to: $0) } } ?? false) {
            text = try pagesText(url, isDirectory: isDir.boolValue)
        } else if ext == "docx" || type?.conforms(to: docxType) == true {
            text = try docxText(try Data(contentsOf: url))
        } else if ext == "doc" || type?.conforms(to: docType) == true {
            text = try legacyDocText(try Data(contentsOf: url))
        } else if ext == "pdf" || type?.conforms(to: .pdf) == true {
            text = try pdfText(PDFDocument(url: url))
        } else if ext == "rtf" || type?.conforms(to: .rtf) == true {
            text = try rtfText(try Data(contentsOf: url))
        } else if type == nil || type?.conforms(to: .text) == true || ext == "txt" {
            text = try plainText(try Data(contentsOf: url))
        } else {
            throw ImportError.unsupported
        }

        let cleaned = normalize(text)
        if cleaned.isEmpty { throw ext == "pdf" ? ImportError.scannedPDF : ImportError.empty }
        return cleaned
    }

    static func plainText(_ data: Data) throws -> String {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            if let s = String(data: data, encoding: .utf16) { return s }
        }
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(decoding: data.dropFirst(3), as: UTF8.self)
        }
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .windowsCP1252) { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        throw ImportError.unreadable
    }

    static func rtfText(_ data: Data) throws -> String {
        guard let attr = try? NSAttributedString(data: data,
                                                 options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                 documentAttributes: nil) else {
            throw ImportError.unreadable
        }
        return attr.string
    }

    static func pdfText(_ doc: PDFDocument?) throws -> String {
        guard let doc else { throw ImportError.unreadable }
        var pages: [String] = []
        for i in 0..<doc.pageCount {
            if let s = doc.page(at: i)?.string, !s.isEmpty { pages.append(s) }
        }
        return pages.joined(separator: "\n\n")
    }

    static func legacyDocText(_ data: Data) throws -> String {
        // Some ".doc" files are really RTF; real binary Word 97 files can't be read on iOS.
        if data.starts(with: Array("{\\rtf".utf8)),
           let s = try? rtfText(data), !normalize(s).isEmpty {
            return s
        }
        throw ImportError.legacyDoc
    }

    static func docxText(_ data: Data) throws -> String {
        guard let xml = try? ZipReader(data: data).file(named: "word/document.xml") else {
            throw ImportError(message: "That Word file couldn't be opened. Try saving it again as .docx or PDF.")
        }
        return DocxTextExtractor.text(from: xml)
    }

    static func pagesText(_ url: URL, isDirectory: Bool) throws -> String {
        let pdfData: Data?
        if isDirectory {
            pdfData = try? Data(contentsOf: url.appendingPathComponent("QuickLook/Preview.pdf"))
        } else {
            let zip = try? ZipReader(data: Data(contentsOf: url))
            pdfData = (try? zip?.file(named: "QuickLook/Preview.pdf")) ?? nil
        }
        guard let pdfData, let doc = PDFDocument(data: pdfData),
              let text = try? pdfText(doc), !normalize(text).isEmpty else {
            throw ImportError.pages
        }
        return text
    }

    static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{0C}", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Minimal ZIP reader (stored + deflate)

struct ZipReader {
    struct Entry { let name: String; let method: UInt16; let compressedSize: Int; let size: Int; let localOffset: Int }
    enum ZipError: Error { case notZip, missing, corrupt }

    private let data: [UInt8]
    private(set) var entries: [String: Entry] = [:]

    init(data: Data) throws {
        self.data = [UInt8](data)
        try readCentralDirectory()
    }

    private func u16(_ o: Int) -> Int { Int(data[o]) | Int(data[o + 1]) << 8 }
    private func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }

    private mutating func readCentralDirectory() throws {
        guard data.count >= 22 else { throw ZipError.notZip }
        var eocd = -1
        var i = data.count - 22
        let floor = max(0, data.count - 22 - 65_535)
        while i >= floor {
            if data[i] == 0x50, data[i + 1] == 0x4B, data[i + 2] == 0x05, data[i + 3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notZip }
        let count = u16(eocd + 10)
        var p = u32(eocd + 16)
        for _ in 0..<count {
            guard p + 46 <= data.count, u32(p) == 0x0201_4B50 else { throw ZipError.corrupt }
            let method = UInt16(u16(p + 10))
            let csize = u32(p + 20), usize = u32(p + 24)
            let nlen = u16(p + 28), elen = u16(p + 30), clen = u16(p + 32)
            let offset = u32(p + 42)
            guard p + 46 + nlen <= data.count else { throw ZipError.corrupt }
            let name = String(decoding: data[(p + 46)..<(p + 46 + nlen)], as: UTF8.self)
            entries[name] = Entry(name: name, method: method, compressedSize: csize, size: usize, localOffset: offset)
            p += 46 + nlen + elen + clen
        }
    }

    func file(named name: String) throws -> Data {
        guard let e = entries[name] else { throw ZipError.missing }
        let lo = e.localOffset
        guard lo + 30 <= data.count, u32(lo) == 0x0403_4B50 else { throw ZipError.corrupt }
        let start = lo + 30 + u16(lo + 26) + u16(lo + 28)
        guard start + e.compressedSize <= data.count else { throw ZipError.corrupt }
        let slice = Array(data[start..<(start + e.compressedSize)])
        switch e.method {
        case 0: return Data(slice)
        case 8: return try Self.inflate(slice, expected: e.size)
        default: throw ZipError.corrupt
        }
    }

    /// Raw DEFLATE via Compression's COMPRESSION_ZLIB (which is raw deflate, no zlib header).
    static func inflate(_ src: [UInt8], expected: Int) throws -> Data {
        guard expected > 0 else { return Data() }
        let capacity = expected + 64
        var dst = [UInt8](repeating: 0, count: capacity)
        let written = src.withUnsafeBufferPointer { s in
            dst.withUnsafeMutableBufferPointer { d in
                compression_decode_buffer(d.baseAddress!, capacity, s.baseAddress!, s.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { throw ZipError.corrupt }
        return Data(dst[0..<written])
    }
}

// MARK: - word/document.xml text extraction

final class DocxTextExtractor: NSObject, XMLParserDelegate {
    private var out = ""
    private var inText = false

    static func text(from xml: Data) -> String {
        let delegate = DocxTextExtractor()
        let parser = XMLParser(data: xml)
        parser.shouldProcessNamespaces = false
        parser.delegate = delegate
        parser.parse()
        return delegate.out
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "w:t": inText = true
        case "w:tab": out += "\t"
        case "w:br", "w:cr": out += "\n"
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "w:t": inText = false
        case "w:p": out += "\n"
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { out += string }
    }
}
