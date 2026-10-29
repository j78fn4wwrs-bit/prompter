import SwiftUI
import UIKit

/// UITextView wrapper for the script editor. Its built-in drop handling is replaced so that
/// dropped FILES become new scripts (via `onFileDrop`) instead of being pasted into, and
/// overwriting, the open script. Dropped plain text is still inserted at the cursor.
struct ScriptTextView: UIViewRepresentable {
    @Binding var text: String
    var onFileDrop: ([NSItemProvider]) -> Void
    /// Cursor position as a Character offset into `text` (same units as Script.markerOffsets).
    var onCursorChange: (Int) -> Void = { _ in }
    /// Set to a Character offset to move the cursor there and scroll it into view; reset to nil after.
    var jumpTo: Binding<Int?> = .constant(nil)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.adjustsFontForContentSizeCategory = true
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        tv.text = text
        tv.tintColor = UIColor(named: "SPAccent")
        ScriptTextView.styleHeadings(in: tv)
        tv.delegate = context.coordinator
        // Remove UITextView's own drop interaction and use ours.
        for interaction in tv.interactions where interaction is UIDropInteraction {
            tv.removeInteraction(interaction)
        }
        tv.addInteraction(UIDropInteraction(delegate: context.coordinator))
        context.coordinator.textView = tv
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        if tv.text != text {
            let selected = tv.selectedRange
            tv.text = text
            let len = (text as NSString).length
            tv.selectedRange = NSRange(location: min(selected.location, len), length: 0)
            ScriptTextView.styleHeadings(in: tv)
        }
        if let target = jumpTo.wrappedValue {
            let clamped = min(max(target, 0), text.count)
            let index = text.index(text.startIndex, offsetBy: clamped)
            let location = NSRange(index..<index, in: text).location
            let range = NSRange(location: min(location, (tv.text as NSString).length), length: 0)
            tv.selectedRange = range
            tv.scrollRangeToVisible(range)
            let binding = jumpTo
            DispatchQueue.main.async { binding.wrappedValue = nil }
        }
    }

    /// Same rule as ScriptOutline: up to six #, then a space or the end of the line.
    private static func isHeading(_ line: String) -> Bool {
        let trimmed = line.drop(while: { $0 == " " })
        let hashes = trimmed.prefix(while: { $0 == "#" }).count
        guard hashes > 0, hashes <= 6 else { return false }
        let rest = trimmed.dropFirst(hashes)
        return rest.isEmpty || rest.first == " "
    }

    /// Colors "# Chapter" lines in the brand accent and makes them bold. Only attributes change,
    /// never the characters, so the cursor, undo and the saved text are untouched.
    @MainActor
    static func styleHeadings(in tv: UITextView) {
        guard tv.markedTextRange == nil else { return }
        let storage = tv.textStorage
        let full = NSRange(location: 0, length: storage.length)
        let body = UIFont.preferredFont(forTextStyle: .body)
        let headingFont = UIFont.systemFont(ofSize: body.pointSize * 1.1, weight: .bold)
        let accent = UIColor(named: "SPAccent") ?? .systemBlue
        let ns = storage.string as NSString
        storage.beginEditing()
        storage.addAttribute(.font, value: body, range: full)
        storage.addAttribute(.foregroundColor, value: UIColor.label, range: full)
        ns.enumerateSubstrings(in: full, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            if isHeading(ns.substring(with: lineRange)) {
                storage.addAttribute(.font, value: headingFont, range: lineRange)
                storage.addAttribute(.foregroundColor, value: accent, range: lineRange)
            }
        }
        storage.endEditing()
        tv.typingAttributes = [.font: body, .foregroundColor: UIColor.label]
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIDropInteractionDelegate {
        var parent: ScriptTextView
        weak var textView: UITextView?

        init(_ parent: ScriptTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            ScriptTextView.styleHeadings(in: textView)
            parent.text = textView.text
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            // selectedRange is in UTF-16 units; markers use Character offsets.
            let ns = textView.text as NSString
            let location = min(textView.selectedRange.location, ns.length)
            let offset = ns.substring(to: location).count
            let callback = parent.onCursorChange
            DispatchQueue.main.async { callback(offset) }
        }

        // MARK: Drop

        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
            let providers = session.items.map(\.itemProvider)
            return DropImporter.hasImportableFile(providers) || session.canLoadObjects(ofClass: NSString.self)
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
            UIDropProposal(operation: .copy)
        }

        func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
            let providers = session.items.map(\.itemProvider)
            if DropImporter.hasImportableFile(providers) {
                parent.onFileDrop(providers)
                return
            }
            // Plain text snippet: insert at the cursor.
            _ = session.loadObjects(ofClass: NSString.self) { [weak self] objects in
                let snippet = objects.compactMap { $0 as? String }.joined(separator: "\n")
                guard !snippet.isEmpty, let self, let tv = self.textView else { return }
                tv.replace(tv.selectedTextRange ?? tv.textRange(from: tv.endOfDocument, to: tv.endOfDocument)!,
                           withText: snippet)
                self.parent.text = tv.text
            }
        }
    }
}
