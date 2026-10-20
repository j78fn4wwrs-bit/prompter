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
            .navigationTitle("Prompter")
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
                        Button { showImporter = true } label: {
                            Label("Import .txt File", systemImage: "doc.text")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [UTType.plainText],
                          allowsMultipleSelection: false) { result in
                handleImport(result)
            }
            .alert("Import", isPresented: Binding(get: { importError != nil },
                                                  set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
            .alert("Restore Purchase", isPresented: Binding(get: { restoreMessage != nil },
                                                            set: { if !$0 { restoreMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(restoreMessage ?? "")
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
    }

    private func restorePurchases() async {
        store.errorMessage = nil
        await store.restore()
        restoreMessage = store.isPro ? "Prompter Pro is restored." : (store.errorMessage ?? "No previous purchase found.")
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
            importError = "The clipboard doesn't have any text."
            return
        }
        newScript(text: text, title: firstLineTitle(text))
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let text = String(decoding: data, as: UTF8.self)
                newScript(text: text, title: url.deletingPathExtension().lastPathComponent)
            } catch {
                importError = "Couldn't read that file."
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
