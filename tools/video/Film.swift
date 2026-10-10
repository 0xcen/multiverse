import SwiftUI

// The launch film: one timeline for picture and sound. Read RULES.md first.

let fps = 30.0

/// Every beat's start, in seconds. Picture and sound both read these, so they can't drift apart.
enum T {
    static let duration = 22.0
    static let lives = 2.0
    static let menu = 4.0
    static let cuts = 6.6
    static let workRoute = 9.0
    static let personalRoute = 12.0
    static let both = 14.4
    static let gather = 16.2
    static let end = 17.7

    // Inside beats
    static let split = 0.3, invert = 0.62          // after 0
    static let menuOpen = menu + 0.42
    static let hoverSlack = menu + 1.35, hoverPersonal = menu + 1.85
    static let card2 = cuts + 0.6, dock = cuts + 1.2
    static let morphEnd = gather + 1.0
    static let plateLand = gather + 1.32
}

/// When things happen inside a route beat. `k` < 1 plays it faster.
struct RouteTimes {
    let start: Double, k: Double
    func at(_ x: Double) -> Double { start + x * k }
    var cursor: (Double, Double) { (at(0.1), at(0.75)) }
    var click: Double { at(0.82) }
    var leg1: (Double, Double) { (at(0.95), at(1.6)) }
    var leg2: (Double, Double) { (at(1.6), at(2.25)) }
    var open: Double { at(2.15) }
    var caption: Double { at(2.4) }
}
let workTimes = RouteTimes(start: T.workRoute, k: 1)
let personalTimes = RouteTimes(start: T.personalRoute, k: 0.85)

let frameCount = Int(fps * T.duration)

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
        case ..<T.lives: oneBecomesTwo
        case ..<T.menu: differentLives
        case ..<T.cuts: meetMultiverse
        case ..<T.workRoute: copiesCuts
        case ..<T.personalRoute: route(personal: false, times: workTimes)
        case ..<T.both: route(personal: true, times: personalTimes)
        case ..<T.gather: bothRoutes
        case ..<T.end: gatherIntoIcon
        default: endCard
        }
    }

    // MARK: Beats

    private var oneBecomesTwo: some View {
        let appear = snap(prog(t, 0, 0.3))
        let split = pop(prog(t, T.split, T.split + 0.32)), invert = snap(prog(t, T.invert, T.invert + 0.2))
        return ZStack {
            ZStack {
                Tile(app: "Slack", size: 220)
                Tile(app: "Slack", ivory: true, size: 220).opacity(invert)
            }
            .position(x: 960 + 200 * split, y: 470)
            Tile(app: "Slack", size: 220).position(x: 960 - 200 * split, y: 470)
            Caption(text: "Same app.", opacity: snap(prog(t, 0.55, 0.8))).position(x: 960, y: 800)
        }
        .opacity(appear)
        .scaleEffect(mix(0.9, 1, appear))
    }

    private var differentLives: some View {
        let s = T.lives
        let g = snap(prog(t, s, s + 0.45)), content = prog(t, s + 0.2, s + 0.45)
        let left = mix(CGRect(x: 650, y: 360, width: 220, height: 220), CGRect(x: 120, y: 190, width: 820, height: 560), g)
        let right = mix(CGRect(x: 1050, y: 360, width: 220, height: 220), CGRect(x: 980, y: 190, width: 820, height: 560), g)
        return ZStack(alignment: .topLeading) {
            workChat.opacity(content).overlay(Tile(app: "Slack", size: 220).opacity(1 - content).scaleEffect(1 - g * 0.3))
                .frame(width: left.width, height: left.height).position(x: left.midX, y: left.midY)
            personalChat.opacity(content).overlay(Tile(app: "Slack", ivory: true, size: 220).opacity(1 - content).scaleEffect(1 - g * 0.3))
                .frame(width: right.width, height: right.height).position(x: right.midX, y: right.midY)
            Caption(text: "Different lives.", opacity: snap(prog(t, s + 0.5, s + 0.75))).position(x: 960, y: 900)
        }
    }

    private var workChat: some View {
        Window(title: "Slack — Acme") {
            ChatApp(workspace: "Acme", account: "sam@acme.com", channel: "launch",
                    messages: [("Priya", "Review moved to 3pm", nil), ("Leo", "Spec is here:", "linear.app/acme/ENG-212")])
        }
    }

    private var personalChat: some View {
        Window(title: "Personal Slack — Family", ivory: true) {
            ChatApp(workspace: "Family", account: "sam@gmail.com", channel: "weekend",
                    messages: [("Mum", "Dinner on Sunday?", nil), ("Alex", "This for Saturday?", "airbnb.com/rooms/48213")], ivory: true)
        }
    }

    private var meetMultiverse: some View {
        let s = T.menu
        let z = snap(prog(t, s, s + 0.5)), menu = snap(prog(t, T.menuOpen, T.menuOpen + 0.2))
        let highlight: String? = t > T.hoverPersonal ? "Personal Slack" : (t > T.hoverSlack ? "Slack" : nil)
        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                workChat.frame(width: 820, height: 560).position(x: 530, y: 470)
                personalChat.frame(width: 820, height: 560).position(x: 1390, y: 470)
            }
            .scaleEffect(mix(1, 0.62, z), anchor: .bottom)
            .opacity(mix(1, 0.55, z))
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
                .scaleEffect(mix(0.96, 1.5, menu), anchor: .top)
                .opacity(menu)
                .position(x: 1560, y: 330)
            Caption(text: "Meet Multiverse.", opacity: snap(prog(t, s + 0.7, s + 0.95))).position(x: 560, y: 260)
        }
    }

    @ViewBuilder private var copiesCuts: some View {
        if t < T.card2 { copyCard(app: "Slack", name: "Personal Slack", start: T.cuts) }
        else if t < T.dock { copyCard(app: "Notion", name: "Personal Notion", start: T.card2) }
        else { dock }
    }

    private func copyCard(app: String, name: String, start: Double) -> some View {
        let p = pop(prog(t, start, start + 0.25)), words = snap(prog(t, start + 0.08, start + 0.3))
        return HStack(spacing: 56) {
            HStack(spacing: 24) {
                Tile(app: app, size: 200)
                Image(systemName: "arrow.right").font(.system(size: 44, weight: .light)).foregroundStyle(Carbon.muted)
                Tile(app: app, ivory: true, size: 200).scaleEffect(mix(0.8, 1, p))
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(name).font(.system(size: 84, weight: .medium)).tracking(-3).foregroundStyle(Carbon.ivory)
                Text("Copy of \(app) · own logins").font(.system(size: 34)).foregroundStyle(Carbon.muted)
            }
            .opacity(words).offset(x: CGFloat(1 - words) * 30)
        }
        .frame(width: stage.width, height: stage.height)
    }

    static let dockItems: [(String, Bool)] = [("Slack", false), ("Slack", true), ("Notion", false), ("Notion", true),
                                              ("Google Chrome", false), ("Dia", true)]

    private var dock: some View {
        VStack(spacing: 46) {
            Caption(text: "Both, side by side.", opacity: snap(prog(t, T.dock + 0.4, T.dock + 0.65)))
            HStack(spacing: 22) {
                ForEach(Array(Self.dockItems.enumerated()), id: \.offset) { i, item in
                    let p = pop(prog(t, T.dock + Double(i) * 0.06, T.dock + 0.24 + Double(i) * 0.06))
                    VStack(spacing: 10) {
                        Tile(app: item.0, ivory: item.1, size: 130)
                        Circle().fill(Carbon.muted).frame(width: 7, height: 7)
                    }
                    .scaleEffect(mix(0.5, 1, p)).opacity(min(1, p * 2))
                }
            }
            .padding(.horizontal, 30).padding(.vertical, 22)
            .background(RoundedRectangle(cornerRadius: 34).fill(Carbon.panel))
            .overlay(RoundedRectangle(cornerRadius: 34).stroke(Carbon.border))
        }
        .frame(width: stage.width, height: stage.height)
    }

    private func route(personal: Bool, times rt: RouteTimes) -> some View {
        let appear = snap(prog(t, rt.start, rt.at(0.25)))
        let cursorIn = snap(prog(t, rt.cursor.0, rt.cursor.1))
        let click = prog(t, rt.click, rt.click + 0.3)
        let leg1 = ease(prog(t, rt.leg1.0, rt.leg1.1)), leg2 = ease(prog(t, rt.leg2.0, rt.leg2.1))
        let open = pop(prog(t, rt.open, rt.open + 0.3))
        let appRect = CGRect(x: 70, y: 260, width: 640, height: 470)
        let linkPoint = CGPoint(x: 470, y: 541)
        let lineStart = CGPoint(x: personal ? 640 : 620, y: 541)
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
                .scaleEffect(leg1 >= 1 ? mix(1.08, 1, snap(prog(t, rt.leg1.1, rt.leg1.1 + 0.25))) : 1)
                .position(nodePoint)
            Window(title: personal ? "Personal Dia" : "Chrome", ivory: personal) {
                BrowserPage(url: personal ? "airbnb.com/rooms/48213" : "linear.app/acme/ENG-212", ivory: personal)
            }
            .frame(width: browserRect.width, height: browserRect.height)
            .position(x: browserRect.midX, y: browserRect.midY)
            .opacity(min(1, open * 2)).scaleEffect(mix(0.9, 1, open))
            RoundedRectangle(cornerRadius: 16).stroke(Carbon.border, style: StrokeStyle(lineWidth: 1.5, dash: [8, 8]))
                .frame(width: browserRect.width, height: browserRect.height)
                .position(x: browserRect.midX, y: browserRect.midY).opacity(open > 0 ? 0 : 1)
            Cursor().position(mix(CGPoint(x: linkPoint.x + 260, y: 980), CGPoint(x: linkPoint.x + 14, y: linkPoint.y + 18), cursorIn))
                .scaleEffect(t >= rt.click && t < rt.click + 0.08 ? 0.9 : 1)
                .opacity(1 - prog(t, rt.at(1.3), rt.at(1.55)))
            Circle().stroke(Carbon.ivory.opacity(1 - click), lineWidth: 2)
                .frame(width: 12 + 60 * click, height: 12 + 60 * click).position(linkPoint).opacity(click > 0 ? 1 : 0)
            Caption(text: personal ? "Personal → Personal Dia." : "Work → Chrome.", opacity: snap(prog(t, rt.caption, rt.caption + 0.25)))
                .position(x: 960, y: 900)
        }
        .opacity(appear)
    }

    private var workChatSmall: some View { workChat }
    private var personalChatSmall: some View { personalChat }

    private var bothRoutes: some View {
        let appear = snap(prog(t, T.both, T.both + 0.3))
        return ZStack(alignment: .topLeading) {
            routeRow(y: 380, app: "Slack", ivory: false, node: "Work", dot: Carbon.ivory, browser: "Google Chrome", label: "Chrome",
                     draw: ease(prog(t, T.both, T.both + 0.5)))
            routeRow(y: 640, app: "Slack", ivory: true, node: "Personal", dot: Carbon.olive, browser: "Dia", label: "Personal Dia",
                     draw: ease(prog(t, T.both + 0.12, T.both + 0.62)))
            Caption(text: "Personal stays personal.", opacity: snap(prog(t, T.both + 0.45, T.both + 0.7))).position(x: 960, y: 170)
        }
        .opacity(appear)
    }

    private func routeRow(y: CGFloat, app: String, ivory: Bool, node: String, dot: Color, browser: String, label: String,
                          draw: Double = 1) -> some View {
        ZStack(alignment: .topLeading) {
            Route(from: CGPoint(x: 470, y: y), to: CGPoint(x: 800, y: y), progress: draw, pulse: false)
            Route(from: CGPoint(x: 1120, y: y), to: CGPoint(x: 1400, y: y), progress: draw, pulse: false)
            Tile(app: app, ivory: ivory, size: 120).position(x: 400, y: y)
            Node(name: node, dot: dot).position(x: 960, y: y)
            HStack(spacing: 16) {
                Tile(app: browser, ivory: ivory, size: 120)
                Text(label).font(.system(size: 30)).foregroundStyle(Carbon.ivory).fixedSize()
            }
            .position(x: 1560, y: y)
        }
    }

    // Snappy: rows clear in 0.3 s, become panes in under a second, the plate lands with a bounce.
    private var gatherIntoIcon: some View {
        let fadeRows = prog(t, T.gather, T.gather + 0.3)
        let morph = ease(prog(t, T.gather + 0.05, T.morphEnd))
        let plate = pop(prog(t, T.morphEnd - 0.05, T.plateLand))
        let iconSize: CGFloat = 300
        let center = CGPoint(x: 960, y: 500)
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
                .position(center).opacity(min(1, plate * 3)).scaleEffect(mix(0.6, 1, plate))
            Quad(points: front).fill(Carbon.ivory.opacity(mix(0.1, 1, morph)))
            Quad(points: back).fill(Carbon.gray.opacity(mix(0.1, 1, morph)))
        }
    }

    private var endCard: some View {
        let s = T.end
        let lift = snap(prog(t, s, s + 0.35)), words = snap(prog(t, s + 0.12, s + 0.42)), line = snap(prog(t, s + 0.3, s + 0.6))
        // The icon picks up exactly where the fold left it (centre 960×500, 300 pt), then lifts.
        return ZStack(alignment: .topLeading) {
            Image(nsImage: Carbon.appIcon).resizable().frame(width: 300, height: 300)
                .scaleEffect(mix(1, 0.72, lift))
                .position(x: 960, y: mix(500, 360, lift))
            Text("Multiverse").font(.system(size: 110, weight: .medium)).tracking(-4).foregroundStyle(Carbon.ivory)
                .opacity(words).position(x: 960, y: 610 + CGFloat(1 - words) * 24)
            Text("One Mac. Different universes.").font(.system(size: 46)).tracking(-1).foregroundStyle(Carbon.muted)
                .opacity(line).position(x: 960, y: 715 + CGFloat(1 - line) * 18)
        }
    }
}
