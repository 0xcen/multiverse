import SwiftUI

// The launch film. Read RULES.md first.
// Build from the repo root:
//   swiftc -O -parse-as-library -D SNAPSHOT Sources/*.swift tools/Carbon.swift tools/video/LaunchVideo.swift -o /tmp/launch-video
//   /tmp/launch-video frames <dir>        render all frames as PNGs
//   /tmp/launch-video still <n> <file>    render one frame
// Then tools/video/render.sh encodes and checks.

let fps = 30.0
let duration = 32.0
let frameCount = Int(fps * duration)
let stage = CGSize(width: 1920, height: 1080)

// MARK: - Time helpers (pure)

/// Progress of `t` between `a` and `b`, clamped to 0…1.
func prog(_ t: Double, _ a: Double, _ b: Double) -> Double { min(1, max(0, (t - a) / (b - a))) }
func ease(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
func mix(_ a: CGFloat, _ b: CGFloat, _ x: Double) -> CGFloat { a + (b - a) * CGFloat(x) }
func mix(_ a: CGPoint, _ b: CGPoint, _ x: Double) -> CGPoint { CGPoint(x: mix(a.x, b.x, x), y: mix(a.y, b.y, x)) }
func mix(_ a: CGRect, _ b: CGRect, _ x: Double) -> CGRect {
    CGRect(x: mix(a.minX, b.minX, x), y: mix(a.minY, b.minY, x), width: mix(a.width, b.width, x), height: mix(a.height, b.height, x))
}

private let ink = Color(hex: 0x161716)

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

// MARK: - The film

struct Frame: View {
    let n: Int
    var t: Double { Double(n) / fps }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Carbon.bg
            scene
        }
        .frame(width: stage.width, height: stage.height)
        .clipped()
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var scene: some View {
        switch t {
        case ..<3: oneBecomesTwo
        case ..<6: differentLives
        case ..<10: meetMultiverse
        case ..<14: copiesCuts
        case ..<19: route(personal: false, start: 14)
        case ..<22.4: route(personal: true, start: 19)
        case ..<24: bothRoutes
        case ..<28: gatherIntoIcon
        default: endCard
        }
    }

    // 0–3 s
    private var oneBecomesTwo: some View {
        let split = ease(prog(t, 0.7, 1.6)), invert = ease(prog(t, 1.4, 2.1)), appear = easeOut(prog(t, 0, 0.5))
        return ZStack {
            ZStack {
                Tile(app: "Slack", size: 220)
                Tile(app: "Slack", ivory: true, size: 220).opacity(invert)
            }
            .position(x: 960 + 200 * split, y: 470)
            Tile(app: "Slack", size: 220).position(x: 960 - 200 * split, y: 470)
            Caption(text: "Same app.", opacity: prog(t, 1.3, 1.8)).position(x: 960, y: 800)
        }
        .opacity(appear)
        .scaleEffect(mix(0.92, 1, appear))
    }

    // 3–6 s
    private var differentLives: some View {
        let g = ease(prog(t, 3, 3.9)), content = prog(t, 3.6, 4.2)
        let left = mix(CGRect(x: 650, y: 360, width: 220, height: 220), CGRect(x: 120, y: 190, width: 820, height: 560), g)
        let right = mix(CGRect(x: 1050, y: 360, width: 220, height: 220), CGRect(x: 980, y: 190, width: 820, height: 560), g)
        return ZStack(alignment: .topLeading) {
            workChat.opacity(content).overlay(Tile(app: "Slack", size: 220).opacity(1 - content).scaleEffect(1 - g * 0.3))
                .frame(width: left.width, height: left.height).position(x: left.midX, y: left.midY)
            personalChat.opacity(content).overlay(Tile(app: "Slack", ivory: true, size: 220).opacity(1 - content).scaleEffect(1 - g * 0.3))
                .frame(width: right.width, height: right.height).position(x: right.midX, y: right.midY)
            Caption(text: "Different lives.", opacity: prog(t, 4.3, 4.8)).position(x: 960, y: 900)
        }
    }

    private var workChat: some View {
        Window(title: "Slack — Acme") {
            ChatApp(workspace: "Acme", account: "sam@acme.com", channel: "launch",
                    messages: [("Priya", "Launch review moved to 3pm", nil), ("Leo", "Spec is here:", "linear.app/acme/ENG-212")])
        }
    }

    private var personalChat: some View {
        Window(title: "Personal Slack — Family", ivory: true) {
            ChatApp(workspace: "Family", account: "sam@gmail.com", channel: "weekend",
                    messages: [("Mum", "Dinner on Sunday?", nil), ("Alex", "This for Saturday?", "airbnb.com/rooms/48213")], ivory: true)
        }
    }

    // 6–10 s
    private var meetMultiverse: some View {
        let z = ease(prog(t, 6, 7.1)), menu = easeOut(prog(t, 7.0, 7.5))
        let highlight: String? = t > 8.6 ? "Personal Slack" : (t > 8.1 ? "Slack" : nil)
        return ZStack(alignment: .topLeading) {
            // The two windows sink back.
            ZStack(alignment: .topLeading) {
                workChat.frame(width: 820, height: 560).position(x: 530, y: 470)
                personalChat.frame(width: 820, height: 560).position(x: 1390, y: 470)
            }
            .scaleEffect(mix(1, 0.62, z), anchor: .bottom)
            .opacity(mix(1, 0.55, z))
            // Menu bar
            HStack(spacing: 22) {
                Spacer()
                Image(nsImage: menuBarIcon).renderingMode(.template).resizable().frame(width: 22, height: 22)
                    .foregroundStyle(Carbon.ivory)
                    .padding(6).background(RoundedRectangle(cornerRadius: 6).fill(Carbon.ivory.opacity(menu > 0 ? 0.15 : 0)))
                Image(systemName: "wifi").foregroundStyle(Carbon.muted)
                Text("Fri 9:41").font(.system(size: 16)).foregroundStyle(Carbon.muted)
            }
            .padding(.horizontal, 30).frame(width: stage.width, height: 44)
            .background(Color(hex: 0x141513))
            .opacity(z)
            MenuMock(highlight: highlight)
                .scaleEffect(1.5, anchor: .top)
                .opacity(menu).offset(y: CGFloat(1 - menu) * -10)
                .position(x: 1560, y: 330)
            Caption(text: "Meet Multiverse.", opacity: prog(t, 8.0, 8.5)).position(x: 560, y: 260)
        }
    }

    // 10–14 s
    @ViewBuilder private var copiesCuts: some View {
        if t < 11 { copyCard(app: "Slack", name: "Personal Slack") }
        else if t < 12 { copyCard(app: "Notion", name: "Personal Notion") }
        else { dock }
    }

    private func copyCard(app: String, name: String) -> some View {
        let local = t < 11 ? t - 10 : t - 11
        let pop = easeOut(prog(local, 0, 0.35))
        return HStack(spacing: 56) {
            HStack(spacing: 24) {
                Tile(app: app, size: 200)
                Image(systemName: "arrow.right").font(.system(size: 44, weight: .light)).foregroundStyle(Carbon.muted)
                Tile(app: app, ivory: true, size: 200).scaleEffect(mix(0.85, 1, pop))
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(name).font(.system(size: 84, weight: .medium)).tracking(-3).foregroundStyle(Carbon.ivory)
                Text("Copy of \(app) · own logins").font(.system(size: 34)).foregroundStyle(Carbon.muted)
            }
            .opacity(prog(local, 0.15, 0.4))
        }
        .frame(width: stage.width, height: stage.height)
    }

    private var dock: some View {
        let items: [(String, Bool, String)] = [("Slack", false, "Slack"), ("Slack", true, "Personal Slack"),
                                               ("Notion", false, "Notion"), ("Notion", true, "Personal Notion"),
                                               ("Google Chrome", false, "Chrome"), ("Dia", true, "Personal Dia")]
        return VStack(spacing: 46) {
            Caption(text: "Both, side by side.", opacity: prog(t, 12.6, 13.0))
            HStack(spacing: 22) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    let pop = easeOut(prog(t, 12.0 + Double(i) * 0.08, 12.35 + Double(i) * 0.08))
                    VStack(spacing: 10) {
                        Tile(app: item.0, ivory: item.1, size: 130)
                        Circle().fill(Carbon.muted).frame(width: 7, height: 7)
                    }
                    .scaleEffect(mix(0.6, 1, pop)).opacity(pop)
                }
            }
            .padding(.horizontal, 30).padding(.vertical, 22)
            .background(RoundedRectangle(cornerRadius: 34).fill(Carbon.panel))
            .overlay(RoundedRectangle(cornerRadius: 34).stroke(Carbon.border))
        }
        .frame(width: stage.width, height: stage.height)
    }

    // 14–19 s (Work), 19–22.4 s (Personal)
    private func route(personal: Bool, start s: Double) -> some View {
        // The second time round the viewer knows the beat, so it plays faster (fits 19–22.4 s).
        let k = personal ? 0.72 : 1.0
        func at(_ x: Double) -> Double { s + x * k }
        let appear = easeOut(prog(t, s, at(0.4)))
        let cursorIn = ease(prog(t, at(0.2), at(1.1)))
        let click = prog(t, at(1.2), at(1.6))
        let leg1 = ease(prog(t, at(1.4), at(2.3))), leg2 = ease(prog(t, at(2.3), at(3.2)))
        let open = easeOut(prog(t, at(3.0), at(3.5)))
        let appRect = CGRect(x: 70, y: 260, width: 640, height: 470)
        let linkPoint = CGPoint(x: 470, y: 541)            // where the link is clicked
        let lineStart = CGPoint(x: personal ? 640 : 620, y: 541)  // just after the link text
        let nodePoint = CGPoint(x: 960, y: 495)
        let browserRect = CGRect(x: 1210, y: 260, width: 640, height: 470)
        return ZStack(alignment: .topLeading) {
            Group {
                if personal { personalChatSmall } else { workChatSmall }
            }
            .frame(width: appRect.width, height: appRect.height).position(x: appRect.midX, y: appRect.midY)
            Route(from: lineStart, to: CGPoint(x: nodePoint.x - 150, y: nodePoint.y), progress: leg1)
            Route(from: CGPoint(x: nodePoint.x + 150, y: nodePoint.y), to: CGPoint(x: browserRect.minX, y: browserRect.midY), progress: leg2)
            Node(name: personal ? "Personal" : "Work", dot: personal ? Carbon.olive : Carbon.ivory, lit: leg1 >= 1)
                .position(nodePoint)
            Window(title: personal ? "Personal Dia" : "Chrome", ivory: personal) {
                BrowserPage(url: personal ? "airbnb.com/rooms/48213" : "linear.app/acme/ENG-212", ivory: personal)
            }
            .frame(width: browserRect.width, height: browserRect.height)
            .position(x: browserRect.midX, y: browserRect.midY)
            .opacity(open).scaleEffect(mix(0.94, 1, open))
            // Ghost of where it will open, before it does.
            RoundedRectangle(cornerRadius: 16).stroke(Carbon.border, style: StrokeStyle(lineWidth: 1.5, dash: [8, 8]))
                .frame(width: browserRect.width, height: browserRect.height)
                .position(x: browserRect.midX, y: browserRect.midY).opacity(1 - open)
            // Cursor and click
            Cursor().position(mix(CGPoint(x: linkPoint.x + 260, y: 980), CGPoint(x: linkPoint.x + 14, y: linkPoint.y + 18), cursorIn))
                .opacity(1 - prog(t, at(2.0), at(2.4)))
            Circle().stroke(Carbon.ivory.opacity(1 - click), lineWidth: 2)
                .frame(width: 12 + 60 * click, height: 12 + 60 * click).position(linkPoint).opacity(click > 0 ? 1 : 0)
            Caption(text: personal ? "Personal → Personal Dia." : "Work → Chrome.", opacity: prog(t, at(3.4), at(3.8)))
                .position(x: 960, y: 900)
        }
        .opacity(appear)
    }

    private var workChatSmall: some View {
        Window(title: "Slack — Acme") {
            ChatApp(workspace: "Acme", account: "sam@acme.com", channel: "launch",
                    messages: [("Priya", "Review moved to 3pm", nil), ("Leo", "Spec is here:", "linear.app/acme/ENG-212")])
        }
    }

    private var personalChatSmall: some View {
        Window(title: "Personal Slack — Family", ivory: true) {
            ChatApp(workspace: "Family", account: "sam@gmail.com", channel: "weekend",
                    messages: [("Mum", "Dinner on Sunday?", nil), ("Alex", "This for Saturday?", "airbnb.com/rooms/48213")], ivory: true)
        }
    }

    // 22.4–24 s
    private var bothRoutes: some View {
        let appear = easeOut(prog(t, 22.4, 22.9))
        return ZStack(alignment: .topLeading) {
            routeRow(y: 380, app: "Slack", ivory: false, node: "Work", dot: Carbon.ivory, browser: "Google Chrome", label: "Chrome")
            routeRow(y: 640, app: "Slack", ivory: true, node: "Personal", dot: Carbon.olive, browser: "Dia", label: "Personal Dia")
            Caption(text: "Personal stays personal.", opacity: prog(t, 22.9, 23.3)).position(x: 960, y: 170)
        }
        .opacity(appear)
    }

    private func routeRow(y: CGFloat, app: String, ivory: Bool, node: String, dot: Color, browser: String, label: String) -> some View {
        ZStack(alignment: .topLeading) {
            Route(from: CGPoint(x: 470, y: y), to: CGPoint(x: 800, y: y), progress: 1, pulse: false)
            Route(from: CGPoint(x: 1120, y: y), to: CGPoint(x: 1400, y: y), progress: 1, pulse: false)
            Tile(app: app, ivory: ivory, size: 120).position(x: 400, y: y)
            Node(name: node, dot: dot).position(x: 960, y: y)
            HStack(spacing: 16) {
                Tile(app: browser, ivory: ivory, size: 120)
                Text(label).font(.system(size: 30)).foregroundStyle(Carbon.ivory).fixedSize()
            }
            .position(x: 1560, y: y)
        }
    }

    // 24–28 s
    private var gatherIntoIcon: some View {
        let fadeRows = prog(t, 24.0, 24.8)
        let morph = ease(prog(t, 24.3, 26.0))
        let plate = ease(prog(t, 26.2, 27.2))
        let iconSize: CGFloat = 300
        let center = CGPoint(x: 960, y: 500)
        // The icon's 21×23 unit space, centred and scaled like the SVG (scale 36 of 1024).
        let unit = iconSize * 36 / 1024
        func iconPoint(_ p: CGPoint) -> CGPoint { CGPoint(x: center.x + (p.x - 10.5) * unit, y: center.y + (p.y - 11.5) * unit) }
        func rectCorners(_ r: CGRect) -> [CGPoint] {
            [CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY)]
        }
        let workRow = CGRect(x: 320, y: 300, width: 1300, height: 160), personalRow = CGRect(x: 320, y: 560, width: 1300, height: 160)
        let back = zip(rectCorners(workRow), Panes.corners(front: false).map(iconPoint)).map { mix($0, $1, morph) }
        let front = zip(rectCorners(personalRow), Panes.corners(front: true).map(iconPoint)).map { mix($0, $1, morph) }
        return ZStack(alignment: .topLeading) {
            bothRoutes.opacity(1 - fadeRows)
            RoundedRectangle(cornerRadius: iconSize * 210 / 1024, style: .continuous)
                .fill(Carbon.graphite)
                .frame(width: iconSize * 928 / 1024, height: iconSize * 928 / 1024)
                .position(center).opacity(plate).scaleEffect(mix(1.25, 1, plate))
            Quad(points: front).fill(Carbon.ivory.opacity(mix(0.08, 1, morph)))
            Quad(points: back).fill(Carbon.gray.opacity(mix(0.08, 1, morph)))
        }
    }

    // 28–32 s
    private var endCard: some View {
        let lift = ease(prog(t, 28.0, 28.8)), words = prog(t, 28.5, 29.2), line = prog(t, 29.1, 29.8)
        return VStack(spacing: 30) {
            Image(nsImage: Carbon.appIcon).resizable().frame(width: 300, height: 300)
                .scaleEffect(mix(1, 0.75, lift))
            Text("Multiverse").font(.system(size: 110, weight: .medium)).tracking(-4).foregroundStyle(Carbon.ivory).opacity(words)
            Text("One Mac. Different universes.").font(.system(size: 46)).tracking(-1).foregroundStyle(Carbon.muted).opacity(line)
        }
        .offset(y: mix(-40, -60, lift) + 40)
        .frame(width: stage.width, height: stage.height)
    }
}

// MARK: - Render

@MainActor func renderFrame(_ n: Int) -> CGImage {
    let renderer = ImageRenderer(content: Frame(n: n))
    renderer.scale = 1
    return renderer.cgImage!
}

@MainActor func writePNG(_ image: CGImage, _ path: String) {
    try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

@main
struct LaunchVideo {
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let args = CommandLine.arguments
        MainActor.assumeIsolated {
            switch args.dropFirst().first {
            case "frames":
                let dir = args[2]
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                for n in 0..<frameCount {
                    autoreleasepool { writePNG(renderFrame(n), String(format: "%@/%04d.png", dir, n)) }
                    if n % 120 == 0 { print("frame \(n)/\(frameCount)") }
                }
                print("frames \(frameCount)")
            case "still":
                writePNG(renderFrame(Int(args[2])!), args[3])
            case "same":
                // Determinism: the same frame rendered twice must be byte-identical.
                let n = Int(args[2])!
                let a = NSBitmapImageRep(cgImage: renderFrame(n)).representation(using: .png, properties: [:])!
                let b = NSBitmapImageRep(cgImage: renderFrame(n)).representation(using: .png, properties: [:])!
                print(a == b ? "same \(n)" : "DIFFERENT \(n)")
                exit(a == b ? 0 : 1)
            default:
                print("usage: launch-video frames <dir> | still <n> <file> | same <n>")
            }
        }
    }
}
