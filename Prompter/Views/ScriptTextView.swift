import SwiftUI
import UIKit

/// UITextView wrapper for the script editor. Its built-in drop handling is replaced so that
/// dropped FILES become new scripts (via `onFileDrop`) instead of being pasted into, and
/// overwriting, the open script. Dropped plain text is still inserted at the cursor.
struct ScriptTextView: UIViewRepresentable {
    @Binding var text: String
    var onFileDrop: ([NSItemProvider]) -> Void

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
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIDropInteractionDelegate {
        var parent: ScriptTextView
        weak var textView: UITextView?

        init(_ parent: ScriptTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
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
