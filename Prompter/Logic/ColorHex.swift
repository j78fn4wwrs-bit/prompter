import SwiftUI

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    func hexString() -> String {
        // ColorPicker colors are often Display P3. UIColor.getRed returns false for
        // those and would store black. Resolved components are sRGB.
        let resolved = resolve(in: EnvironmentValues())
        func channel(_ value: Float) -> Int {
            Int((min(max(value, 0), 1) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", channel(resolved.red), channel(resolved.green), channel(resolved.blue))
    }
}

/// Shared prompter preferences (stored in UserDefaults via @AppStorage keys).
enum PrefKey {
    static let speed = "speed"
    static let fontSize = "fontSize"
    static let mirror = "mirror"
    static let textHex = "textHex"
    static let backgroundHex = "backgroundHex"
    static let seeded = "seededSample"
    static let prompterMarkerRail = "prompterMarkerRail"
    static let editorMarkerPanel = "editorMarkerPanel"
}
