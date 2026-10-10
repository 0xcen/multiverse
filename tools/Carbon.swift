import SwiftUI

// Carbon brand pieces shared by the launch image and the launch video.

enum Carbon {
    static let bg = Color(hex: 0x0F100F)
    static let panel = Color(hex: 0x1A1B19)
    static let panelHeader = Color(hex: 0x1E201D)
    static let border = Color(hex: 0x2C2E2A)
    static let tile = Color(hex: 0x262825)
    static let ivory = Color(hex: 0xF4F3EC)
    static let gray = Color(hex: 0x767973)
    static let muted = Color(hex: 0x8E9089)
    static let graphite = Color(hex: 0x202320)
    static let olive = Color(hex: 0xB6BB98)

    static let ivoryNS = NSColor(red: 0xF4 / 255, green: 0xF3 / 255, blue: 0xEC / 255, alpha: 1)
    static let darkNS = NSColor(red: 0x16 / 255, green: 0x17 / 255, blue: 0x16 / 255, alpha: 1)

    static var appIcon: NSImage {
        NSImage(contentsOfFile: "tools/assets/icon-1024.png") ?? NSImage(contentsOfFile: "Resources/AppIcon.icns")!
    }

    /// The symbol from a real app icon (Notion's N, Slack's hash, Claude's spark…) as a white mask:
    /// the icon's background colour is sampled around its inner edge and everything that differs from
    /// it is the symbol. Tint it with `.foregroundStyle` via `Glyph`.
    static func glyph(_ app: String, size: Int = 256) -> NSImage {
        let key = "\(app)|\(size)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let source = NSWorkspace.shared.icon(forFile: "/Applications/\(app).app")
        guard let rep = Icons.bitmap(source, size: size), let data = rep.bitmapData else { return source }
        let w = rep.pixelsWide, h = rep.pixelsHigh
        func px(_ x: Int, _ y: Int) -> (Float, Float, Float, Float) {
            let p = data + (y * w + x) * 4, a = Float(p[3])
            guard a > 0 else { return (0, 0, 0, 0) }
            return (Float(p[0]) / a, Float(p[1]) / a, Float(p[2]) / a, a / 255)
        }
        // Bounding box of the opaque icon shape.
        var minX = w, minY = h, maxX = 0, maxY = 0
        for y in 0..<h { for x in 0..<w where px(x, y).3 > 0.9 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
        guard maxX > minX else { return source }
        // Background = median colour on a ring just inside the shape.
        let inset = Int(Double(maxX - minX) * 0.07)
        var rs: [Float] = [], gs: [Float] = [], bs: [Float] = []
        for t in stride(from: 0.2, through: 0.8, by: 0.02) {
            let xs = minX + inset + Int(Double(maxX - minX - 2 * inset) * t)
            let ys = minY + inset + Int(Double(maxY - minY - 2 * inset) * t)
            for (x, y) in [(xs, minY + inset), (xs, maxY - inset), (minX + inset, ys), (maxX - inset, ys)] {
                let c = px(x, y); if c.3 > 0.9 { rs.append(c.0); gs.append(c.1); bs.append(c.2) }
            }
        }
        func median(_ v: [Float]) -> Float { v.isEmpty ? 1 : v.sorted()[v.count / 2] }
        let bg = (median(rs), median(gs), median(bs))
        // Mask: distance from the background colour, inside the shape only.
        let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: w * 4, bitsPerPixel: 32)!
        let o = out.bitmapData!
        for y in 0..<h {
            for x in 0..<w {
                let c = px(x, y)
                let d = sqrt((c.0 - bg.0) * (c.0 - bg.0) + (c.1 - bg.1) * (c.1 - bg.1) + (c.2 - bg.2) * (c.2 - bg.2))
                // Ignore the icon's own rim: keep only pixels well inside its (rounded) shape.
                let edge = inset * 3 / 4
                let inside = x >= edge && y >= edge && x < w - edge && y < h - edge
                    && px(x - edge, y).3 > 0.9 && px(x + edge, y).3 > 0.9 && px(x, y - edge).3 > 0.9 && px(x, y + edge).3 > 0.9
                    && px(x - edge, y - edge).3 > 0.9 && px(x + edge, y + edge).3 > 0.9
                    && px(x - edge, y + edge).3 > 0.9 && px(x + edge, y - edge).3 > 0.9
                let a = inside ? min(1, max(0, (d - 0.12) / 0.18)) * c.3 : 0
                let q = o + (y * w + x) * 4
                let v = UInt8(a * 255)
                q[0] = v; q[1] = v; q[2] = v; q[3] = v  // premultiplied white
            }
        }
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(out)
        cache.setObject(image, forKey: key)
        return image
    }

    private static let cache = NSCache<NSString, NSImage>()
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Logo + wordmark.
struct CarbonBrand: View {
    var size: CGFloat = 44
    var body: some View {
        HStack(spacing: size * 0.32) {
            Image(nsImage: Carbon.appIcon).resizable().frame(width: size * 1.35, height: size * 1.35)
            Text("Multiverse").font(.system(size: size, weight: .medium)).tracking(-size * 0.03).foregroundStyle(Carbon.ivory)
        }
    }
}

/// An app as a Carbon tile: dark tile with an ivory symbol, or (for a copy) ivory tile with a dark symbol.
struct Tile: View {
    let app: String
    var ivory = false
    var size: CGFloat = 70
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(ivory ? Carbon.ivory : Carbon.tile)
            .overlay {
                Image(nsImage: Carbon.glyph(app)).resizable().renderingMode(.template)
                    .foregroundStyle(ivory ? Color(hex: 0x161716) : Carbon.ivory)
                    .frame(width: size * 1.12, height: size * 1.12)
            }
            .frame(width: size, height: size)
    }
}

/// One universe: a header with its dot and name, then its apps → its browser.
struct UniversePanel: View {
    let name: String
    let dot: Color
    let apps: [String]
    let ivory: Bool
    let browser: String
    let browserLabel: String
    var iconSize: CGFloat = 70
    var fontSize: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Circle().fill(dot).frame(width: fontSize * 0.62, height: fontSize * 0.62)
                Text(name).font(.system(size: fontSize, weight: .medium)).foregroundStyle(Carbon.ivory)
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
            Rectangle().fill(Carbon.border).frame(height: 1)
            HStack(spacing: 14) {
                ForEach(apps, id: \.self) { app in Tile(app: app, ivory: ivory, size: iconSize) }
                Rectangle().fill(Carbon.border).frame(width: 1.5, height: iconSize * 0.8).padding(.horizontal, 6)
                Image(systemName: "arrow.right").font(.system(size: fontSize * 0.9, weight: .light)).foregroundStyle(Carbon.muted)
                    .padding(.horizontal, 4)
                Tile(app: browser, ivory: ivory, size: iconSize)
                Text(browserLabel).font(.system(size: fontSize, weight: .regular)).foregroundStyle(Carbon.ivory)
                    .padding(.leading, 6)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22).padding(.vertical, 16)
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(Carbon.panel))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Carbon.border, lineWidth: 1))
    }
}

/// Big tight headline (SwiftUI ignores negative line spacing, so lines are stacked by hand).
struct Headline: View {
    let lines: [String]
    var size: CGFloat = 120
    var color = Carbon.ivory
    var body: some View {
        VStack(alignment: .leading, spacing: -size * 0.2) {
            ForEach(lines, id: \.self) { line in
                Text(line).font(.system(size: size, weight: .medium)).tracking(-size * 0.04).foregroundStyle(color).fixedSize()
            }
        }
    }
}

/// Renders a view to a PNG at 2x.
@MainActor func renderPNG<V: View>(_ view: V, to path: String, scale: CGFloat = 2) {
    let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
    renderer.scale = scale
    guard let cg = renderer.cgImage else { fatalError("render failed: \(path)") }
    try! NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(cg.width)x\(cg.height))")
}
