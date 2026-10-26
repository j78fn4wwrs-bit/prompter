import SwiftUI
import SwiftData

struct ScriptEditorView: View {
    @Bindable var script: Script
    /// Creates new scripts from dropped files (handled by the script list).
    var onFileDrop: ([NSItemProvider]) -> Void = { _ in }
    @EnvironmentObject private var store: ProStore
    @State private var showPrompter = false
    @State private var paywallFeature: ProFeature?
    @AppStorage(PrefKey.speed) private var speed: Double = 60

    var body: some View {
        VStack(spacing: 0) {
            TextField("Title", text: $script.title)
                .font(.title2.bold())
                .foregroundStyle(LensGlassColor.label)
                .padding(.horizontal)
                .padding(.top, 8)
            HStack(spacing: 8) {
                LensGlassChip(text: "\(script.wordCount) words", systemImage: "text.word.spacing")
                let chapters = ScriptOutline.lines(script.text).filter { $0.headingLevel > 0 }.count
                if chapters > 0 {
                    LensGlassChip(text: "\(chapters) chapter\(chapters == 1 ? "" : "s")", systemImage: "bookmark.fill")
                }
                Spacer()
                Button {
                    if !store.isPro { paywallFeature = .readTime }
                } label: {
                    if store.isPro {
                        Label("~\(script.readTime()) read", systemImage: "clock")
                    } else {
                        Label("Read time", systemImage: "lock.fill")
                    }
                }
                .buttonStyle(.borderless)
            }
            .font(.caption)
            .foregroundStyle(LensGlassColor.secondaryLabel)
            .padding(.horizontal)
            .padding(.vertical, 6)
            Divider().overlay(LensGlassColor.separator)
            ScriptTextView(text: $script.text, onFileDrop: onFileDrop)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: 820)
        .frame(maxWidth: .infinity)
        .background(LensGlassColor.card.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showPrompter = true
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .disabled(script.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onChange(of: script.text) { _, _ in script.updatedAt = Date() }
        .onChange(of: script.title) { _, _ in script.updatedAt = Date() }
        .fullScreenCover(isPresented: $showPrompter) {
            PrompterView(script: script)
                .environmentObject(store)
        }
        .sheet(item: $paywallFeature) { feature in
            PaywallView(feature: feature).environmentObject(store)
        }
        .onDrop(of: DropImporter.acceptedTypes, isTargeted: nil) { providers in
            guard DropImporter.hasImportableFile(providers) else { return false }
            onFileDrop(providers)
            return true
        }
    }
}
