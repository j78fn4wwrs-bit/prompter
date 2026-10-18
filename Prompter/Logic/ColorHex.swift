import SwiftUI
import UIKit

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
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int(max(0, min(1, r)) * 255)
        let gi = Int(max(0, min(1, g)) * 255)
        let bi = Int(max(0, min(1, b)) * 255)
        return String(format: "#%02X%02X%02X", ri, gi, bi)
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
}
