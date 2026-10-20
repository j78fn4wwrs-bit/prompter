import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

struct ScriptListView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var store: ProStore
    @State private var restoreMessage: String?
    @Query(sort: \Script.updatedAt, order: .reverse) private var scripts: [Script]
    @AppStorage(PrefKey.seeded) private var seeded = false

    @State private var selection: Script?
    @State private var showImporter = false
    @State private var importError: String?
    @State private var pasteError: String?

    var body: some View {
        NavigationSplitView {
            Group {
                if scripts.isEmpty {
                    ContentUnavailableView {
                        Label("No scripts yet", systemImage: "text.alignleft")
                    } description: {
                        Text("Tap + to write, paste or import a script.")
                    }
                } else {
                    List(selection: $selection) {
                        ForEach(scripts) { script in
                            NavigationLink(value: script) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(script.title.isEmpty ? "Untitled" : script.title)
                                        .font(.headline)
                                    Text("\(script.wordCount) words · \(script.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Steady Prompter")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        if store.isPro {
                            Label("Pro Unlocked", systemImage: "checkmark.seal.fill")
                        }
                        Button {
                            Task { await restorePurchases() }
                        } label: {
                            Label("Restore Purchase", systemImage: "arrow.clockwise")
                        }
                        .disabled(store.isBusy)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { newScript(text: "") } label: {
                            Label("New Script", systemImage: "square.and.pencil")
                        }
                        Button { pasteScript() } label: {
                            Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                        }
                        Button { presentImporter() } label: {
                            Label("Import File (Text, PDF, Word, Pages)", systemImage: "doc.text")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear(perform: seedIfNeeded)
            .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 420)
        } detail: {
            if let selection {
                ScriptEditorView(script: selection)
                    .id(selection.persistentModelID)
            } else {
                ContentUnavailableView {
                    Label("Pick a script", systemImage: "text.alignleft")
                } description: {
                    Text("Choose a script on the left, or tap + to write a new one.")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        // Presentation modifiers live on the split view itself (one stable container), not on the
        // sidebar column. On iPad the sidebar can be collapsed/hidden (portrait), and modifiers
        // attached to a hidden column never present - that's why Import did nothing.
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: ScriptImporter.allowedContentTypes,
                      allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .alert("Couldn't Import File", isPresented: Binding(get: { importError != nil },
                                                            set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .alert("Nothing to Paste", isPresented: Binding(get: { pasteError != nil },
                                                        set: { if !$0 { pasteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(pasteError ?? "")
        }
        .alert("Restore Purchase", isPresented: Binding(get: { restoreMessage != nil },
                                                        set: { if !$0 { restoreMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreMessage ?? "")
        }
    }

    /// Opens the Files picker after the + menu has finished dismissing; presenting while the
    /// menu is still animating out can be silently dropped on iPad.
    private func presentImporter() {
        importError = nil
        pasteError = nil
        DispatchQueue.main.async { showImporter = true }
    }

    private func restorePurchases() async {
        store.errorMessage = nil
        await store.restore()
        restoreMessage = store.isPro ? "Steady Prompter Pro is restored." : (store.errorMessage ?? "No previous purchase found.")
        store.errorMessage = nil
    }

    private func seedIfNeeded() {
        guard !seeded else { return }
        seeded = true
        if scripts.isEmpty {
            context.insert(Script(title: "Welcome", text: Script.sampleText))
        }
    }

    private func newScript(text: String, title: String = "") {
        let script = Script(title: title, text: text)
        context.insert(script)
        selection = script
    }

    private func pasteScript() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            pasteError = "The clipboard doesn't have any text. Copy your script first, then try again."
            return
        }
        newScript(text: text, title: firstLineTitle(text))
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let imported = try ScriptImporter.importFile(at: url)
                newScript(text: imported.body, title: imported.title)
            } catch {
                importError = (error as? LocalizedError)?.errorDescription ?? "Couldn't read that file."
            }
        case .failure:
            importError = "Couldn't open that file."
        }
    }

    private func firstLineTitle(_ text: String) -> String {
        let line = text.split(separator: "\n").first.map(String.init) ?? ""
        return String(line.trimmingCharacters(in: .whitespaces).prefix(40))
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            if selection == scripts[index] { selection = nil }
            context.delete(scripts[index])
        }
    }
}
