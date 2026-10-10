import SwiftUI

// The launch film: one timeline for picture and sound. Read RULES.md first.

let fps = 30.0

/// Every beat's start, in seconds. Picture and sound both read these, so they can't drift apart.
enum T {
    /// Music tempo: the dots, the groove and the beat grid all use it.
    static let bpm = 96.0, quarter = 60 / bpm

    /// Cold open: a tangled mess of apps snaps into two clean pathways, then the headline holds.
    static let untangle = 1.4, untangled = 2.4
    /// Dots start flowing along the neat lines; one reaches a node every `flowBeat` (an eighth note).
    static let flow = untangle + 0.6, flowBeat = quarter / 2
    static let intro = 5.6

    // Beats. Each is long enough to read its caption: it appears, lands, and holds 1.3 s or more.
    static let lives = intro + 2.4        // "Same app."
    static let menu = lives + 3.1         // "Different lives." and two chats
    static let cuts = menu + 3.4          // "Meet Multiverse." and the menu
    static let card2 = cuts + 1.9         // each card: name + "Copy of … · own logins"
    static let dock = cuts + 3.8
    static let workRoute = cuts + 6.1     // "Both, side by side."
    static let personalRoute = workRoute + 4.3
    static let sideRoute = personalRoute + 3.8
    static let both = sideRoute + 4.0
    static let gather = both + 3.0        // "Every link in its own universe."
    static let end = gather + 1.6
    static let duration = end + 4.4

    // Inside beats
    static let split = intro + 0.3, invert = intro + 0.62
    static let menuOpen = menu + 0.42
    static let hoverSlack = menu + 1.6, hoverPersonal = menu + 2.3
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
    var caption: Double { at(2.15) }  // with the browser opening, so it has time to be read
}
let workTimes = RouteTimes(start: T.workRoute, k: 1.1)
let personalTimes = RouteTimes(start: T.personalRoute, k: 0.9)
let sideTimes = RouteTimes(start: T.sideRoute, k: 0.9)

/// One universe's route: which app sends the link, where it goes.
enum Lane: CaseIterable {
    case work, personal, side
    var node: String { ["Work", "Personal", "Side project"][index] }
    var dot: Color { [Carbon.ivory, Carbon.olive, Carbon.gray][index] }
    var ivory: Bool { self == .personal }
    var app: String { ["Claude", "ChatGPT", "Cursor"][index] }
    var appLabel: String { ["Claude", "Personal ChatGPT", "Side project Cursor"][index] }
    var browser: String { ["Google Chrome", "Dia", "Dia"][index] }
    var browserLabel: String { ["Chrome", "Dia", "Side project Dia"][index] }
    var url: String { ["docs.acme.dev/limits", "airbnb.com/rooms/48213", "vercel.com/docs/deploy"][index] }
    var times: RouteTimes { [workTimes, personalTimes, sideTimes][index] }
    /// Where the link text ends in the app window (the line starts there).
    var linkEndX: CGFloat { [582, 622, 600][index] }
    private var index: Int { Lane.allCases.firstIndex(of: self)! }
}

let frameCount = Int((fps * T.duration).rounded())

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
        case ..<T.intro: coldOpen
        case ..<T.lives: oneBecomesTwo
        case ..<T.menu: differentLives
        case ..<T.cuts: meetMultiverse
        case ..<T.workRoute: copiesCuts
        case ..<T.personalRoute: route(.work)
        case ..<T.sideRoute: route(.personal)
        case ..<T.both: route(.side)
        case ..<T.gather: bothRoutes
        case ..<T.end: gatherIntoIcon
        default: endCard
        }
    }

    // MARK: Beats

    /// The apps in the cold open: each as a Work tile and an ivory Personal copy.
    static let openApps = ["Claude", "ChatGPT", "Cursor", "Google Chrome", "Dia", "Arc",
                           "Granola", "Notion", "Linear", "Figma", "Slack", "Telegram"]

    /// Fixed pseudo-random numbers in 0…1 (same every render).
    static func rand(_ i: Int, _ k: Int) -> Double {
        var x = UInt64(i &* 7919 &+ k &* 104729 &+ 17)
        x ^= x >> 33; x = x &* 0xff51afd7ed558ccd; x ^= x >> 33; x = x &* 0xc4ceb9fe1a85ec53; x ^= x >> 33
        return Double(x % 10_000) / 10_000
    }

    /// 0–1.3 s chaos, 1.3–2.3 s it snaps into two rows whose lines fan into Work and Personal, then clears.
    private var coldOpen: some View {
        let order = snap(prog(t, T.untangle, T.untangle + 0.55))
        let nodes = pop(prog(t, T.untangle + 0.35, T.untangle + 0.65))
        let leave = prog(t, T.intro - 0.35, T.intro)
        let count = Self.openApps.count * 2
        let workNode = CGPoint(x: 1000, y: 312), personalNode = CGPoint(x: 1000, y: 768)
        func tile(_ i: Int) -> (app: String, ivory: Bool) { (Self.openApps[i % Self.openApps.count], i >= Self.openApps.count) }
        func chaosPoint(_ i: Int) -> CGPoint {
            let base = CGPoint(x: 120 + Self.rand(i, 1) * 1680, y: 110 + Self.rand(i, 2) * 860)
            let drift = CGPoint(x: (Self.rand(i, 3) - 0.5) * 160, y: (Self.rand(i, 4) - 0.5) * 120)
            return CGPoint(x: base.x + drift.x * t, y: base.y + drift.y * t)
        }
        func orderPoint(_ i: Int) -> CGPoint {
            // Each universe as a 4×3 grid on the left; its lines fan out to its node.
            let group = i / Self.openApps.count, g = i % Self.openApps.count
            return CGPoint(x: 170 + CGFloat(g % 4) * 112, y: (group == 0 ? 200 : 656) + CGFloat(g / 4) * 112)
        }
        // Anticipation: just before the snap everything pulls in toward the middle.
        let gather = sin(.pi / 2 * prog(t, T.untangle - 0.2, T.untangle)) * (1 - prog(t, T.untangle, T.untangle + 0.15))
        func landTime(_ i: Int) -> Double { T.untangle + 0.42 + Double(i % Self.openApps.count) * 0.018 }
        func position(_ i: Int) -> CGPoint {
            // Stagger the snap per tile so it reads as a sweep; travel on arcs; overshoot a little.
            let g = Double(i % Self.openApps.count)
            let local = popSoft(prog(t, T.untangle + g * 0.018, landTime(i)))
            let c = chaosPoint(i)
            let pulled = mix(c, CGPoint(x: 960, y: 540), 0.08 * gather)
            return arc(pulled, orderPoint(i), local, bulge: i % 2 == 0 ? 80 : -80)
        }
        return ZStack(alignment: .topLeading) {
            // Lines: tangled between random tiles, then each runs cleanly to its universe.
            Canvas { ctx, _ in
                for i in 0..<count {
                    let from = position(i)
                    let other = chaosPoint((i * 7 + 5) % count)
                    let target = i < Self.openApps.count ? workNode : personalNode
                    let end = mix(other, CGPoint(x: target.x - 105, y: target.y), order)
                    let wild1 = CGPoint(x: from.x + (Self.rand(i, 5) - 0.5) * 900, y: from.y + (Self.rand(i, 6) - 0.5) * 700)
                    let wild2 = CGPoint(x: end.x + (Self.rand(i, 7) - 0.5) * 900, y: end.y + (Self.rand(i, 8) - 0.5) * 700)
                    let midX = (from.x + end.x) / 2
                    let c1 = mix(wild1, CGPoint(x: midX, y: from.y), order), c2 = mix(wild2, CGPoint(x: midX, y: end.y), order)
                    var p = Path(); p.move(to: from); p.addCurve(to: end, control1: c1, control2: c2)
                    ctx.stroke(p, with: .color(order > 0.5 ? Carbon.ivory.opacity(0.35 + 0.25 * order) : Carbon.muted.opacity(0.45)),
                               lineWidth: mix(1.5, 2, order))
                    // Once ordered, a dot flows along each line. Lines are offset by a quarter period, so
                    // a dot reaches a node every flowBeat seconds (the soundtrack ticks on those).
                    if t > T.flow {
                        let phase = Double(i % 4) / 4
                        let x = ((t - T.flow) / (T.flowBeat * 4) + phase).truncatingRemainder(dividingBy: 1)
                        let fade = min(1, (t - T.flow) / 0.3) * (1 - leave)
                        let dot = bezier(from, c1, c2, end, x)
                        ctx.fill(Path(ellipseIn: CGRect(x: dot.x - 5, y: dot.y - 5, width: 10, height: 10)),
                                 with: .color(Carbon.ivory.opacity(fade * (0.4 + 0.6 * x))))
                    }
                }
            }
            .frame(width: stage.width, height: stage.height)
            ForEach(0..<count, id: \.self) { i in
                let tl = tile(i)
                let land = squash(t - landTime(i), amount: 0.16)
                Tile(app: tl.app, ivory: tl.ivory, size: mix(CGFloat(70 + Self.rand(i, 9) * 50), 92, order))
                    .scaleEffect(x: land.width * (1 - 0.06 * gather), y: land.height * (1 - 0.06 * gather))
                    .rotationEffect(.degrees((Self.rand(i, 10) - 0.5) * 50 * (1 - order) + (Self.rand(i, 11) - 0.5) * 20 * t * (1 - order)))
                    .position(position(i))
            }
            Node(name: "Work", dot: Carbon.ivory).scaleEffect(nodes).opacity(min(1, nodes * 2)).position(workNode)
            Node(name: "Personal", dot: Carbon.olive).scaleEffect(nodes).opacity(min(1, nodes * 2)).position(personalNode)
            let words = snap(prog(t, T.untangle + 0.4, T.untangle + 0.65)), sub = snap(prog(t, T.untangle + 0.55, T.untangle + 0.8))
            VStack(alignment: .leading, spacing: 18) {
                Headline(lines: ["Run copies", "of any app."], size: 96).opacity(words).offset(x: CGFloat(1 - words) * 40)
                Text("Organize your workflow.").font(.system(size: 40)).tracking(-1).foregroundStyle(Carbon.muted)
                    .opacity(sub).offset(x: CGFloat(1 - sub) * 40)
            }
            .fixedSize()
            .position(x: 1530, y: 540)
        }
        .scaleEffect(mix(1.06, 1, snap(prog(t, 0, T.untangle))) * mix(1, 0.92, leave))
        .opacity(1 - leave)
    }

    private var oneBecomesTwo: some View {
        let appear = snap(prog(t, T.intro, T.intro + 0.25))
        let split = pop(prog(t, T.split, T.split + 0.32)), invert = snap(prog(t, T.invert, T.invert + 0.2))
        // Anticipation: the icon squeezes just before it splits. Arcs: both halves travel on curves.
        let wind = sin(.pi * prog(t, T.split - 0.16, T.split + 0.04))
        let landed = squash(t - (T.split + 0.3)), flip = squash(t - (T.invert + 0.12), amount: 0.08)
        let center = CGPoint(x: 960, y: 470)
        return ZStack {
            ZStack {
                Tile(app: "Claude", size: 220)
                Tile(app: "Claude", ivory: true, size: 220).opacity(invert)
            }
            .scaleEffect(x: landed.width * flip.width, y: landed.height * flip.height, anchor: .bottom)
            .position(arc(center, CGPoint(x: 1160, y: 470), split, bulge: -70))
            Tile(app: "Claude", size: 220)
                .scaleEffect(x: landed.width * (1 + 0.06 * wind), y: landed.height * (1 - 0.1 * wind), anchor: .bottom)
                .position(arc(center, CGPoint(x: 760, y: 470), split, bulge: 70))
            Caption(text: "Same app.", opacity: snap(prog(t, T.intro + 0.55, T.intro + 0.9))).position(x: 960, y: 800)
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
            workChat.opacity(content).offset(y: CGFloat(1 - snap(content)) * 18).overlay(Tile(app: "Claude", size: 220).opacity(1 - content).scaleEffect(1 - g * 0.3))
                .frame(width: left.width, height: left.height).position(x: left.midX, y: left.midY)
            personalChat.opacity(content).offset(y: CGFloat(1 - snap(content)) * 18).overlay(Tile(app: "Claude", ivory: true, size: 220).opacity(1 - content).scaleEffect(1 - g * 0.3))
                .frame(width: right.width, height: right.height).position(x: right.midX, y: right.midY)
            Caption(text: "Different lives.", opacity: snap(prog(t, s + 0.5, s + 0.9))).position(x: 960, y: 900)
        }
    }

    private var workChat: some View {
        Window(title: "Claude — Acme") {
            AIChat(app: "Claude", account: "sam@acme.com", plan: "Acme · Team plan",
                   history: ["API rate limits", "Q3 launch plan", "Refactor auth flow"],
                   prompt: "Where are our rate limits documented?",
                   answer: "They're in the platform docs, under Limits:", link: "docs.acme.dev/limits")
        }
    }

    private var personalChat: some View {
        Window(title: "Personal Claude", ivory: true) {
            AIChat(app: "Claude", account: "sam@gmail.com", plan: "Pro plan",
                   history: ["Lisbon weekend", "Sourdough schedule", "Running plan"],
                   prompt: "Find us a place in Lisbon for Saturday",
                   answer: "This one has a terrace and fits four:", link: "airbnb.com/rooms/48213", ivory: true)
        }
    }

    /// Route beat: Personal uses ChatGPT, to show any app works.
    private var personalChatGPT: some View {
        Window(title: "Personal ChatGPT", ivory: true) {
            AIChat(app: "ChatGPT", account: "sam@gmail.com", plan: "Plus plan",
                   history: ["Lisbon weekend", "Birthday ideas", "Sourdough schedule"],
                   prompt: "Find us a place in Lisbon for Saturday",
                   answer: "This one has a terrace and fits four:", link: "airbnb.com/rooms/48213", ivory: true)
        }
    }

    private var meetMultiverse: some View {
        let s = T.menu
        let z = snap(prog(t, s, s + 0.5)), menu = snap(prog(t, T.menuOpen, T.menuOpen + 0.2))
        let highlight: String? = t > T.hoverPersonal ? "Personal Claude" : (t > T.hoverSlack ? "Claude" : nil)
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
            MenuMock(highlight: highlight, reveal: prog(t, T.menuOpen, T.menuOpen + 0.55))
                .scaleEffect(mix(0.96, 1.5, menu), anchor: .top)
                .opacity(menu)
                .position(x: 1560, y: 330)
            Caption(text: "Meet Multiverse.", opacity: snap(prog(t, s + 0.7, s + 1.1))).position(x: 560, y: 260)
        }
    }

    @ViewBuilder private var copiesCuts: some View {
        if t < T.card2 { copyCard(app: "Claude", name: "Personal Claude", start: T.cuts) }
        else if t < T.dock { copyCard(app: "ChatGPT", name: "Personal ChatGPT", start: T.card2) }
        else { dock }
    }

    private func copyCard(app: String, name: String, start: Double) -> some View {
        let p = pop(prog(t, start, start + 0.25)), words = snap(prog(t, start + 0.08, start + 0.3))
        return HStack(spacing: 56) {
            HStack(spacing: 24) {
                Tile(app: app, size: 200)
                Image(systemName: "arrow.right").font(.system(size: 44, weight: .light)).foregroundStyle(Carbon.muted)
                let land = squash(t - (start + 0.22), amount: 0.14)
                Tile(app: app, ivory: true, size: 200).scaleEffect(mix(0.8, 1, p))
                    .scaleEffect(x: land.width, y: land.height, anchor: .bottom)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(name).font(.system(size: 84, weight: .medium)).tracking(-3).foregroundStyle(Carbon.ivory)
                Text("Copy of \(app) · own logins").font(.system(size: 34)).foregroundStyle(Carbon.muted)
            }
            .opacity(words).offset(x: CGFloat(1 - words) * 30)
        }
        .frame(width: stage.width, height: stage.height)
    }

    static let dockItems: [(String, Bool)] = [("Claude", false), ("Claude", true), ("ChatGPT", false), ("ChatGPT", true),
                                              ("Google Chrome", false), ("Dia", true), ("Dia", false)]

    private var dock: some View {
        VStack(spacing: 46) {
            Caption(text: "Both, side by side.", opacity: snap(prog(t, T.dock + 0.4, T.dock + 0.8)))
            HStack(spacing: 22) {
                ForEach(Array(Self.dockItems.enumerated()), id: \.offset) { i, item in
                    let p = pop(prog(t, T.dock + Double(i) * 0.06, T.dock + 0.24 + Double(i) * 0.06))
                    VStack(spacing: 10) {
                        let land = squash(t - (T.dock + 0.22 + Double(i) * 0.06), amount: 0.14)
                        Tile(app: item.0, ivory: item.1, size: 130).scaleEffect(x: land.width, y: land.height, anchor: .bottom)
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

    private func route(_ lane: Lane) -> some View {
        let rt = lane.times
        let appear = snap(prog(t, rt.start, rt.at(0.25)))
        let cursorIn = snap(prog(t, rt.cursor.0, rt.cursor.1))
        let click = prog(t, rt.click, rt.click + 0.3)
        let leg1 = ease(prog(t, rt.leg1.0, rt.leg1.1)), leg2 = ease(prog(t, rt.leg2.0, rt.leg2.1))
        let open = pop(prog(t, rt.open, rt.open + 0.3))
        let appRect = CGRect(x: 70, y: 260, width: 640, height: 470)
        let linkPoint = CGPoint(x: 465, y: 510)                // where the link is clicked
        let lineStart = CGPoint(x: lane.linkEndX, y: 510)       // just after the link text
        let nodePoint = CGPoint(x: 960, y: 495)
        let browserRect = CGRect(x: 1210, y: 260, width: 640, height: 470)
        return ZStack(alignment: .topLeading) {
            appWindow(lane)
                .frame(width: appRect.width, height: appRect.height).position(x: appRect.midX, y: appRect.midY)
                .opacity(1 - 0.5 * prog(t, rt.leg1.0, rt.leg1.1))  // staging: focus follows the link
            // Secondary action: a ring leaves the node when the link reaches it.
            let ring = prog(t, rt.leg1.1, rt.leg1.1 + 0.45)
            Capsule().stroke(lane.dot.opacity(0.6 * (1 - ring)), lineWidth: 2)
                .frame(width: 330 + 120 * CGFloat(ring), height: 74 + 70 * CGFloat(ring))
                .position(nodePoint).opacity(ring > 0 && ring < 1 ? 1 : 0)
            Route(from: lineStart, to: CGPoint(x: nodePoint.x - 172, y: nodePoint.y), progress: leg1)
            Route(from: CGPoint(x: nodePoint.x + 172, y: nodePoint.y), to: CGPoint(x: browserRect.minX - 12, y: browserRect.midY), progress: leg2)
            Node(name: lane.node, dot: lane.dot, lit: leg1 >= 1, width: 320)
                .scaleEffect(leg1 >= 1 ? mix(1.08, 1, snap(prog(t, rt.leg1.1, rt.leg1.1 + 0.25))) : 1)
                .position(nodePoint)
            Window(title: lane.browserLabel, ivory: lane.ivory) {
                BrowserPage(url: lane.url, ivory: lane.ivory, load: prog(t, rt.open + 0.1, rt.open + 0.65))
            }
            .frame(width: browserRect.width, height: browserRect.height)
            .position(x: browserRect.midX, y: browserRect.midY)
            .opacity(min(1, open * 2)).scaleEffect(mix(0.9, 1, open))
            .scaleEffect(x: squash(t - (rt.open + 0.28), amount: 0.04).width, y: squash(t - (rt.open + 0.28), amount: 0.04).height)
            RoundedRectangle(cornerRadius: 16).stroke(Carbon.border, style: StrokeStyle(lineWidth: 1.5, dash: [8, 8]))
                .frame(width: browserRect.width, height: browserRect.height)
                .position(x: browserRect.midX, y: browserRect.midY).opacity(open > 0 ? 0 : 1)
            Cursor().position(arc(CGPoint(x: linkPoint.x + 260, y: 980), CGPoint(x: linkPoint.x + 14, y: linkPoint.y + 18), cursorIn, bulge: 90))
                .scaleEffect(t >= rt.click && t < rt.click + 0.08 ? 0.9 : 1)
                .opacity(1 - prog(t, rt.at(1.3), rt.at(1.55)))
            Circle().stroke((lane.ivory ? ink : Carbon.ivory).opacity(1 - click), lineWidth: 2)
                .frame(width: 12 + 60 * click, height: 12 + 60 * click).position(linkPoint).opacity(click > 0 ? 1 : 0)
            Caption(text: "\(lane.node) → \(lane.browserLabel).", opacity: snap(prog(t, rt.caption, rt.caption + 0.45)))
                .position(x: 960, y: 900)
        }
        .opacity(appear)
    }

    @ViewBuilder private func appWindow(_ lane: Lane) -> some View {
        switch lane {
        case .work: workChat
        case .personal: personalChatGPT
        case .side:
            Window(title: "Side project Cursor") {
                AIChat(app: "Cursor", account: "sam@indie.dev", plan: "Pro plan",
                       history: ["Deploy the app", "Fix login bug", "Add dark mode"],
                       prompt: "How do I deploy this?",
                       answer: "Vercel's guide covers it step by step:", link: "vercel.com/docs/deploy")
            }
        }
    }

    private var bothRoutes: some View {
        let appear = snap(prog(t, T.both, T.both + 0.3))
        return ZStack(alignment: .topLeading) {
            ForEach(Array(Lane.allCases.enumerated()), id: \.offset) { i, lane in
                routeRow(y: 350 + CGFloat(i) * 210, lane: lane,
                         draw: ease(prog(t, T.both + Double(i) * 0.1, T.both + 0.5 + Double(i) * 0.1)))
            }
            Caption(text: "Every link in its own universe.", opacity: snap(prog(t, T.both + 0.45, T.both + 0.9))).position(x: 960, y: 170)
        }
        .opacity(appear)
    }

    private func routeRow(y: CGFloat, lane: Lane, draw: Double = 1) -> some View {
        // Fixed columns: app tile, node (one width for all), browser tile; labels start after the browser
        // tile, so long names never shift the tiles. Lines run exactly edge to edge.
        let appX: CGFloat = 400, nodeX: CGFloat = 960, browserX: CGFloat = 1500, tile: CGFloat = 120, nodeW: CGFloat = 320
        return ZStack(alignment: .topLeading) {
            Route(from: CGPoint(x: appX + tile / 2 + 12, y: y), to: CGPoint(x: nodeX - nodeW / 2 - 12, y: y), progress: draw, pulse: false)
            Route(from: CGPoint(x: nodeX + nodeW / 2 + 12, y: y), to: CGPoint(x: browserX - tile / 2 - 12, y: y), progress: draw, pulse: false)
            Tile(app: lane.app, ivory: lane.ivory, size: tile).position(x: appX, y: y)
            Node(name: lane.node, dot: lane.dot, width: nodeW).position(x: nodeX, y: y)
            Tile(app: lane.browser, ivory: lane.ivory, size: tile).position(x: browserX, y: y)
            Text(lane.browserLabel).font(.system(size: 30)).foregroundStyle(Carbon.ivory).fixedSize()
                .frame(width: 360, alignment: .leading)
                .position(x: browserX + tile / 2 + 24 + 180, y: y)
        }
    }

    // Snappy: rows clear in 0.3 s, become panes in under a second, the plate lands with a bounce.
    private var gatherIntoIcon: some View {
        let fadeRows = prog(t, T.gather, T.gather + 0.3)
        let morph = anticipate(prog(t, T.gather + 0.05, T.morphEnd), back: 1.1)
        let plate = pop(prog(t, T.morphEnd - 0.05, T.plateLand))
        let iconSize: CGFloat = 300
        let center = CGPoint(x: 960, y: 500)
        let unit = iconSize * 36 / 1024
        func iconPoint(_ p: CGPoint) -> CGPoint { CGPoint(x: center.x + (p.x - 10.5) * unit, y: center.y + (p.y - 11.5) * unit) }
        func rectCorners(_ r: CGRect) -> [CGPoint] {
            [CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY)]
        }
        // Work and Side project fold into the gray pane, Personal into the ivory one.
        let workRow = CGRect(x: 320, y: 270, width: 1320, height: 160), personalRow = CGRect(x: 320, y: 480, width: 1320, height: 160)
        let sideRow = CGRect(x: 320, y: 690, width: 1320, height: 160)
        let back = zip(rectCorners(workRow), Panes.corners(front: false).map(iconPoint)).map { mix($0, $1, morph) }
        let side = zip(rectCorners(sideRow), Panes.corners(front: false).map(iconPoint)).map { mix($0, $1, morph) }
        let front = zip(rectCorners(personalRow), Panes.corners(front: true).map(iconPoint)).map { mix($0, $1, morph) }
        let land = squash(t - T.plateLand, amount: 0.16)
        return ZStack(alignment: .topLeading) {
            bothRoutes.opacity(1 - fadeRows)
            ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: iconSize * 210 / 1024, style: .continuous)
                .fill(Carbon.graphite)
                .frame(width: iconSize * 928 / 1024, height: iconSize * 928 / 1024)
                .position(center).opacity(min(1, plate * 3)).scaleEffect(mix(0.6, 1, plate))
            Quad(points: front).fill(Carbon.ivory.opacity(mix(0.1, 1, morph)))
            Quad(points: side).fill(Carbon.gray.opacity(mix(0.1, 1, morph)))
            Quad(points: back).fill(Carbon.gray.opacity(mix(0.1, 1, morph)))
            }
            .frame(width: stage.width, height: stage.height)
            .scaleEffect(x: land.width, y: land.height, anchor: UnitPoint(x: 0.5, y: (500 + 136) / 1080))
        }
    }

    private var endCard: some View {
        let s = T.end
        let lift = anticipate(prog(t, s, s + 0.42), back: 1.2)
        let words = snap(prog(t, s + 0.16, s + 0.46)), line = prog(t, s + 0.32, s + 0.7)
        // The icon picks up exactly where the fold left it (centre 960×500, 300 pt), then lifts.
        return ZStack(alignment: .topLeading) {
            Image(nsImage: Carbon.appIcon).resizable().frame(width: 300, height: 300)
                .scaleEffect(mix(1, 0.72, lift))
                .position(x: 960, y: mix(500, 360, lift))
            Text("Multiverse").font(.system(size: 110, weight: .medium)).tracking(-4).foregroundStyle(Carbon.ivory)
                .opacity(words).position(x: 960, y: 610 + CGFloat(1 - words) * 24)
            let tagline = ["One", "Mac.", "Different", "universes."]
            HStack(spacing: 12) {
                ForEach(Array(tagline.enumerated()), id: \.offset) { i, w in
                    let p = min(1, max(0, line * 1.5 - Double(i) * 0.16))
                    Text(w).font(.system(size: 46)).tracking(-1).foregroundStyle(Carbon.muted)
                        .opacity(p).offset(y: CGFloat(1 - snap(p)) * 16)
                }
            }
            .fixedSize()
            .position(x: 960, y: 715)
        }
    }
}
