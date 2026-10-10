import SwiftUI

/// Automation permission (Apple Events) for sending links to a browser profile.
enum Automation {
    enum State { case allowed, denied, notAsked, notRunning }

    /// With `ask`, macOS shows its "Multiverse wants to control …" prompt if it hasn't yet.
    /// Blocks until the user answers, so call it off the main thread when asking.
    static func state(for bundleID: String, ask: Bool) -> State {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return .notRunning }
        switch AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask) {
        case noErr: return .allowed
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(procNotFound): return .notRunning
        default: return .notAsked
        }
    }

    /// Browsers that links are handed to with an Apple Event (universes using a profile folder).
    static func targets(in config: Config) -> [(name: String, bundleID: String, path: String)] {
        var seen = Set<String>()
        return config.universes.compactMap { u in
            guard u.browser.dataDir != nil,
                  let id = Bundle(url: URL(fileURLWithPath: expand(u.browser.appPath)))?.bundleIdentifier,
                  seen.insert(id).inserted else { return nil }
            return (appName(u.browser.appPath), id, u.browser.appPath)
        }
    }
}

private let onboardedKey = "onboardingCompleted"

/// First launch shows setup; afterwards it's in the menu.
@MainActor func showOnboardingIfNeeded() -> Bool {
    guard !UserDefaults.standard.bool(forKey: onboardedKey) else { return false }
    showOnboarding()
    return true
}

@MainActor private var onboardingWindow: NSWindow?

@MainActor func showOnboarding() {
    if onboardingWindow == nil {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.title = "Set up Multiverse"
        window.contentViewController = NSHostingController(rootView: OnboardingView {
            UserDefaults.standard.set(true, forKey: onboardedKey)
            onboardingWindow?.close()
            showSettings()
        }.environmentObject(Store.shared))
        window.setContentSize(NSSize(width: 620, height: 560))
        window.isReleasedWhenClosed = false
        window.center()
        onboardingWindow = window
    }
    NSApp.activate()
    onboardingWindow?.makeKeyAndOrderFront(nil)
    onboardingWindow?.orderFrontRegardless()
}

struct OnboardingView: View {
    @EnvironmentObject var store: Store
    let finish: () -> Void
    @State private var step: Int

    init(startAt step: Int = 0, finish: @escaping () -> Void) {
        self.finish = finish
        _step = State(initialValue: step)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch step {
                case 0: WelcomeStep()
                case 1: UniversesStep()
                default: PermissionsStep()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider().padding(.horizontal, -32).padding(.bottom, 14)
            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<3) { i in
                        Circle().fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if step > 0 { Button("Back") { step -= 1 } }
                if step < 2 {
                    Button("Continue") { step += 1 }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(step == 1 && store.config.universes.isEmpty)
                } else {
                    Button("Done") { finish() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .padding(.bottom, 22)
        .frame(width: 620, height: 560)
    }
}

// MARK: Step 1

private struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
            Text("Keep work and personal apart").font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 16) {
                Point(symbol: "circle.hexagongrid", title: "Universes",
                      text: "Group your apps into universes, like 💼 Work and 🏠 Personal.")
                Point(symbol: "square.on.square", title: "Separate copies",
                      text: "Use the same app in both, with separate logins and its own icon in the Dock.")
                Point(symbol: "link", title: "Links go to the right browser",
                      text: "A link you click in a work app opens in your work browser, and so on.")
            }
            Text("Setup takes a minute. macOS asks you to confirm a few things along the way; the next steps say what and why.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct Point: View {
    let symbol: String, title: String, text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Color.accentColor).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: Step 2

private struct UniversesStep: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your universes").font(.largeTitle.bold())
            if store.config.universes.isEmpty {
                Text("Start with two. You can rename them, add more and add apps afterwards.")
                    .foregroundStyle(.secondary)
                Button("Create 💼 Work and 🏠 Personal") { createDefaults() }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
            } else {
                Text("Pick the browser each universe's links open in. Apps, separate copies and separate browsers can be added in Settings.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 0) {
                    ForEach($store.config.universes) { $u in
                        HStack {
                            Text("\(u.emoji) \(u.name)").font(.headline)
                            if store.config.defaultUniverse?.id == u.id {
                                Image(systemName: "star.fill").font(.caption).foregroundStyle(.secondary)
                                    .help("Links from apps that aren't in any universe open here")
                            }
                            Spacer()
                            BrowserPicker(universe: $u)
                        }
                        .padding(12)
                        if u.id != store.config.universes.last?.id { Divider() }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
            }
        }
    }

    private func createDefaults() {
        let browser = installedBrowsers().first { appName($0.path) == "Safari" } ?? installedBrowsers().first
        let target = BrowserTarget(appPath: browser?.path ?? "/Applications/Safari.app")
        let work = Universe(name: "Work", emoji: "💼", browser: target, color: Universe.palette[0])
        let personal = Universe(name: "Personal", emoji: "🏠", browser: target, color: Universe.palette[2])
        store.config.universes = [work, personal]
        store.config.defaultUniverseID = work.id
    }
}

// MARK: Step 3

private struct PermissionsStep: View {
    @EnvironmentObject var store: Store
    @State private var automation: [String: Automation.State] = [:]
    @State private var asking: String?

    var body: some View {
        let targets = Automation.targets(in: store.config)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Permissions").font(.largeTitle.bold())
                Text("Multiverse only asks for what it uses. Each of these is a one-time macOS prompt.")
                    .foregroundStyle(.secondary)

                PermissionRow(
                    symbol: "link", title: "Default browser",
                    why: "Multiverse receives every link you click and passes it to the right universe's browser. Nothing else changes about your browsers.",
                    status: store.routingOn ? .done : .needed,
                    actionTitle: "Turn on"
                ) { store.makeDefaultBrowser() }

                ForEach(targets, id: \.bundleID) { t in
                    PermissionRow(
                        symbol: "arrow.up.forward.app", title: "Send links to \(t.name) profiles",
                        why: "To open a link in a specific \(t.name) profile, Multiverse hands it to that window. macOS asks “Multiverse wants to control \(t.name)”: click Allow.",
                        status: status(automation[t.bundleID]),
                        actionTitle: automation[t.bundleID] == .notRunning ? "Open \(t.name)" : "Allow",
                        busy: asking == t.bundleID
                    ) { ask(t) }
                }

                PermissionRow(
                    symbol: "app.badge.checkmark", title: "Update app copies",
                    why: "When you update a copy, macOS may say Multiverse was prevented from modifying apps. Turn Multiverse on under Privacy & Security → App Management, then try again.",
                    status: .optional, actionTitle: "Open Settings"
                ) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")!)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("What your copies will ask", systemImage: "info.circle").font(.headline)
                    Text("macOS treats each copy as a new app, so the first time it opens it asks again for what the original had:")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• **“… Safe Storage” in your keychain**: enter your Mac password and click Always Allow, or it can't keep you signed in.")
                        Text("• **Folders, camera, microphone, screen recording**: allow what you'd allow the original.")
                    }
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
            }
            .padding(.bottom, 16)
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshRouting()
            refresh()
        }
    }

    private func status(_ s: Automation.State?) -> PermissionRow.Status {
        switch s {
        case .allowed: .done
        case .denied: .denied
        default: .needed
        }
    }

    private func refresh() {
        let targets = Automation.targets(in: store.config)
        Task.detached {
            var out: [String: Automation.State] = [:]
            for t in targets { out[t.bundleID] = Automation.state(for: t.bundleID, ask: false) }
            let result = out
            await MainActor.run { automation = result }
        }
    }

    private func ask(_ t: (name: String, bundleID: String, path: String)) {
        if automation[t.bundleID] == .denied {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
            return
        }
        asking = t.bundleID
        Task.detached {
            // The target has to be running for macOS to ask.
            if Automation.state(for: t.bundleID, ask: false) == .notRunning {
                _ = try? await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: expand(t.path)),
                                                                  configuration: NSWorkspace.OpenConfiguration())
                try? await Task.sleep(for: .seconds(2))
            }
            let state = Automation.state(for: t.bundleID, ask: true)
            await MainActor.run {
                automation[t.bundleID] = state
                asking = nil
                showOnboarding()  // come back to the front after the prompt
            }
        }
    }
}

private struct PermissionRow: View {
    enum Status { case done, needed, denied, optional }
    let symbol: String
    let title: String
    let why: String
    let status: Status
    var actionTitle = "Allow"
    var busy = false
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Color.accentColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title).font(.headline)
                    pill
                }
                Text(why).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if busy {
                ProgressView().controlSize(.small)
            } else if status != .done {
                Button(status == .denied ? "Open Settings" : actionTitle, action: action)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
    }

    @ViewBuilder private var pill: some View {
        switch status {
        case .done: Label("Done", systemImage: "checkmark.circle.fill").font(.caption.bold()).foregroundStyle(.green)
        case .needed: Text("Needed").font(.caption.bold()).foregroundStyle(.orange)
        case .denied: Text("Turned off").font(.caption.bold()).foregroundStyle(.red)
        case .optional: Text("Optional").font(.caption.bold()).foregroundStyle(.secondary)
        }
    }
}
