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
// Lasseter's principles, as helpers (see RULES.md).

/// Anticipation: winds back a little before going 0→1 (ease-in-out-back).
func anticipate(_ x: Double, back: Double = 1.4) -> Double {
    let c = back * 1.525
    return x < 0.5 ? (pow(2 * x, 2) * ((c + 1) * 2 * x - c)) / 2
                   : (pow(2 * x - 2, 2) * ((c + 1) * (x * 2 - 2) + c) + 2) / 2
}

/// Squash & stretch after an impact `since` seconds ago: flattens, springs back, settles. Keeps volume.
func squash(_ since: Double, amount: Double = 0.12) -> CGSize {
    guard since >= 0 else { return CGSize(width: 1, height: 1) }
    let a = amount * exp(-since / 0.11) * cos(since * 2 * .pi * 3.5)
    return CGSize(width: 1 + a, height: 1 / (1 + a))
}

/// Arcs: a point between a and b that bulges sideways (perpendicular), most at the middle.
func arc(_ a: CGPoint, _ b: CGPoint, _ x: Double, bulge: CGFloat) -> CGPoint {
    let p = mix(a, b, x)
    let dx = b.x - a.x, dy = b.y - a.y, len = max(1, sqrt(dx * dx + dy * dy))
    let k = bulge * CGFloat(sin(.pi * min(1, max(0, x))))
    return CGPoint(x: p.x - dy / len * k, y: p.y + dx / len * k)
}

/// Long moves: a gentler overshoot, so far-travelling things don't fly past the frame.
func popSoft(_ x: Double) -> Double { let c = 0.7; return 1 + (c + 1) * pow(x - 1, 3) + c * pow(x - 1, 2) }

/// Staging: darken a whole window evenly (a dark layer over its shape), instead of fading its parts.
extension View {
    func dimmed(_ amount: Double, cornerRadius: CGFloat = 16) -> some View {
        overlay(RoundedRectangle(cornerRadius: cornerRadius).fill(Carbon.bg.opacity(amount)))
    }
}

/// Lands with a small overshoot.
func pop(_ x: Double) -> Double { let c = 1.9; return 1 + (c + 1) * pow(x - 1, 3) + c * pow(x - 1, 2) }
func mix(_ a: CGFloat, _ b: CGFloat, _ x: Double) -> CGFloat { a + (b - a) * CGFloat(x) }
func mix(_ a: CGPoint, _ b: CGPoint, _ x: Double) -> CGPoint { CGPoint(x: mix(a.x, b.x, x), y: mix(a.y, b.y, x)) }
func mix(_ a: CGRect, _ b: CGRect, _ x: Double) -> CGRect {
    CGRect(x: mix(a.minX, b.minX, x), y: mix(a.minY, b.minY, x), width: mix(a.width, b.width, x), height: mix(a.height, b.height, x))
}

let ink = Color(hex: 0x161716)

// MARK: - Pieces

/// A caption whose words arrive one after another (overlapping action), each rising into place.
struct Caption: View {
    let text: String
    /// 0…1 progress of the whole caption.
    let opacity: Double
    var body: some View {
        let words = text.split(separator: " ").map(String.init)
        let lag = 0.18
        HStack(spacing: 16) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, word in
                let p = min(1, max(0, opacity * (1 + lag * Double(words.count - 1)) - lag * Double(i)))
                Text(word).font(.system(size: 64, weight: .medium)).tracking(-2).foregroundStyle(Carbon.ivory)
                    .opacity(p).offset(y: CGFloat(1 - snap(p)) * 22)
            }
        }
        .fixedSize()
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

/// An AI chat app: history sidebar with the signed-in account, then a prompt and an answer with a link.
struct AIChat: View {
    let app: String
    let account: String
    let plan: String
    let history: [String]
    let prompt: String
    let answer: String
    let link: String
    var ivory = false
    var body: some View {
        let fg = ivory ? ink : Carbon.ivory
        let dim = ivory ? ink.opacity(0.5) : Carbon.muted
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Tile(app: app, ivory: !ivory, size: 34)
                    Text(app).font(.system(size: 26, weight: .semibold)).foregroundStyle(fg)
                }
                Text("Recents").font(.system(size: 16, weight: .semibold)).foregroundStyle(dim).padding(.top, 6)
                ForEach(Array(history.enumerated()), id: \.offset) { i, h in
                    Text(h).font(.system(size: 20, weight: i == 0 ? .semibold : .regular)).foregroundStyle(i == 0 ? fg : dim)
                        .lineLimit(1)
                }
                Spacer()
                HStack(spacing: 8) {
                    Circle().fill(ivory ? Carbon.olive : Carbon.gray).frame(width: 34, height: 34)
                        .overlay(Text(String(account.prefix(1)).uppercased()).font(.system(size: 17, weight: .bold)).foregroundStyle(ink))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account).font(.system(size: 17)).foregroundStyle(fg.opacity(0.8)).lineLimit(1).fixedSize()
                        Text(plan).font(.system(size: 14)).foregroundStyle(dim)
                    }
                }
            }
            .padding(24).frame(width: 270).frame(maxHeight: .infinity, alignment: .topLeading)
            .background(ivory ? Color(hex: 0xEAE8DF) : Color(hex: 0x161715))
            VStack(alignment: .trailing, spacing: 22) {
                Text(prompt).font(.system(size: 22)).foregroundStyle(fg)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 16).fill(ivory ? Color(hex: 0xE2E0D6) : Color(hex: 0x262825)))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 10) {
                    Text(answer).font(.system(size: 22)).foregroundStyle(fg.opacity(0.88)).fixedSize(horizontal: false, vertical: true)
                    Text(link).font(.system(size: 22, weight: .medium)).underline().foregroundStyle(fg).fixedSize()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            }
            .padding(26)
        }
    }
}

/// A browser window opened on a URL.
struct BrowserPage: View {
    let url: String
    var ivory = false
    /// 0…1: the page's lines draw in one after another after it opens (secondary action).
    var load: Double = 1
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
            ForEach(Array([300, 440, 380, 470, 260].enumerated()), id: \.offset) { i, w in
                let p = snap(min(1, max(0, load * 2.2 - Double(i) * 0.25)))
                RoundedRectangle(cornerRadius: 5).fill(fg.opacity(i == 0 ? 0.85 : 0.18))
                    .frame(width: CGFloat(w) * CGFloat(p), height: i == 0 ? 30 : 18)
                    .frame(width: CGFloat(w), alignment: .leading)
            }
        }
        .padding(24)
    }
}

/// The Multiverse menu, with the app's real items.
struct MenuMock: View {
    var highlight: String?
    /// 0…1: rows cascade in one after another (follow-through).
    var reveal: Double = 1
    var body: some View {
        let rows: [AnyView] = [
            AnyView(section("💼 Work")), AnyView(item("Claude", app: "Claude")), AnyView(item("ChatGPT", app: "ChatGPT")),
            AnyView(section("🏠 Personal")), AnyView(item("Personal Claude", app: "Claude", ivory: true)),
            AnyView(item("Personal ChatGPT", app: "ChatGPT", ivory: true)), AnyView(item("Dia", app: "Dia", ivory: true)),
            AnyView(section("🚀 Side project")), AnyView(item("Side project Cursor", app: "Cursor")),
            AnyView(item("Side project Dia", app: "Dia")), AnyView(divider()),
            AnyView(item("Recent links", trailing: "›")), AnyView(item("Settings…", trailing: "⌘,")),
            AnyView(item("Setup & permissions…")), AnyView(divider()), AnyView(item("Quit Multiverse", trailing: "⌘Q")),
        ]
        let lag = 0.05
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                let p = min(1, max(0, reveal * (1 + lag * Double(rows.count)) - lag * Double(i)))
                row.opacity(p).offset(y: CGFloat(1 - snap(p)) * -8)
            }
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
            // Dark outline under the ivory line keeps it visible where it crosses an ivory window.
            Path { p in p.move(to: from); p.addCurve(to: to, control1: c1, control2: c2) }
                .trim(from: 0, to: progress)
                .stroke(ink, style: StrokeStyle(lineWidth: 6, lineCap: .round))
            Path { p in p.move(to: from); p.addCurve(to: to, control1: c1, control2: c2) }
                .trim(from: 0, to: progress)
                .stroke(Carbon.ivory, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            if pulse && progress > 0 && progress < 1 {
                let head = bezier(from, c1, c2, to, progress)
                // Stretch along the direction of travel, most at full speed (middle of the leg).
                let ahead = bezier(from, c1, c2, to, min(1, progress + 0.01))
                let angle = atan2(ahead.y - head.y, ahead.x - head.x)
                let stretch = 1 + 0.9 * sin(.pi * progress)
                Capsule().fill(Carbon.ivory).overlay(Capsule().stroke(ink, lineWidth: 2))
                    .frame(width: 18 * stretch, height: 18 / sqrt(stretch))
                    .rotationEffect(.radians(Double(angle))).position(head)
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
    /// A fixed width keeps nodes (and the lines meeting them) aligned whatever the name's length.
    var width: CGFloat? = nil
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: Carbon.appIcon).resizable().frame(width: 40, height: 40)
            Circle().fill(dot).frame(width: 14, height: 14)
            Text(name).font(.system(size: 26, weight: .medium)).foregroundStyle(Carbon.ivory).fixedSize()
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .frame(width: width)
        .background(Capsule().fill(Carbon.panel))
        .overlay(Capsule().stroke(lit ? Carbon.ivory.opacity(0.6) : Carbon.border, lineWidth: 1.5))
    }
}

