import SwiftUI
import SwiftData

struct ScriptEditorView: View {
    @Bindable var script: Script
    @EnvironmentObject private var store: ProStore
    @State private var showPrompter = false
    @State private var showPaywall = false
    @AppStorage(PrefKey.speed) private var speed: Double = 60

    var body: some View {
        VStack(spacing: 0) {
            TextField("Title", text: $script.title)
                .font(.title2.bold())
                .padding(.horizontal)
                .padding(.top, 8)
            HStack {
                Text("\(script.wordCount) words")
                Spacer()
                Button {
                    if !store.isPro { showPaywall = true }
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
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 6)
            Divider()
            TextEditor(text: $script.text)
                .font(.body)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: 820)
        .frame(maxWidth: .infinity)
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
            PrompterView(text: script.text)
                .environmentObject(store)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(store)
        }
    }
}
