import SwiftUI

// Renders the launch image (docs/launch.png) from real app icons and Multiverse's own icon tinting.
// Build: swiftc -parse-as-library -D SNAPSHOT Sources/*.swift tools/LaunchImage.swift -o /tmp/launch && /tmp/launch docs
// then: sips -z 1350 2400 docs/launch.png (the 2x render is ~14 MB)

private let work = Color(red: 0.36, green: 0.55, blue: 0.94)
private let personal = Color(red: 0.19, green: 0.64, blue: 0.42)
private let workNS = NSColor(red: 0.36, green: 0.55, blue: 0.94, alpha: 1)
private let personalNS = NSColor(red: 0.19, green: 0.64, blue: 0.42, alpha: 1)

private func icon(_ app: String, tint: NSColor? = nil) -> NSImage {
    let url = URL(fileURLWithPath: "/Applications/\(app).app")
    return tint.map { Icons.make(for: url, style: .tint, tint: $0, size: 256) } ?? NSWorkspace.shared.icon(forFile: url.path)
}

struct LaunchImage: View {
    let appIcon: NSImage

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.035, blue: 0.05)
            // Two universes as two glows.
            RadialGradient(colors: [work.opacity(0.45), .clear], center: UnitPoint(x: 0.72, y: 0.18), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [personal.opacity(0.38), .clear], center: UnitPoint(x: 0.9, y: 0.95), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Color.white.opacity(0.06), .clear], center: UnitPoint(x: 0.18, y: 0.35), startRadius: 0, endRadius: 420)
            DotGrid().opacity(0.5)

            HStack(alignment: .center, spacing: 56) {
                // Left: brand
                VStack(alignment: .leading, spacing: 26) {
                    Image(nsImage: appIcon).resizable().frame(width: 132, height: 132)
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.white.opacity(0.12)))
                        .shadow(color: work.opacity(0.6), radius: 40)
                    Text("Multiverse")
                        .font(.system(size: 92, weight: .bold, design: .default))
                        .tracking(-2.5)
                        .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.72)], startPoint: .top, endPoint: .bottom))
                    Text("Keep work and personal apart on one Mac.\nSeparate copies of your apps, separate logins,\nand every link opens in the right browser.")
                        .font(.system(size: 27, weight: .regular))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineSpacing(6)
                    HStack(spacing: 10) {
                        Pill("Free & open source")
                        Pill("macOS 14+")
                        Pill("Set up by your agent")
                    }
                    .padding(.top, 6)
                }
                .frame(width: 720, alignment: .leading)

                // Right: the product
                VStack(alignment: .leading, spacing: 22) {
                    RoutingCard()
                    DockStrip()
                }
                .frame(width: 640)
            }
            .padding(.horizontal, 96)
        }
        .frame(width: 1600, height: 900)
        .environment(\.colorScheme, .dark)
    }
}

private struct Pill: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(.white.opacity(0.07)))
            .overlay(Capsule().stroke(.white.opacity(0.12)))
    }
}

/// Raycast-style panel: links coming in from apps and the universe each one opens in.
private struct RoutingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "link").foregroundStyle(.white.opacity(0.5))
                Text("Links you clicked").foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text("routed by Multiverse").foregroundStyle(.white.opacity(0.3))
            }
            .font(.system(size: 17, weight: .medium))
            .padding(.horizontal, 22).padding(.vertical, 16)
            Divider().overlay(.white.opacity(0.08))
            VStack(spacing: 4) {
                Route(from: icon("Slack", tint: workNS), app: "Work Slack", host: "linear.app/acme/issue/ENG-212",
                      to: "💼 Work", browser: icon("Google Chrome"), color: work, selected: true)
                Route(from: icon("Telegram"), app: "Telegram", host: "airbnb.com/rooms/48213",
                      to: "🏠 Personal", browser: icon("Dia", tint: personalNS), color: personal)
                Route(from: icon("Notion"), app: "Notion", host: "figma.com/design/q3-roadmap",
                      to: "💼 Work", browser: icon("Google Chrome"), color: work)
                Route(from: icon("Slack"), app: "Slack", host: "youtube.com/watch?v=dQw4",
                      to: "🏠 Personal", browser: icon("Dia", tint: personalNS), color: personal)
            }
            .padding(10)
        }
        .background(RoundedRectangle(cornerRadius: 22).fill(Color(white: 0.09).opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.6), radius: 50, y: 20)
    }
}

private struct Route: View {
    let from: NSImage, app: String, host: String, to: String, browser: NSImage, color: Color
    var selected = false

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: from).resizable().frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(host).font(.system(size: 18, weight: .medium)).foregroundStyle(.white.opacity(0.92)).lineLimit(1)
                Text("from \(app)").font(.system(size: 14)).foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 8)
            Image(systemName: "arrow.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.35))
            HStack(spacing: 8) {
                Image(nsImage: browser).resizable().frame(width: 26, height: 26)
                Text(to).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(color.opacity(0.22)))
            .overlay(Capsule().stroke(color.opacity(0.55)))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Color.white.opacity(0.07) : .clear))
    }
}

/// Originals next to their tinted copies, like they sit in the Dock.
private struct DockStrip: View {
    var body: some View {
        HStack(spacing: 18) {
            Pair(original: icon("Slack"), copy: icon("Slack", tint: workNS), label: "Slack", copyLabel: "Slack + Work Slack")
            Pair(original: icon("Dia"), copy: icon("Dia", tint: personalNS), label: "Dia", copyLabel: "Dia + Personal Dia")
            Pair(original: icon("Linear"), copy: icon("Linear", tint: workNS), label: "Linear", copyLabel: "Linear + Work Linear")
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 22).fill(.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.1)))
    }
}

private struct Pair: View {
    let original: NSImage, copy: NSImage, label: String, copyLabel: String
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(nsImage: original).resizable().frame(width: 64, height: 64)
                Image(nsImage: copy).resizable().frame(width: 64, height: 64)
            }
            Text(copyLabel).font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DotGrid: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 28
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.6, height: 1.6)), with: .color(.white.opacity(0.07)))
                    x += step
                }
                y += step
            }
        }
    }
}

@main
struct RenderLaunchImage {
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
            let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs"
            let appIcon = NSImage(contentsOfFile: "Resources/AppIcon.icns") ?? NSApp.applicationIconImage!
            let view = LaunchImage(appIcon: appIcon)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let cg = renderer.cgImage else { fatalError("render failed") }
            let rep = NSBitmapImageRep(cgImage: cg)
            try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/launch.png"))
            print("wrote \(out)/launch.png (\(cg.width)x\(cg.height))")
        }
    }
}
