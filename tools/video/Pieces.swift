import SwiftUI

// Reusable pieces of the launch film (time helpers, windows, menu, routes). See RULES.md.

let stage = CGSize(width: 1920, height: 1080)

// MARK: - Time helpers (pure)

/// Progress of `t` between `a` and `b`, clamped to 0…1.
func prog(_ t: Double, _ a: Double, _ b: Double) -> Double { min(1, max(0, (t - a) / (b - a))) }
func ease(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
/// Snappy entrance: fast start, long soft landing.
func snap(_ x: Double) -> Double { x >= 1 ? 1 : 1 - pow(2, -10 * x) }
/// Lands with a small overshoot.
func pop(_ x: Double) -> Double { let c = 1.9; return 1 + (c + 1) * pow(x - 1, 3) + c * pow(x - 1, 2) }
func mix(_ a: CGFloat, _ b: CGFloat, _ x: Double) -> CGFloat { a + (b - a) * CGFloat(x) }
func mix(_ a: CGPoint, _ b: CGPoint, _ x: Double) -> CGPoint { CGPoint(x: mix(a.x, b.x, x), y: mix(a.y, b.y, x)) }
func mix(_ a: CGRect, _ b: CGRect, _ x: Double) -> CGRect {
    CGRect(x: mix(a.minX, b.minX, x), y: mix(a.minY, b.minY, x), width: mix(a.width, b.width, x), height: mix(a.height, b.height, x))
}

let ink = Color(hex: 0x161716)

// MARK: - Pieces

struct Caption: View {
    let text: String
    let opacity: Double
    var body: some View {
        Text(text).font(.system(size: 64, weight: .medium)).tracking(-2).foregroundStyle(Carbon.ivory)
            .opacity(opacity).offset(y: CGFloat(1 - opacity) * 16)
    }
}

/// A Carbon window: title bar with dots and title, then content.
struct Window<Content: View>: View {
    let title: String
    var ivory = false
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(ivory ? Color(hex: 0xC9C7BD) : Color(hex: 0x3A3C38)).frame(width: 12, height: 12) }
                Spacer()
                Text(title).font(.system(size: 20, weight: .medium)).foregroundStyle(ivory ? ink.opacity(0.7) : Carbon.muted)
                Spacer()
                Color.clear.frame(width: 52, height: 1)
            }
            .padding(.horizontal, 18).frame(height: 50)
            Rectangle().fill(ivory ? Color(hex: 0xDDDBD1) : Carbon.border).frame(height: 1)
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(ivory ? Carbon.ivory : Carbon.panel))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(ivory ? Color(hex: 0xDDDBD1) : Carbon.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// A chat app: workspace sidebar with the signed-in account, a channel, messages.
struct ChatApp: View {
    let workspace: String
    let account: String
    let channel: String
    /// (author, text, link)
    let messages: [(String, String, String?)]
    var ivory = false
    var linkHighlight: Double = 0
    var body: some View {
        let fg = ivory ? ink : Carbon.ivory
        let dim = ivory ? ink.opacity(0.5) : Carbon.muted
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text(workspace).font(.system(size: 28, weight: .semibold)).foregroundStyle(fg)
                ForEach(["# general", "# \(channel)", "# random"], id: \.self) { c in
                    Text(c).font(.system(size: 22, weight: c.contains(channel) ? .semibold : .regular))
                        .foregroundStyle(c.contains(channel) ? fg : dim)
                }
                Spacer()
                HStack(spacing: 8) {
                    Circle().fill(ivory ? Carbon.olive : Carbon.gray).frame(width: 34, height: 34)
                        .overlay(Text(String(account.prefix(1)).uppercased()).font(.system(size: 17, weight: .bold)).foregroundStyle(ink))
                    Text(account).font(.system(size: 19)).foregroundStyle(dim).lineLimit(1).fixedSize()
                }
            }
            .padding(24).frame(width: 250).frame(maxHeight: .infinity, alignment: .topLeading)
            .background(ivory ? Color(hex: 0xEAE8DF) : Color(hex: 0x161715))
            VStack(alignment: .leading, spacing: 22) {
                Text("# \(channel)").font(.system(size: 24, weight: .semibold)).foregroundStyle(fg)
                ForEach(Array(messages.enumerated()), id: \.offset) { _, m in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(m.0).font(.system(size: 20, weight: .semibold)).foregroundStyle(fg)
                        Text(m.1).font(.system(size: 23)).foregroundStyle(fg.opacity(0.85)).fixedSize()
                        if let link = m.2 {
                            Text(link).font(.system(size: 23, weight: .medium)).underline().foregroundStyle(fg).fixedSize()
                        }
                    }
                }
                Spacer()
            }
            .padding(24)
        }
    }
}

/// A browser window opened on a URL.
struct BrowserPage: View {
    let url: String
    var ivory = false
    var body: some View {
        let fg = ivory ? ink : Carbon.ivory
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "lock.fill").font(.system(size: 18))
                Text(url).font(.system(size: 22, design: .monospaced)).fixedSize()
            }
            .foregroundStyle(fg.opacity(0.8))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9).fill(ivory ? Color(hex: 0xE6E4DA) : Color(hex: 0x252723)))
            RoundedRectangle(cornerRadius: 6).fill(fg.opacity(0.85)).frame(width: 300, height: 30)
            ForEach([440, 380, 470, 260], id: \.self) { w in
                RoundedRectangle(cornerRadius: 5).fill(fg.opacity(0.18)).frame(width: CGFloat(w), height: 18)
            }
        }
        .padding(24)
    }
}

/// The Multiverse menu, with the app's real items.
struct MenuMock: View {
    var highlight: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            section("💼 Work")
            item("Slack", app: "Slack")
            item("Notion", app: "Notion")
            section("🏠 Personal")
            item("Personal Slack", app: "Slack", ivory: true)
            item("Personal Notion", app: "Notion", ivory: true)
            item("Personal Dia", app: "Dia", ivory: true)
            divider()
            item("Recent links", trailing: "›")
            item("Settings…", trailing: "⌘,")
            item("Setup & permissions…")
            divider()
            item("Quit Multiverse", trailing: "⌘Q")
        }
        .padding(8)
        .frame(width: 330)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x1E201D)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Carbon.border))
    }
    private func section(_ title: String) -> some View {
        Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Carbon.muted).padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 2)
    }
    private func divider() -> some View { Rectangle().fill(Carbon.border).frame(height: 1).padding(.vertical, 5) }
    private func item(_ title: String, app: String? = nil, ivory: Bool = false, trailing: String? = nil) -> some View {
        let on = highlight == title
        return HStack(spacing: 10) {
            if let app { Tile(app: app, ivory: ivory, size: 24) }
            Text(title).font(.system(size: 16)).foregroundStyle(on ? ink : Carbon.ivory)
            Spacer()
            if let trailing { Text(trailing).font(.system(size: 14)).foregroundStyle(on ? ink.opacity(0.6) : Carbon.muted) }
        }
        .padding(.horizontal, 10).frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 7).fill(on ? Carbon.ivory : .clear))
    }
}

struct Cursor: View {
    var body: some View {
        Image(systemName: "cursorarrow").font(.system(size: 40, weight: .regular))
            .foregroundStyle(Carbon.ivory)
            .shadow(color: .black.opacity(0.8), radius: 2)
    }
}

/// The front (ivory) and back (gray) panes of the Multiverse icon, in the icon's own 21×23 units.
enum Panes {
    static func corners(front: Bool) -> [CGPoint] {
        let d: CGFloat = front ? 0 : 3
        return [CGPoint(x: 2 + d, y: 16 + d), CGPoint(x: 8.5 + d, y: 4 + d), CGPoint(x: 16 + d, y: 4 + d), CGPoint(x: 9.5 + d, y: 16 + d)]
    }
}

/// A quad between any four corners, so a rectangle can morph into a pane.
struct Quad: Shape {
    var points: [CGPoint]
    func path(in _: CGRect) -> Path {
        var p = Path()
        p.move(to: points[0]); points.dropFirst().forEach { p.addLine(to: $0) }; p.closeSubpath()
        return p
    }
}

/// Cubic curve point.
func bezier(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: Double) -> CGPoint {
    let u = 1 - t
    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
    return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x, y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
}

/// A horizontal S-curve from a to b, drawn up to `progress`, with a pulse at its head.
struct Route: View {
    let from: CGPoint, to: CGPoint
    let progress: Double
    var pulse = true
    var body: some View {
        let mid = (from.x + to.x) / 2
        let c1 = CGPoint(x: mid, y: from.y), c2 = CGPoint(x: mid, y: to.y)
        ZStack {
            Path { p in p.move(to: from); p.addCurve(to: to, control1: c1, control2: c2) }
                .stroke(Carbon.border, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            Path { p in p.move(to: from); p.addCurve(to: to, control1: c1, control2: c2) }
                .trim(from: 0, to: progress)
                .stroke(Carbon.ivory, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            if pulse && progress > 0 && progress < 1 {
                let head = bezier(from, c1, c2, to, progress)
                Circle().fill(Carbon.ivory).frame(width: 18, height: 18).position(head)
                Circle().stroke(Carbon.ivory.opacity(0.35), lineWidth: 2).frame(width: 40, height: 40).position(head)
            }
        }
    }
}

/// A universe node in a route: dot + name pill.
struct Node: View {
    let name: String
    let dot: Color
    var lit = true
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: Carbon.appIcon).resizable().frame(width: 40, height: 40)
            Circle().fill(dot).frame(width: 14, height: 14)
            Text(name).font(.system(size: 26, weight: .medium)).foregroundStyle(Carbon.ivory)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Capsule().fill(Carbon.panel))
        .overlay(Capsule().stroke(lit ? Carbon.ivory.opacity(0.6) : Carbon.border, lineWidth: 1.5))
    }
}

