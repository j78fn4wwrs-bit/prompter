import SwiftUI

/// Timecode text: "M:SS" under an hour, "H:MM:SS" from an hour. Accepts MM:SS or HH:MM:SS (or plain seconds).
enum Timecode {
    static func format(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    /// nil when the text is not a valid timecode. Minutes and seconds must be 0–59 after the first field.
    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard (1...3).contains(parts.count) else { return nil }
        var values: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let v = Int(part) else { return nil }
            values.append(v)
        }
        for v in values.dropFirst() where v > 59 { return nil }
        var total = 0
        for v in values { total = total * 60 + v }
        return Double(total)
    }
}

/// Right-aligned time for a marker row: the set timecode, or the estimate in grey italics.
struct MarkerTimeText: View {
    let script: Script
    let offset: Int
    var color: Color = .primary

    var body: some View {
        if let set = script.markerTimecode(for: offset) {
            Text(Timecode.format(set))
                .font(.footnote.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
                .accessibilityLabel("Timecode \(Timecode.format(set))")
        } else {
            Text("~" + Timecode.format(script.estimatedSeconds(for: offset)))
                .font(.footnote.monospacedDigit().italic())
                .foregroundStyle(color.opacity(0.5))
                .accessibilityLabel("Estimated time \(Timecode.format(script.estimatedSeconds(for: offset)))")
        }
    }
}

/// Edit a marker's label and timecode. Replaces the old rename alerts.
struct MarkerEditSheet: View {
    let script: Script
    let offset: Int
    var onClose: () -> Void = {}

    @State private var label = ""
    @State private var timecodeText = ""
    @State private var loaded = false

    private var trimmedTimecode: String { timecodeText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var timecodeValid: Bool { trimmedTimecode.isEmpty || Timecode.parse(trimmedTimecode) != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Label") {
                    TextField(script.defaultMarkerName(for: offset), text: $label)
                        .textInputAutocapitalization(.sentences)
                }
                Section {
                    TextField("MM:SS or HH:MM:SS", text: $timecodeText)
                        .keyboardType(.numbersAndPunctuation)
                        .font(.body.monospacedDigit())
                    if !timecodeValid {
                        Text("Use MM:SS or HH:MM:SS, for example 1:05 or 1:02:30.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    Button {
                        timecodeText = Timecode.format(script.estimatedSeconds(for: offset))
                    } label: {
                        Label("Use estimated time (~\(Timecode.format(script.estimatedSeconds(for: offset))))",
                              systemImage: "clock")
                    }
                    .buttonStyle(LensGlassButtonStyle(role: .secondary, fontSize: 15, horizontalPadding: 14))
                    .frame(height: 44)
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Timecode")
                } footer: {
                    Text("Leave empty for no timecode. The estimate uses the words before this marker at a 150 words-per-minute read.")
                }
                Section {
                    Button(role: .destructive) {
                        script.removeMarker(at: offset)
                        onClose()
                    } label: {
                        Label("Delete Marker", systemImage: "trash")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LensGlassBackground())
            .tint(LensGlassColor.accent)
            .navigationTitle("Edit Marker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onClose() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!timecodeValid)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            guard !loaded else { return }
            loaded = true
            label = script.markerName(for: offset)
            if let t = script.markerTimecode(for: offset) { timecodeText = Timecode.format(t) }
        }
    }

    private func save() {
        script.renameMarker(at: offset, to: label)
        script.setMarkerTimecode(trimmedTimecode.isEmpty ? nil : Timecode.parse(trimmedTimecode), for: offset)
        onClose()
    }
}
