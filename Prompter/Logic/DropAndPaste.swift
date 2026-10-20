import Foundation
import UIKit
import UniformTypeIdentifiers

/// Turns dropped files into new scripts via ScriptImporter.
enum DropImporter {
    /// Type identifiers we look for on a dropped item, most specific first.
    static var acceptedTypes: [UTType] {
        ScriptImporter.allowedContentTypes + [.fileURL]
    }

    /// True if at least one provider looks like a file we can import (not just a text snippet).
    static func hasImportableFile(_ providers: [NSItemProvider]) -> Bool {
        providers.contains { fileTypeIdentifier(for: $0) != nil }
    }

    /// The registered type to load as a file. Plain-text-only snippets (no file name) return nil
    /// so they can still be inserted as text in the editor.
    static func fileTypeIdentifier(for provider: NSItemProvider) -> String? {
        let ids = provider.registeredTypeIdentifiers
        let isFileLike = provider.suggestedName != nil || ids.contains(UTType.fileURL.identifier)
        for id in ids {
            guard let type = UTType(id) else { continue }
            if type == .fileURL { continue }
            if ScriptImporter.allowedContentTypes.contains(where: { type.conforms(to: $0) }) {
                // A bare "public.utf8-plain-text" drag from another app's selection has no name.
                if type.conforms(to: .plainText) && !isFileLike { continue }
                return id
            }
        }
        return nil
    }

    /// Loads each importable provider and calls `completion` on the main queue per file.
    static func importProviders(_ providers: [NSItemProvider],
                                completion: @escaping (Result<(title: String, body: String), Error>) -> Void) {
        for provider in providers {
            guard let typeID = fileTypeIdentifier(for: provider) else { continue }
            let suggested = provider.suggestedName
            _ = provider.loadFileRepresentation(forTypeIdentifier: typeID) { url, error in
                // The temp file is only valid inside this callback, so read it now.
                let result: Result<(title: String, body: String), Error>
                if let url {
                    do {
                        var imported = try ScriptImporter.importFile(at: url)
                        if let suggested, !suggested.isEmpty {
                            imported.title = (suggested as NSString).deletingPathExtension
                        }
                        result = .success(imported)
                    } catch {
                        result = .failure(error)
                    }
                } else {
                    result = .failure(error ?? ScriptImporter.ImportError.unreadable)
                }
                DispatchQueue.main.async { completion(result) }
            }
        }
    }
}

enum ClipboardReader {
    /// Reads text from the general pasteboard: plain string, then multiple strings, then RTF/attributed.
    /// Accessing it shows iOS's "Allow Paste" prompt when needed, which is the expected behavior.
    static func text() -> String? {
        let pb = UIPasteboard.general
        if let s = pb.string, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
        if let all = pb.strings, !all.isEmpty {
            let joined = all.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return joined }
        }
        let rich: [(String, NSAttributedString.DocumentType)] = [
            (UTType.rtf.identifier, .rtf),
            (UTType.flatRTFD.identifier, .rtfd),
            (UTType.html.identifier, .html),
        ]
        for (typeID, docType) in rich {
            if let data = pb.data(forPasteboardType: typeID),
               let attr = try? NSAttributedString(data: data,
                                                  options: [.documentType: docType],
                                                  documentAttributes: nil) {
                let s = attr.string
                if !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
            }
        }
        return nil
    }
}
