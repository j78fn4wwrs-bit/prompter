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
    @State private var cursorOffset = 0
    @State private var renameOffset: Int?
    @State private var renameText = ""
    @State private var markerNote: String?
    @State private var jumpTarget: Int?
    @State private var showMarkerSheet = false
    @AppStorage(PrefKey.editorMarkerPanel) private var showMarkerPanel: Bool = true
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isWide: Bool { horizontalSizeClass == .regular }
    private var markerPoints: [JumpPoint] {
        ScriptOutline.jumpPoints(lines: ScriptOutline.lines(script.text),
                                 markers: script.markerOffsets ?? [],
                                 names: script.markerNames ?? [:]).filter { $0.kind == .marker }
    }

    var body: some View {
        HStack(spacing: 0) {
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
                    LensGlassChip(text: "\(chapters) chapter\(chapters == 1 ? "" : "s")", systemImage: "text.book.closed")
                }
                let markerCount = script.markerOffsets?.count ?? 0
                if markerCount > 0 {
                    // Wide: shows/hides the side panel. Compact (iPhone): opens the list as a sheet.
                    Button {
                        if isWide { showMarkerPanel.toggle() } else { showMarkerSheet = true }
                    } label: {
                        LensGlassChip(text: "\(markerCount) marker\(markerCount == 1 ? "" : "s")", systemImage: "bookmark.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(markerCount) markers, show list")
                }
                Button { addMarkerAtCursor() } label: {
                    if isWide {
                        Label("Add Marker", systemImage: "bookmark")
                    } else {
                        // iPhone: icon-only so the row (and Read time) fits on one line.
                        Label("Add Marker", systemImage: "bookmark").labelStyle(.iconOnly)
                    }
                }
                .buttonStyle(LensGlassButtonStyle(role: .secondary, fontSize: 14, horizontalPadding: 12))
                .fixedSize()
                .accessibilityLabel("Add marker at cursor")
                if let markerNote {
                    // The transient note is the one item allowed to shorten if space runs out.
                    Text(markerNote).foregroundStyle(LensGlassColor.secondaryLabel)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
                if isWide { readTimeButton }
            }
            .font(.caption)
            .foregroundStyle(LensGlassColor.secondaryLabel)
            .padding(.horizontal)
            .padding(.vertical, 6)
            if !isWide {
                // iPhone: Read time gets its own line so it never wraps into a letter column.
                HStack {
                    readTimeButton
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(LensGlassColor.secondaryLabel)
                .padding(.horizontal)
                .padding(.bottom, 6)
            }
            Divider().overlay(LensGlassColor.separator)
            ScriptTextView(text: $script.text, onFileDrop: onFileDrop,
                           onCursorChange: { cursorOffset = $0 },
                           jumpTo: $jumpTarget)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: 820)
        .frame(maxWidth: .infinity)
            if isWide && showMarkerPanel && !markerPoints.isEmpty {
                Divider().overlay(LensGlassColor.separator)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Markers").font(.headline).foregroundStyle(LensGlassColor.label)
                        Spacer()
                        Button { showMarkerPanel = false } label: {
                            Image(systemName: "sidebar.right")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Hide markers list")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    markerList
                }
                .frame(width: 260)
            }
        }
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
        .sheet(isPresented: Binding(get: { renameOffset != nil && !showMarkerSheet },
                                    set: { if !$0 { renameOffset = nil } })) {
            if let offset = renameOffset {
                MarkerEditSheet(script: script, offset: offset) { renameOffset = nil }
            }
        }
        .sheet(isPresented: $showMarkerSheet) {
            NavigationStack {
                markerList
                    .navigationTitle("Markers")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { Button("Done") { showMarkerSheet = false } }
                    }
            }
            .presentationDetents([.medium, .large])
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

    private var readTimeButton: some View {
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
        .lineLimit(1)
        .fixedSize()
    }

    private var markerList: some View {
        List {
            ForEach(markerPoints) { point in
                HStack(spacing: 8) {
                    Button { goTo(point) } label: {
                        HStack {
                            Image(systemName: "bookmark.fill").foregroundStyle(.orange)
                            Text(point.title).foregroundStyle(.primary).lineLimit(2)
                            Spacer()
                            if let offset = markerOffset(of: point) {
                                MarkerTimeText(script: script, offset: offset)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button { beginRename(point) } label: {
                        Image(systemName: "pencil.circle")
                            .font(.title3)
                            .foregroundStyle(LensGlassColor.accent)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Edit marker")
                }
                .contextMenu {
                    Button { beginRename(point) } label: { Label("Edit Marker", systemImage: "pencil") }
                    Button(role: .destructive) { deleteMarker(point) } label: { Label("Delete", systemImage: "trash") }
                }
                .swipeActions {
                    Button(role: .destructive) { deleteMarker(point) } label: { Label("Delete", systemImage: "trash") }
                    Button { beginRename(point) } label: { Label("Edit", systemImage: "pencil") }
                        .tint(LensGlassColor.accent)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .tint(LensGlassColor.accent)
        .sheet(isPresented: Binding(get: { renameOffset != nil && showMarkerSheet },
                                    set: { if !$0 { renameOffset = nil } })) {
            if let offset = renameOffset {
                MarkerEditSheet(script: script, offset: offset) { renameOffset = nil }
            }
        }
    }

    private func markerOffset(of point: JumpPoint) -> Int? {
        guard point.kind == .marker else { return nil }
        return Int(point.id.dropFirst())
    }

    private func goTo(_ point: JumpPoint) {
        guard let offset = markerOffset(of: point) else { return }
        jumpTarget = offset
        showMarkerSheet = false
    }

    private func beginRename(_ point: JumpPoint) {
        guard let offset = markerOffset(of: point) else { return }
        renameText = script.markerName(for: offset)
        renameOffset = offset
    }

    private func deleteMarker(_ point: JumpPoint) {
        guard let offset = markerOffset(of: point) else { return }
        script.removeMarker(at: offset)
    }

    /// Marks the line the cursor is on, the same way the prompter's bookmark button does.
    private func addMarkerAtCursor() {
        let offset = min(max(cursorOffset, 0), script.text.count)
        guard let added = script.addMarker(atLineContaining: offset) else {
            showMarkerNote("Already marked")
            return
        }
        renameText = script.defaultMarkerName(for: added)
        renameOffset = added
    }

    private func showMarkerNote(_ text: String) {
        markerNote = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            markerNote = nil
        }
    }
}
