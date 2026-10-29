import SwiftUI

// D1 "Lens Glass" button system (Jim's spec, Steady Prompter v1.1).
// Every color here is a named asset in Assets.xcassets (light/dark where the spec has both).

/// Named color assets used by the Lens Glass styles. Keep in sync with Assets.xcassets.
enum LensGlassColor {
    static let yellow = Color("SPYellow")
    static let backgroundTop = Color("SPBackgroundTop")
    static let backgroundBottom = Color("SPBackgroundBottom")
    static let label = Color("SPLabel")
    static let secondaryLabel = Color("SPSecondaryLabel")
    static let card = Color("SPCard")
    static let separator = Color("SPSeparator")
    static let accent = Color("SPAccent")
    static let connected = Color("SPConnected")

    static let primaryTop = Color("D1PrimaryTop")
    static let primaryBottom = Color("D1PrimaryBottom")
    static let primaryLabel = Color("D1PrimaryLabel")
    static let secondaryTop = Color("D1SecondaryTop")
    static let secondaryBottom = Color("D1SecondaryBottom")
    static let secondaryLabelGlyph = Color("D1SecondaryLabel")
    static let utilityTop = Color("D1UtilityTop")
    static let utilityBottom = Color("D1UtilityBottom")
    static let utilityLabel = Color("D1UtilityLabel")
    static let rimLight = Color("D1RimLight")
    static let rimMid = Color("D1RimMid")
    static let rimDark = Color("D1RimDark")
    static let disabledTop = Color("D1DisabledTop")
    static let disabledBottom = Color("D1DisabledBottom")
    static let disabledLabel = Color("D1DisabledLabel")
    static let toggleOff = Color("D1ToggleOff")
    static let sliderTrack = Color("D1SliderTrack")

    static var rim: LinearGradient {
        LinearGradient(colors: [rimLight, rimMid, rimDark], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum LensGlassRole { case primary, secondary, utility }

/// Capsule lens-glass button. Give it a square frame (e.g. 60×60) and it becomes the circle variant.
struct LensGlassButtonStyle: ButtonStyle {
    var role: LensGlassRole = .secondary
    var isActive: Bool = false
    var fontSize: CGFloat = 24
    var horizontalPadding: CGFloat = 20

    func makeBody(configuration: Configuration) -> some View {
        LensGlassButtonBody(configuration: configuration, role: role, isActive: isActive,
                            fontSize: fontSize, horizontalPadding: horizontalPadding)
    }
}

private struct LensGlassButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let role: LensGlassRole
    let isActive: Bool
    let fontSize: CGFloat
    let horizontalPadding: CGFloat

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    private var topColor: Color {
        guard isEnabled else { return LensGlassColor.disabledTop }
        switch role {
        case .primary: return LensGlassColor.primaryTop
        case .secondary: return LensGlassColor.secondaryTop
        case .utility: return LensGlassColor.utilityTop
        }
    }

    private var bottomColor: Color {
        guard isEnabled else { return LensGlassColor.disabledBottom }
        switch role {
        case .primary: return LensGlassColor.primaryBottom
        case .secondary: return LensGlassColor.secondaryBottom
        case .utility: return LensGlassColor.utilityBottom
        }
    }

    private var labelColor: Color {
        guard isEnabled else { return LensGlassColor.disabledLabel }
        switch role {
        case .primary: return LensGlassColor.primaryLabel
        case .secondary: return LensGlassColor.secondaryLabelGlyph
        case .utility: return LensGlassColor.utilityLabel
        }
    }

    private var glows: Bool { role == .primary || isActive }

    private var shadowColor: Color {
        guard isEnabled else { return .clear }
        if glows { return LensGlassColor.yellow.opacity(0.45) }
        return Color.black.opacity(colorScheme == .dark ? 0.55 : 0.25)
    }

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.system(size: fontSize, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(labelColor)
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
            .contentShape(Capsule())
            .background { glass(pressed: pressed) }
            .shadow(color: shadowColor, radius: role == .primary ? 10 : 6, x: 0, y: 6)
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: pressed)
    }

    private func glass(pressed: Bool) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Capsule()
                    .fill(LinearGradient(colors: [topColor, bottomColor], startPoint: .top, endPoint: .bottom))
                if isEnabled {
                    Capsule()
                        .fill(Color.white.opacity(role == .primary ? 0.32 : 0.14))
                        .frame(height: proxy.size.height * 0.42)
                        .padding(.horizontal, min(8, proxy.size.width * 0.15))
                        .padding(.top, 5)
                }
                Capsule().strokeBorder(LensGlassColor.rim, lineWidth: 3)
                if isActive && isEnabled && role != .primary {
                    Capsule().strokeBorder(LensGlassColor.yellow, lineWidth: 3).padding(2)
                }
                if pressed {
                    Capsule().fill(Color.black.opacity(0.28))
                }
            }
        }
    }
}

/// Lens Glass switch: Yellow track with a navy-glass knob when on.
struct LensGlassToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        LensGlassToggleBody(configuration: configuration)
    }
}

private struct LensGlassToggleBody: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            configuration.$isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 12) {
                configuration.label
                Spacer(minLength: 8)
                track
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }

    private var track: some View {
        ZStack(alignment: configuration.isOn ? .trailing : .leading) {
            Capsule()
                .fill(configuration.isOn ? LensGlassColor.yellow : LensGlassColor.toggleOff)
                .frame(width: 64, height: 36)
            knob.padding(4)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: configuration.isOn)
    }

    private var knob: some View {
        ZStack(alignment: .topLeading) {
            Circle()
                .fill(LinearGradient(colors: [LensGlassColor.secondaryTop, LensGlassColor.secondaryBottom],
                                     startPoint: .top, endPoint: .bottom))
            Circle().strokeBorder(LensGlassColor.rim, lineWidth: 2)
            Circle()
                .fill(Color.white.opacity(0.85))
                .frame(width: 6, height: 6)
                .offset(x: 8, y: 7)
        }
        .frame(width: 28, height: 28)
    }
}

/// Faint lens-ring watermark behind the remote header.
struct LensRingWatermark: View {
    var body: some View {
        Circle()
            // SPAccent is Navy in light mode and Yellow in dark mode, as the spec asks.
            .stroke(LensGlassColor.accent, lineWidth: 22)
            .opacity(0.07)
            .frame(width: 300, height: 300)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - App-wide branded surfaces (D1)

/// Soft navy (dark) / pale blue (light) gradient used behind lists, sheets and empty states.
struct LensGlassBackground: View {
    var body: some View {
        LinearGradient(colors: [LensGlassColor.backgroundTop, LensGlassColor.backgroundBottom],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

/// Small rounded glass tile holding an SF Symbol (list rows, paywall header, feature rows).
struct LensGlassIconTile: View {
    let systemName: String
    var size: CGFloat = 36
    var symbolSize: CGFloat = 16

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: symbolSize, weight: .semibold))
            .foregroundStyle(LensGlassColor.secondaryLabelGlyph)
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(LinearGradient(colors: [LensGlassColor.secondaryTop, LensGlassColor.secondaryBottom],
                                         startPoint: .top, endPoint: .bottom))
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(LensGlassColor.rim, lineWidth: 1.5)
            }
            .accessibilityHidden(true)
    }
}

/// Branded replacement for ContentUnavailableView: lens ring, glass tile, title and message.
struct LensGlassEmptyState: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                LensRingWatermark()
                    .scaleEffect(0.5)
                    .frame(width: 150, height: 150)
                LensGlassIconTile(systemName: systemImage, size: 72, symbolSize: 32)
            }
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(LensGlassColor.label)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.body)
                .foregroundStyle(LensGlassColor.secondaryLabel)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Small capsule chip for meta info ("120 words", "2 chapters").
struct LensGlassChip: View {
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).accessibilityHidden(true)
            }
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(LensGlassColor.label)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(LensGlassColor.yellow.opacity(0.3), in: Capsule())
        // Never truncate a chip ("93 w…"): chips keep their full width.
        .fixedSize()
    }
}
