import SwiftUI

/// The Carbon visual identity: graphite and ivory, olive for accents. Adapts to light and dark mode.
enum Brand {
    static let ivoryHex = 0xF4F3EC, graphiteHex = 0x202320

    /// Window background.
    static let background = dynamic(light: 0xF4F3EC, dark: 0x0F100F)
    /// Cards and panels.
    static let panel = dynamic(light: 0xEAE8DF, dark: 0x1A1B19)
    static let border = dynamic(light: 0xD9D6CA, dark: 0x2C2E2A)
    /// Primary text and the main accent (buttons, selection).
    static let ink = dynamic(light: 0x161716, dark: 0xF4F3EC)
    /// The colour drawn on top of `ink` (button labels).
    static let onInk = dynamic(light: 0xF4F3EC, dark: 0x161716)
    static let muted = dynamic(light: 0x6E716B, dark: 0x8E9089)
    static let olive = Color(nsColor: NSColor(rgb: 0xB6BB98))

    static func dynamic(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(rgb: dark) : NSColor(rgb: light)
        })
    }

    /// Headings in the brand voice: medium weight, tight tracking.
    static func heading(_ size: CGFloat) -> Font { .system(size: size, weight: .medium) }
}

extension NSColor {
    convenience init(rgb: Int) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

/// A big heading with brand tracking.
struct BrandTitle: View {
    let text: String
    var size: CGFloat = 34
    init(_ text: String, size: CGFloat = 34) { self.text = text; self.size = size }
    var body: some View {
        Text(text).font(Brand.heading(size)).tracking(-size * 0.03).foregroundStyle(Brand.ink)
    }
}

/// Primary action: an ink-filled pill.
struct BrandButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Brand.onInk)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Capsule().fill(Brand.ink.opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.3)))
    }
}

/// Secondary action: a quiet outlined pill.
struct BrandQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Brand.ink)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Capsule().fill(Brand.panel.opacity(configuration.isPressed ? 0.6 : 1)))
            .overlay(Capsule().stroke(Brand.border))
    }
}

extension ButtonStyle where Self == BrandButtonStyle { static var brand: BrandButtonStyle { BrandButtonStyle() } }
extension ButtonStyle where Self == BrandQuietButtonStyle { static var brandQuiet: BrandQuietButtonStyle { BrandQuietButtonStyle() } }

/// A brand card: panel fill with a hairline border.
struct BrandCard: ViewModifier {
    var radius: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius).fill(Brand.panel))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Brand.border))
    }
}

extension View {
    func brandCard(radius: CGFloat = 12) -> some View { modifier(BrandCard(radius: radius)) }
}
